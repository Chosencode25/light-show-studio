import SwiftUI

enum StudioCommand: String, CaseIterable, Identifiable {
    case program = "Program Editor", showMode = "Show Mode", armShow = "Check & Arm Show"
    case playPause = "Play / Pause", stop = "Stop and Return to Beginning", go = "GO to Next Cue"
    case back = "Back One Second", forward = "Forward One Second", rewind = "Go to Beginning"
    case mute = "Toggle Soundtrack Mute", blackout = "Immediate Blackout", restore = "Restore Lights"
    case record = "Start / Stop Cue Recording", addBeat = "Add Beat at Playhead"
    case duplicate = "Duplicate Selected at Playhead", clearSelection = "Clear Cue Selection"
    case nudgeEarlier = "Move Selected Earlier by 0.1 Seconds", nudgeLater = "Move Selected Later by 0.1 Seconds"
    case zoomIn = "Zoom In on Timeline", zoomOut = "Zoom Out on Timeline", fit = "Fit Complete Timeline"
    case snap = "Toggle Timeline Snapping"

    var id: Self { self }
    static let show: [Self] = [.program, .showMode, .armShow, .playPause, .stop, .go, .back, .forward, .rewind, .mute, .blackout, .restore]
    static let timeline: [Self] = [.record, .addBeat, .duplicate, .clearSelection, .nudgeEarlier, .nudgeLater,
                                   .zoomIn, .zoomOut, .fit, .snap]

    var shortcut: KeyboardShortcut? {
        switch self {
        case .program: KeyboardShortcut("e", modifiers: [.control, .command])
        case .showMode: KeyboardShortcut("o", modifiers: [.control, .command])
        case .armShow: nil
        case .playPause: KeyboardShortcut(.return)
        case .stop: KeyboardShortcut(.return, modifiers: [.shift, .command])
        case .go: KeyboardShortcut("g", modifiers: [.option, .command])
        case .back: KeyboardShortcut(.leftArrow, modifiers: [.option, .shift])
        case .forward: KeyboardShortcut(.rightArrow, modifiers: [.option, .shift])
        case .rewind: KeyboardShortcut(.home, modifiers: [])
        case .mute: KeyboardShortcut("m", modifiers: [.shift, .command])
        case .blackout: KeyboardShortcut("b", modifiers: [.shift, .command])
        case .restore: KeyboardShortcut("r", modifiers: [.shift, .command])
        case .record: KeyboardShortcut("r", modifiers: [.option, .command])
        case .addBeat: KeyboardShortcut("k", modifiers: [.shift, .command])
        case .duplicate: KeyboardShortcut("d")
        case .clearSelection: KeyboardShortcut("a", modifiers: [.shift, .command])
        case .nudgeEarlier: KeyboardShortcut(.leftArrow, modifiers: [.option, .command])
        case .nudgeLater: KeyboardShortcut(.rightArrow, modifiers: [.option, .command])
        case .zoomIn: KeyboardShortcut("=")
        case .zoomOut: KeyboardShortcut("-")
        case .fit: KeyboardShortcut("0")
        case .snap: KeyboardShortcut("s", modifiers: [.option, .command])
        }
    }

    @MainActor func isEnabled(in session: ShowSession, layout: EditorLayoutSettings) -> Bool {
        guard !session.isHome else { return false }
        switch self {
        case .program: return session.workspace != .edit
        case .showMode: return session.workspace != .show
        case .armShow: return session.workspace == .show && !session.ready && !session.loadingSong
        case .playPause: return session.playing || session.canPlay
        case .stop: return true
        case .go: return !session.cues.isEmpty && (session.workspace == .edit || session.ready)
        case .back, .forward, .rewind: return !session.playing && !session.loadingSong && session.canPlay
        case .mute: return session.project.song != nil
        case .blackout: return !session.simulation.blackout
        case .restore: return session.simulation.blackout
        case .record: return session.recording || session.canRecord
        case .addBeat: return session.canEdit
        case .duplicate, .nudgeEarlier, .nudgeLater: return session.canEdit && !session.selectedCueIDs.isEmpty
        case .clearSelection: return session.workspace == .edit && !session.selectedCueIDs.isEmpty
        case .zoomIn, .zoomOut, .fit, .snap:
            guard session.workspace == .edit, layout.displayedLayout.panels.contains(.timeline) else { return false }
            if self == .zoomIn { return session.timelineZoom < 16 }
            if self == .zoomOut || self == .fit { return session.timelineZoom > 1 }
            return true
        }
    }

    @MainActor func perform(in session: ShowSession, layout: EditorLayoutSettings) {
        guard isEnabled(in: session, layout: layout) else { return }
        switch self {
        case .program: session.switchWorkspace(.edit)
        case .showMode: session.switchWorkspace(.show)
        case .armShow: session.armShow()
        case .playPause: if session.playing { session.pause() } else { session.play() }
        case .stop: session.stop()
        case .go: session.go()
        case .back: session.seek(to: session.position - 1)
        case .forward: session.seek(to: session.position + 1)
        case .rewind: session.seek(to: 0)
        case .mute: session.songMuted.toggle()
        case .blackout: session.setBlackout(true)
        case .restore: session.setBlackout(false)
        case .record: if session.recording { session.pause() } else { session.startRecording() }
        case .addBeat: session.addMarker(.beat)
        case .duplicate: session.duplicateSelectedCues(at: session.position)
        case .clearSelection: session.selectedCueID = nil
        case .nudgeEarlier: session.moveSelectedCues(by: -0.1)
        case .nudgeLater: session.moveSelectedCues(by: 0.1)
        case .zoomIn: session.timelineZoom = min(16, session.timelineZoom * 1.5)
        case .zoomOut: session.timelineZoom = max(1, session.timelineZoom / 1.5)
        case .fit: session.timelineZoom = 1
        case .snap: session.timelineSnapping.toggle()
        }
    }
}

extension EditorLayoutPreset {
    var shortcut: KeyboardShortcut {
        let key: KeyEquivalent
        switch self {
        case .overview: key = "1"
        case .stageDesign: key = "2"
        case .showTiming: key = "3"
        case .cueEditing: key = "4"
        case .fixturePatch: key = "5"
        }
        return KeyboardShortcut(key, modifiers: [.control, .command])
    }
}

extension EditorPanel {
    var shortcut: KeyboardShortcut {
        let key: KeyEquivalent
        switch self {
        case .fixtures: key = "s"
        case .stage: key = "p"
        case .inspector: key = "i"
        case .timeline: key = "t"
        }
        return KeyboardShortcut(key, modifiers: [.control, .command])
    }
}

struct StudioCommands: Commands {
    let session: ShowSession
    let layouts: EditorLayoutSettings
    let checkUpdates: () -> Void
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…", action: checkUpdates)
        }
        CommandGroup(replacing: .newItem) {
            Button("New Light Show") { session.newShow() }.keyboardShortcut("n")
            Button("Open Light Show…") { session.chooseShow() }.keyboardShortcut("o")
            Button("New Show from Setup…") { session.chooseSetup() }
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save Light Show") { session.save() }.keyboardShortcut("s").disabled(session.isHome)
            Button("Save Light Show As…") { session.save(asCopy: true) }.keyboardShortcut("s", modifiers: [.command, .shift]).disabled(session.isHome)
            Button("Save Fixture Setup…") { session.saveSetup() }.disabled(session.isHome)
        }
        CommandGroup(after: .windowArrangement) {
            Menu("Layouts") {
                ForEach(EditorLayoutPreset.allCases) { preset in
                    Button { layouts.select(preset) } label: {
                        if layouts.preset == preset { Label(preset.rawValue, systemImage: "checkmark") }
                        else { Text(preset.rawValue) }
                    }.keyboardShortcut(preset.shortcut)
                }
                Divider()
                Button("Reset Layout") { layouts.reset() }
            }.disabled(session.isHome || session.workspace != .edit)
            Menu("Panels") {
                ForEach(EditorPanel.allCases) { panel in
                    let visible = layouts.layout.panels.contains(panel)
                    Button((visible ? "Hide " : "Show ") + panel.rawValue) { layouts.toggle(panel) }
                        .keyboardShortcut(panel.shortcut)
                        .disabled(!layouts.canToggle(panel))
                }
                Divider()
                Button("Restore Panels") { layouts.restorePanels() }
                    .keyboardShortcut("m", modifiers: [.control, .command])
                    .disabled(layouts.expandedPanel == nil)
            }.disabled(session.isHome || session.workspace != .edit)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { session.undoEdit() }.keyboardShortcut("z").disabled(!session.canUndo)
            Button("Redo") { session.redoEdit() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!session.canRedo)
        }
        CommandMenu("Show") {
            ForEach(StudioCommand.show) { commandButton($0) }
        }
        CommandMenu("Timeline") {
            ForEach(StudioCommand.timeline) { commandButton($0) }
        }
        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts…") { openWindow(id: "studio-shortcuts") }
                .keyboardShortcut("/")
        }
    }

    private func commandButton(_ command: StudioCommand) -> some View {
        Button(command.rawValue) { command.perform(in: session, layout: layouts) }
            .keyboardShortcut(command.shortcut)
            .disabled(!command.isEnabled(in: session, layout: layouts))
    }
}

struct StudioShortcutGuide: View {
    private struct Entry {
        let title: String
        let keys: String

        init(_ title: String, _ shortcut: KeyboardShortcut) {
            self.title = title
            let modifiers = shortcut.modifiers
            let prefix = (modifiers.contains(.control) ? "⌃" : "") + (modifiers.contains(.option) ? "⌥" : "") +
                         (modifiers.contains(.shift) ? "⇧" : "") + (modifiers.contains(.command) ? "⌘" : "")
            let key: String
            switch shortcut.key {
            case .return: key = "↩"
            case .home: key = "Home"
            case .leftArrow: key = "←"
            case .rightArrow: key = "→"
            default: key = String(shortcut.key.character).uppercased()
            }
            keys = prefix + key
        }

        init?(_ command: StudioCommand) {
            guard let shortcut = command.shortcut else { return nil }
            self.init(command.rawValue, shortcut)
        }
    }

    @State private var query = ""

    var body: some View {
        VStack(spacing: 12) {
            TextField("Find a shortcut", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding([.top, .horizontal], 14)
            List {
                shortcuts("Show", StudioCommand.show.compactMap(Entry.init))
                shortcuts("Timeline", StudioCommand.timeline.compactMap(Entry.init))
                shortcuts("Layouts and panels",
                          EditorLayoutPreset.allCases.map { Entry($0.rawValue, $0.shortcut) } +
                          EditorPanel.allCases.map { Entry("Show / Hide " + $0.rawValue, $0.shortcut) } +
                          [Entry("Restore Panels", KeyboardShortcut("m", modifiers: [.control, .command]))])
                shortcuts("Files and editing", [
                    Entry("New Light Show", KeyboardShortcut("n")),
                    Entry("Open Light Show", KeyboardShortcut("o")),
                    Entry("Save Light Show", KeyboardShortcut("s")),
                    Entry("Save Light Show As", KeyboardShortcut("s", modifiers: [.shift, .command])),
                    Entry("Undo", KeyboardShortcut("z")),
                    Entry("Redo", KeyboardShortcut("z", modifiers: [.shift, .command])),
                    Entry("Keyboard Shortcuts", KeyboardShortcut("/"))
                ])
            }.listStyle(.inset)
        }
    }

    @ViewBuilder private func shortcuts(_ title: String, _ entries: [Entry]) -> some View {
        let matches = entries.filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.keys.localizedCaseInsensitiveContains(query)
        }
        if !matches.isEmpty {
            Section(title) {
                ForEach(matches, id: \.title) { entry in
                    HStack {
                        Text(entry.title)
                        Spacer()
                        Text(entry.keys).font(.body.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
