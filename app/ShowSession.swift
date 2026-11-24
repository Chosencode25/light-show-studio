import AppKit
import AVFoundation
import Observation
import UniformTypeIdentifiers

enum StudioWorkspace: String, CaseIterable, Identifiable {
    case edit = "Program"
    case show = "Show Mode"
    var id: Self { self }
}

enum StudioSelection: Hashable {
    case all, fixture(UUID), group(String)
}

@MainActor @Observable
final class ShowSession {
    private(set) var project = LightShow()
    private(set) var documentURL: URL?
    private(set) var isHome = true
    private(set) var recentShows: [URL] = []
    private(set) var workspace = StudioWorkspace.edit
    var selection = StudioSelection.all
    private var focusedCueID: UUID?
    private(set) var selectedCueIDs: Set<UUID> = []
    var selectedCueID: UUID? {
        get { focusedCueID }
        set { focusedCueID = newValue; selectedCueIDs = newValue.map { [$0] } ?? [] }
    }
    private(set) var waveform: [Float] = []
    var nextCueID: UUID?
    private var lastCueID: UUID?
    var message: String?
    private(set) var position = 0.0
    private(set) var playing = false
    private(set) var loadingSong = false
    private(set) var recording = false
    private(set) var take: [LightingCue] = []
    private(set) var reviewingTake = false
    private(set) var ready = false
    let simulation = LightingSimulation()

    private var baseline = LightShow()
    private var undo: [LightShow] = []
    private var redo: [LightShow] = []
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var audioFolder: URL?
    @ObservationIgnored private var soundtrack: Data?
    @ObservationIgnored private var seekID = UUID()
    @ObservationIgnored private var seeking = false
    @ObservationIgnored private var anchorTime = 0.0
    @ObservationIgnored private var anchorPosition = 0.0
    @ObservationIgnored private var waitingSince: Double?
    @ObservationIgnored private let defaults: UserDefaults

    var timelineZoom = 1.0
    var timelineSnapping = true

    var songMuted = false { didSet { player?.isMuted = songMuted } }
    var hasUnsavedChanges: Bool { project != baseline }
    var canUndo: Bool { canEdit && !undo.isEmpty }
    var canRedo: Bool { canEdit && !redo.isEmpty }
    var canEdit: Bool { !isHome && workspace == .edit && !playing && !recording && !loadingSong }
    var canPlay: Bool { !isHome && !loadingSong && (workspace == .edit || ready) }
    var canRecord: Bool {
        !isHome && workspace == .edit && !loadingSong && player != nil && take.isEmpty &&
            (!project.lighting.looks.isEmpty || !project.lighting.cues.isEmpty)
    }
    var selectedFixtures: [PatchedFixture] {
        let fixtures = project.lighting.fixtures
        switch selection {
        case .all: return fixtures
        case .fixture(let id): return fixtures.filter { $0.id == id }
        case .group(let group): return fixtures.filter { $0.group == group }
        }
    }
    var groups: [String] { Set(project.lighting.fixtures.map(\.group)).filter { !$0.isEmpty }.sorted() }
    var cues: [LightingCue] { project.lighting.cues.enumerated().sorted {
        $0.element.time == $1.element.time ? $0.offset < $1.offset : $0.element.time < $1.element.time
    }.map(\.element) }
    var selectedCue: LightingCue? { project.lighting.cues.first { $0.id == selectedCueID } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recentShows = (defaults.stringArray(forKey: "RecentLightShows") ?? []).map { URL(fileURLWithPath: $0) }
        baseline = project
    }

    func newShow(_ show: LightShow = LightShow()) {
        guard confirmLeaving() else { return }
        reset(to: show)
    }

    func showHome() {
        guard confirmLeaving() else { return }
        reset(to: LightShow())
        isHome = true
    }

    func chooseShow() {
        guard let url = openPanel(types: [.lightShow], title: "Open Light Show") else { return }
        open(url)
    }

    func open(_ url: URL) {
        guard confirmLeaving() else { return }
        do { try load(url) }
        catch { message = error.localizedDescription }
    }

    func load(_ url: URL) throws {
        let (show, audio) = try ShowFiles.load(url)
        let prepared = try audio.map(makeAudio)
        reset(to: show)
        if let audio, let prepared { adoptAudio(prepared, track: audio) }
        documentURL = url
        remember(url)
    }

    func chooseSetup() {
        guard let url = openPanel(types: [.lightSetup], title: "Open Fixture Setup") else { return }
        do { newShow(try ShowFiles.loadSetup(url).newShow()) }
        catch { message = error.localizedDescription }
    }

    func saveSetup() {
        guard !isHome, !project.lighting.fixtures.isEmpty,
              let url = savePanel(type: .lightSetup, name: project.name, title: "Save Fixture Setup") else { return }
        do {
            try ShowFiles.saveSetup(FixtureSetup(show: project, name: project.name), to: url)
            message = "Saved fixture setup."
        } catch { message = error.localizedDescription }
    }

    @discardableResult
    func save(asCopy: Bool = false) -> Bool {
        guard !isHome, !loadingSong else { return false }
        guard let url = (asCopy ? nil : documentURL) ?? savePanel(type: .lightShow, name: project.name, title: "Save Light Show") else { return false }
        do {
            try write(url, replacing: true)
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func write(_ url: URL, replacing: Bool = false) throws {
        try ShowFiles.save(project, soundtrack: soundtrack, to: url, replacing: replacing)
        baseline = project
        documentURL = url
        remember(url)
        message = "Saved \(url.deletingPathExtension().lastPathComponent)."
    }

    func confirmLeaving() -> Bool {
        guard !loadingSong else { message = "Wait for the soundtrack to finish loading."; return false }
        guard hasUnsavedChanges || recording || !take.isEmpty || playing else { return true }
        let alert = NSAlert()
        alert.messageText = "Leave this light show?"
        if recording || !take.isEmpty {
            alert.informativeText = "Add the cue take to the timeline to keep it."
            alert.addButton(withTitle: "Keep Working")
            alert.addButton(withTitle: "Discard Take")
            return alert.runModal() == .alertSecondButtonReturn &&
                (!hasUnsavedChanges || confirmSaving())
        }
        if hasUnsavedChanges { return confirmSaving() }
        alert.informativeText = "Simulation and the soundtrack will stop."
        alert.addButton(withTitle: "Stop and Leave")
        alert.addButton(withTitle: "Keep Working")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func confirmSaving() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Save changes to \(project.name)?"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don’t Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return save()
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    private func openPanel(types: [UTType], title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func savePanel(type: UTType, name: String, title: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = name.replacingOccurrences(of: "/", with: "-")
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func remember(_ url: URL) {
        recentShows = Array(([url] + recentShows.filter { $0 != url }).prefix(12))
        defaults.set(recentShows.map(\.path), forKey: "RecentLightShows")
    }

    private func reset(to show: LightShow) {
        stop()
        unloadAudio()
        project = show
        timelineZoom = 1
        baseline = show
        documentURL = nil
        workspace = .edit
        isHome = false
        selection = .all
        selectedCueID = nil
        nextCueID = nil
        lastCueID = nil
        undo.removeAll()
        redo.removeAll()
        take.removeAll()
        reviewingTake = false
        message = nil
        simulation.reset()
        refresh()
    }

    func finish() { stop(); unloadAudio() }

    @discardableResult
    func edit(_ change: (inout LightShow) -> Void) -> Bool {
        guard canEdit else { return false }
        var candidate = project
        change(&candidate)
        do { try candidate.validate() }
        catch { message = error.localizedDescription; return false }
        guard candidate != project else { return true }
        undo.append(project)
        if undo.count > 48 { undo.removeFirst() }
        redo.removeAll()
        project = candidate
        reconcileCueSelection()
        message = nil
        refresh()
        return true
    }

    func undoEdit() {
        guard canUndo, let previous = undo.popLast() else { return }
        redo.append(project)
        project = previous
        reconcileCueSelection()
        refresh()
    }

    func redoEdit() {
        guard canRedo, let next = redo.popLast() else { return }
        undo.append(project)
        project = next
        reconcileCueSelection()
        refresh()
    }

    func rename(_ name: String) {
        edit { $0.name = name.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func addFixture(_ kind: FixtureKind) {
        guard canEdit else { return }
        let lighting = project.lighting
        let size = kind == .movingHead ? 9 : kind == .rgb ? 3 : 1
        var patch: (LightingController, Int)?
        for controller in lighting.controllers where controller.kind == kind.controllerKind {
            let occupied = Set(lighting.fixtures.filter { $0.controllerID == controller.id }.flatMap(\.slots))
            guard controller.capacity >= size else { continue }
            if let address = (1...(controller.capacity - size + 1)).first(where: {
                occupied.isDisjoint(with: $0..<($0 + size))
            }) {
                patch = (controller, address)
                break
            }
        }
        let controller = patch?.0 ?? LightingController(name: kind.controllerKind.rawValue + " Simulation", kind: kind.controllerKind)
        let address = patch?.1 ?? 1
        var fixture = PatchedFixture(name: "\(kind.rawValue) \(lighting.fixtures.count + 1)", kind: kind, controllerID: controller.id)
        fixture.address = address
        fixture.green = address + 1
        fixture.blue = address + 2
        fixture.previewPlacement = .initial(index: lighting.fixtures.count, kind: kind)
        if edit({
            if patch == nil { $0.lighting.controllers.append(controller) }
            $0.lighting.fixtures.append(fixture)
        }) { selection = .fixture(fixture.id) }
    }

    func move(_ fixture: PatchedFixture, to point: FixturePreviewPoint) {
        updateFixture(fixture.id) { current in
            var placement = current.previewPlacement ?? FixturePreviewPlacement(origin: point)
            let dx = point.x - placement.origin.x
            let dy = point.y - placement.origin.y
            func shifted(_ vertex: FixturePreviewPoint) -> FixturePreviewPoint {
                FixturePreviewPoint(x: min(1, max(0, vertex.x + dx)), y: min(1, max(0, vertex.y + dy)))
            }
            placement.origin = point
            placement.stripEnd = placement.stripEnd.map(shifted)
            placement.stripBends = placement.stripBends?.map(shifted)
            current.previewPlacement = placement
        }
    }

    func setStripPath(_ points: [FixturePreviewPoint], for fixtureID: UUID) {
        guard (2...FixturePreviewPlacement.maximumStripPoints).contains(points.count),
              let start = points.first, let end = points.last else { return }
        let bends = points.dropFirst().dropLast()
        let placement = FixturePreviewPlacement(origin: start, stripEnd: end,
                                                 stripBends: bends.isEmpty ? nil : Array(bends))
        updateFixture(fixtureID) { fixture in
            guard fixture.drawsStrip else { return }
            fixture.previewPlacement = placement
        }
    }

    @discardableResult
    func updateFixture(_ id: UUID, _ change: (inout PatchedFixture) -> Void) -> Bool {
        guard let index = project.lighting.fixtures.firstIndex(where: { $0.id == id }) else { return false }
        return edit { change(&$0.lighting.fixtures[index]) }
    }

    @discardableResult
    func applyFixturePatch(_ draft: PatchedFixture) -> Bool {
        updateFixture(draft.id) { current in
            var patch = draft
            patch.previewPlacement = current.previewPlacement
            current = patch
        }
    }

    func removeFixture(_ fixture: PatchedFixture) {
        if edit({ show in
            show.lighting.removeFixture(fixture.id)
            for index in show.chases.indices { show.chases[index].targets.removeAll { $0.id == fixture.id } }
            show.chases.removeAll { $0.targets.isEmpty }
        }) { selection = .all }
    }

    func setController(_ controller: LightingController) {
        edit {
            if let index = $0.lighting.controllers.firstIndex(where: { $0.id == controller.id }) {
                $0.lighting.controllers[index] = controller
            } else { $0.lighting.controllers.append(controller) }
        }
    }

    func removeController(_ controller: LightingController) {
        guard !project.lighting.fixtures.contains(where: { $0.controllerID == controller.id }) else {
            message = "Reassign this controller’s fixtures before removing it."
            return
        }
        edit { $0.lighting.controllers.removeAll { $0.id == controller.id } }
    }

    func effectiveState(_ fixture: PatchedFixture) -> FixtureState {
        simulation.reports[fixture.controllerID]?.fixtures.first { $0.id == fixture.id }?.effective ?? fixture.kind.dark
    }

    func audition(_ fixture: PatchedFixture, state: FixtureState) {
        guard canEdit, state.kind == fixture.kind else { return }
        simulation.resume()
        simulation.override(state, for: fixture)
        refresh()
    }

    func clearAudition() {
        for fixture in project.lighting.fixtures { simulation.override(nil, for: fixture) }
        simulation.clearManualCues()
        refresh()
    }

    func captureLook(_ title: String) {
        let entries = selectedFixtures.map { fixture in
            FixtureLookEntry(id: fixture.id, state: simulation.reports[fixture.controllerID]?.fixtures
                .first { $0.id == fixture.id }?.intended ?? fixture.kind.dark)
        }
        guard !entries.isEmpty else { message = "Select fixtures to capture a look."; return }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        edit { $0.lighting.looks.append(FixtureLook(name: name, entries: entries)) }
    }

    func removeLook(_ look: FixtureLook) {
        edit { $0.lighting.looks.removeAll { $0.id == look.id } }
    }

    func place(_ look: FixtureLook) {
        setCue(LightingCue(name: look.name, time: position, entries: look.entries))
    }

    @discardableResult
    func setCue(_ cue: LightingCue) -> Bool {
        let saved = edit { show in
            if let index = show.lighting.cues.firstIndex(where: { $0.id == cue.id }) {
                let previous = show.lighting.cues[index]
                var revised = cue
                let effectClip = cue.clipDuration != nil &&
                    (cue.timelineCommand == .chase || cue.timelineCommand == .movement || cue.timelineCommand == .fade)
                if !effectClip, cue.entries != previous.entries || cue.lead != previous.lead ||
                    cue.motionCurve != previous.motionCurve || cue.dimmerFade != previous.dimmerFade {
                    revised.timelineCommand = nil
                }
                show.lighting.cues[index] = revised
            } else { show.lighting.cues.append(cue) }
        }
        if saved { selectedCueID = cue.id }
        return saved
    }

    @discardableResult
    func placeTimelineCommand(_ command: FixtureTimelineCommand, fixtureID: UUID, at time: Double) -> Bool {
        let limit = project.song?.duration ?? 3600
        guard canEdit, time.isFinite, (0...limit).contains(time),
              let fixture = project.lighting.fixtures.first(where: { $0.id == fixtureID }),
              command.supports(fixture.kind) else { return false }
        let start = min(time, limit - CueTiming.minimumClipDuration)
        let length = min(CueTiming.defaultClipDuration, limit - start)
        let schedule = LightingSchedule(cues: project.lighting.cues)
        let scheduled = schedule.state(for: fixture, at: start)
        var previous = HeadPositionSchedule(keys: project.lighting.positionKeys)
            .applying(to: scheduled, fixtureID: fixture.id, at: start)
        for clip in schedule.activeClips(for: fixture.id, at: start) {
            previous = LightingSimulation.clipOutput(clip.cue, target: clip.state, over: previous,
                                                     elapsed: start - clip.cue.time)
        }
        let state: FixtureState
        switch command {
        case .chase:
            state = previous
        case .movement:
            guard case .head(var head) = previous else { return false }
            head.pan += head.pan <= 0.75 ? 0.25 : -0.25
            state = .head(head)
        default:
            guard let result = command.state(from: previous) else { return false }
            state = result
        }
        var cue = LightingCue(name: command.rawValue, time: start, entries: [.init(id: fixture.id, state: state)])
        cue.timelineCommand = command
        cue.clipDuration = length
        if command == .fade { cue.dimmerFade = 1 }
        guard setCue(cue) else { return false }
        selection = .fixture(fixture.id)
        return true
    }

    func resizeClip(cueID: UUID, fixtureID: UUID, start: Double, end: Double) {
        guard start.isFinite, end.isFinite,
              let cue = project.lighting.cues.first(where: { $0.id == cueID && $0.clipDuration != nil }),
              let entry = cue.entries.first(where: { $0.id == fixtureID }) else { return }
        var resized = cue
        resized.time = start
        resized.clipDuration = end - start
        saveFixtureCommand(resized, original: cue, entry: entry)
    }

    func moveFixtureCommand(cueID: UUID, fixtureID: UUID, to time: Double) {
        guard time.isFinite, (0...(project.song?.duration ?? 3600)).contains(time),
              let cue = project.lighting.cues.first(where: { $0.id == cueID && !$0.isManual }),
              abs(time - cue.time) > 0.000001,
              let entry = cue.entries.first(where: { $0.id == fixtureID }) else { return }
        var moved = cue
        moved.time = time
        saveFixtureCommand(moved, original: cue, entry: entry)
    }

    private func saveFixtureCommand(_ revised: LightingCue, original: LightingCue, entry: FixtureLookEntry) {
        guard revised != original else { return }
        if original.entries.count == 1 {
            setCue(revised)
            return
        }
        var split = revised
        split.id = UUID()
        split.entries = [entry]
        if edit({ show in
            guard let index = show.lighting.cues.firstIndex(where: { $0.id == original.id }) else { return }
            show.lighting.cues[index].entries.removeAll { $0.id == entry.id }
            show.lighting.cues.append(split)
        }) { selectedCueID = split.id }
    }

    func removeFixtureCommand(cueID: UUID, fixtureID: UUID) {
        guard var cue = project.lighting.cues.first(where: { $0.id == cueID }) else { return }
        cue.entries.removeAll { $0.id == fixtureID }
        if cue.entries.isEmpty { removeCue(cue) }
        else { setCue(cue) }
    }

    func selectCue(_ id: UUID, extending: Bool = false) {
        guard extending else { selectedCueID = id; return }
        if selectedCueIDs.remove(id) != nil {
            if focusedCueID == id { focusedCueID = cues.first { selectedCueIDs.contains($0.id) }?.id }
        } else {
            selectedCueIDs.insert(id)
            focusedCueID = id
        }
    }

    private func reconcileCueSelection() {
        selectedCueIDs.formIntersection(project.lighting.cues.map(\.id))
        if focusedCueID.map({ selectedCueIDs.contains($0) }) != true {
            focusedCueID = cues.first { selectedCueIDs.contains($0.id) }?.id
        }
    }

    func moveSelectedCues(by desired: Double) {
        let selected = project.lighting.cues.filter { selectedCueIDs.contains($0.id) }
        guard !selected.isEmpty, desired.isFinite else { return }
        let offset = CueTiming.boundedOffset(desired, cues: selected, end: project.song?.duration ?? 3600)
        guard abs(offset) > 0.000001 else { return }
        let ids = selectedCueIDs
        edit {
            for index in $0.lighting.cues.indices where ids.contains($0.lighting.cues[index].id) {
                let moved = $0.lighting.cues[index].time + offset
                $0.lighting.cues[index].time = min($0.song?.duration ?? 3600, max(0, moved))
            }
        }
    }

    func duplicateSelectedCues(at time: Double) {
        let selected = cues.filter { selectedCueIDs.contains($0.id) }
        guard let first = selected.first, time.isFinite, (0...3600).contains(time) else { return }
        var copies: [LightingCue] = []
        for cue in selected {
            var copy = cue
            copy.id = UUID()
            copy.time = time + (cue.time - first.time)
            copies.append(copy)
        }
        if edit({ $0.lighting.cues.append(contentsOf: copies) }) {
            selectedCueIDs = Set(copies.map(\.id))
            focusedCueID = copies.first?.id
        }
    }

    func removeSelectedCues() {
        let selected = selectedCueIDs
        if edit({ $0.lighting.cues.removeAll { selected.contains($0.id) } }) { selectedCueID = nil }
    }

    func previewCue(_ cue: LightingCue) {
        guard canEdit, !cue.entries.isEmpty else { return }
        clearAudition()
        _ = trigger(cue)
    }

    func addMarker(_ kind: TimelineMarker.Kind, name: String = "") {
        let marker = TimelineMarker(kind: kind, time: position, name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        edit { $0.timeMarkers = $0.markers + [marker] }
    }

    func removeMarker(_ marker: TimelineMarker) {
        edit { $0.timeMarkers?.removeAll { $0.id == marker.id } }
    }

    func chooseStagePhoto() {
        guard canEdit, project.stagePhoto?.locked != true,
              let url = openPanel(types: [.image], title: "Choose Stage Photo") else { return }
        do { let photo = try StagePhoto.read(url); edit { $0.stagePhoto = photo } }
        catch { message = error.localizedDescription }
    }

    func setStagePhotoLock(_ locked: Bool) {
        edit { $0.stagePhoto?.locked = locked }
    }

    func setStagePhotoOpacity(_ opacity: Double) {
        guard project.stagePhoto?.locked != true else { return }
        edit { $0.stagePhoto?.opacity = opacity }
    }

    func removeStagePhoto() {
        guard project.stagePhoto?.locked != true else { return }
        edit { $0.stagePhoto = nil }
    }

    func removeCue(_ cue: LightingCue) {
        if edit({ $0.lighting.cues.removeAll { $0.id == cue.id } }) { selectedCueID = nil }
    }

    @discardableResult
    func putPosition(_ key: HeadPositionKey) -> Bool {
        edit {
            var keys = $0.lighting.positionKeys
            if let index = keys.firstIndex(where: { $0.id == key.id }) { keys[index] = key }
            else { keys.append(key) }
            $0.lighting.headPositions = keys
        }
    }

    func capturePosition(_ fixture: PatchedFixture) {
        guard case .head(let head) = effectiveState(fixture) else { return }
        putPosition(HeadPositionKey(fixtureID: fixture.id, time: position, pan: head.pan, tilt: head.tilt))
    }

    func removePosition(_ key: HeadPositionKey) {
        edit { $0.lighting.headPositions?.removeAll { $0.id == key.id } }
    }

    func createChase() {
        guard !selectedFixtures.isEmpty else { message = "Select fixtures for the chase."; return }
        var clip = ChoreographyClip()
        clip.name = "Chase \(project.chases.count + 1)"
        clip.start = position
        clip.targets = selectedFixtures.map { fixture in
            ChoreographyTarget(id: fixture.id, position: fixture.previewPlacement?.origin ?? FixturePreviewPoint(x: 0.5, y: 0.5))
        }
        putChase(clip)
    }

    @discardableResult
    func putChase(_ clip: ChoreographyClip) -> Bool {
        edit {
            if let index = $0.chases.firstIndex(where: { $0.id == clip.id }) { $0.chases[index] = clip }
            else { $0.chases.append(clip) }
        }
    }

    func removeChase(_ clip: ChoreographyClip) {
        edit { $0.chases.removeAll { $0.id == clip.id } }
    }

    func savePreset(from clip: ChoreographyClip) {
        edit {
            var presets = $0.lighting.lightingEffectPresets
            let preset = LightingEffectPreset(clip: clip)
            if let index = presets.firstIndex(where: { $0.name.caseInsensitiveCompare(preset.name) == .orderedSame }) {
                presets[index] = preset
            } else { presets.append(preset) }
            $0.lighting.effectPresets = presets
        }
    }

    func placePreset(_ preset: LightingEffectPreset) {
        guard !selectedFixtures.isEmpty else { message = "Select fixtures for the chase preset."; return }
        var clip = ChoreographyClip()
        preset.apply(to: &clip)
        clip.name = preset.name
        clip.start = position
        clip.targets = selectedFixtures.map { fixture in
            ChoreographyTarget(id: fixture.id, position: fixture.previewPlacement?.origin ?? FixturePreviewPoint(x: 0.5, y: 0.5))
        }
        putChase(clip)
    }

    func chooseSong() {
        guard canEdit, let url = openPanel(types: ShowSong.extensions.compactMap { UTType(filenameExtension: $0) }, title: "Choose Soundtrack") else { return }
        loadingSong = true
        Task { [weak self] in
            defer { self?.loadingSong = false }
            do {
                let track = try await Task.detached(priority: .userInitiated) { try PreparedSoundtrack.read(url) }.value
                try self?.importSong(track)
            } catch { self?.message = error.localizedDescription }
        }
    }

    func importSong(_ track: PreparedSoundtrack) throws {
        var candidate = project
        candidate.song = track.song
        try candidate.validate()
        let output = try makeAudio(track)
        stop()
        adoptAudio(output, track: track)
        project = candidate
        undo.removeAll()
        redo.removeAll()
        message = "Loaded \(track.song.name)."
    }

    private func makeAudio(_ track: PreparedSoundtrack) throws -> (URL, AVPlayer) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("light-studio-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let url = folder.appendingPathComponent(track.song.fileName)
        do { try track.data.write(to: url, options: .atomic) }
        catch { try? FileManager.default.removeItem(at: folder); throw error }
        let audio = AVPlayer(url: url)
        audio.isMuted = songMuted
        return (folder, audio)
    }

    private func adoptAudio(_ prepared: (URL, AVPlayer), track: PreparedSoundtrack) {
        unloadAudio()
        audioFolder = prepared.0
        player = prepared.1
        soundtrack = track.data
        waveform = track.waveform
    }

    private func unloadAudio() {
        seekID = UUID()
        seeking = false
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        if let audioFolder { try? FileManager.default.removeItem(at: audioFolder) }
        audioFolder = nil
        soundtrack = nil
        waveform = []
    }

    func switchWorkspace(_ next: StudioWorkspace) {
        guard workspace != next else { return }
        pause()
        simulation.stop()
        if next == .show { simulation.blackout = false }
        ready = false
        workspace = next
        refresh()
    }

    func armShow() {
        guard workspace == .show, !project.lighting.fixtures.isEmpty, !loadingSong,
              project.song == nil || player?.currentItem?.status != .failed else {
            message = "Add a valid fixture patch and check the soundtrack before arming."
            return
        }
        ready = true
        message = nil
    }

    func setBlackout(_ value: Bool) {
        simulation.blackout = value
        refresh()
    }

    func play() {
        guard canPlay, !playing else { return }
        if position >= project.duration { seek(to: 0) }
        clearAudition()
        playing = true
        anchorTime = ProcessInfo.processInfo.systemUptime
        anchorPosition = position
        waitingSince = nil
        simulation.resume()
        if !seeking { player?.play() }
        updateTicker()
        refresh()
    }

    func pause() {
        if playing { position = currentTime(at: ProcessInfo.processInfo.systemUptime) }
        playing = false
        player?.pause()
        finishRecording()
        refresh()
        updateTicker()
    }

    func stop() {
        pause()
        seek(to: 0, preview: false)
        simulation.stop()
        refresh()
    }

    func seek(to time: Double, preview: Bool = true) {
        guard time.isFinite else { return }
        if playing { pause() }
        position = min(project.duration, max(0, time))
        clearAudition()
        if preview { simulation.resume() }
        nextCueID = nil
        lastCueID = nil
        if let player {
            seekID = UUID()
            let token = seekID
            seeking = true
            player.seek(to: CMTime(seconds: position, preferredTimescale: 60000),
                        toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.seekID == token else { return }
                    self.seeking = false
                    if self.playing { self.player?.play() }
                }
            }
        }
        refresh()
    }

    func startRecording() {
        guard canRecord, !recording else { return }
        recording = true
        play()
        if !playing { recording = false }
    }

    private func finishRecording() {
        guard recording else { return }
        recording = false
        simulation.clearManualCues()
        reviewingTake = !take.isEmpty
        if take.isEmpty { message = "No cues were recorded." }
    }

    func reviewTake(_ visible: Bool) { reviewingTake = visible }

    func discardTake() {
        take.removeAll()
        reviewingTake = false
    }

    @discardableResult
    func addTake(_ ids: Set<UUID>, times: [UUID: Double] = [:]) -> Bool {
        let selected = take.filter { ids.contains($0.id) }.map { cue in
            var cue = cue
            cue.time = times[cue.id] ?? cue.time
            return cue
        }
        guard !selected.isEmpty, selected.count == ids.count else { return false }
        guard edit({ $0.lighting.cues.append(contentsOf: selected) }) else { return false }
        selectedCueID = selected.first?.id
        discardTake()
        return true
    }

    func go() {
        let sorted = cues
        let index = nextCueID.flatMap { id in sorted.firstIndex { $0.id == id } } ??
            (lastCueID == nil ? sorted.indices.first : nil)
        guard let index, trigger(sorted[index]) else { return }
        lastCueID = sorted[index].id
        nextCueID = sorted.indices.contains(index + 1) ? sorted[index + 1].id : nil
    }

    func triggerLook(_ look: FixtureLook) { _ = trigger(LightingCue(name: look.name, time: position, entries: look.entries)) }

    @discardableResult
    private func trigger(_ cue: LightingCue) -> Bool {
        guard workspace == .edit || ready else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        var output = cue
        if recording {
            guard let player, !seeking, player.timeControlStatus == .playing else {
                message = "Wait for the soundtrack to play before triggering."
                return false
            }
            guard take.count + project.lighting.cues.count < ProjectLighting.maximumCues else {
                pause(); message = "The lighting timeline has reached its cue limit."
                return false
            }
            let time = player.currentTime().seconds
            guard (0..<project.duration).contains(time) else { return false }
            output = LightingCue(name: cue.name, time: time, entries: cue.entries)
            if let duration = cue.clipDuration {
                let remaining = project.duration - time
                guard remaining >= CueTiming.minimumClipDuration else { return false }
                output.timelineCommand = cue.timelineCommand
                output.clipDuration = min(duration, remaining)
                output.dimmerFade = cue.dimmerFade
            }
            take.append(output)
            message = nil
        }
        for entry in output.entries {
            if let fixture = project.lighting.fixtures.first(where: { $0.id == entry.id }) { simulation.override(nil, for: fixture) }
        }
        simulation.trigger(output, at: now)
        refresh()
        updateTicker()
        return true
    }

    private func currentTime(at now: Double) -> Double {
        guard playing else { return position }
        if let player {
            let time = player.currentTime().seconds
            return !seeking && time.isFinite ? min(project.duration,max(0,time)) : position
        }
        return min(project.duration, anchorPosition + now - anchorTime)
    }

    private func refresh() {
        simulation.update(project.lighting, at: position, choreography: project.chases)
    }

    private func updateTicker() {
        let active = playing || simulation.hasManualTransitions(at: ProcessInfo.processInfo.systemUptime)
        if !active { ticker?.cancel(); ticker = nil; return }
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(25)) } catch { return }
                guard let self else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if playing {
            position = currentTime(at: now)
            if !seeking, (position >= project.duration - 0.005 || player?.currentItem?.status == .failed) {
                pause()
                simulation.stop()
                refresh()
                updateTicker()
                return
            }
            if let player, !seeking, player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                if waitingSince == nil { waitingSince = now }
                if let start = waitingSince, now - start > 5 {
                    pause()
                    simulation.stop()
                    refresh()
                    message = "The soundtrack stopped responding."
                    return
                }
            } else { waitingSince = nil }
        }
        refresh()
        updateTicker()
    }
}
