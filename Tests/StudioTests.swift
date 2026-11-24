import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Testing

@MainActor
struct StudioTests {
    @Test func setupCarriesPatchAndPositionsIntoIndependentShows() throws {
        let session = makeSession()
        defer { session.finish() }
        session.newShow()
        session.addFixture(.movingHead)
        session.addFixture(.rgb)
        session.addFixture(.plug)
        let fixture = try #require(session.project.lighting.fixtures.last)
        session.updateFixture(fixture.id) { $0.group = "Garden" }
        let position = FixturePreviewPoint(x: 0.86, y: 0.75)
        session.move(fixture, to: position)
        session.audition(fixture, state: .plug(true))
        session.captureLook("Garden On")
        session.place(try #require(session.project.lighting.looks.first))
        let setup = FixtureSetup(show: session.project, name: "Saved Layout")
        let first = try setup.newShow()
        let second = try setup.newShow()
        #expect(first.id != second.id)
        #expect(first.lighting.fixtures == session.project.lighting.fixtures)
        #expect(first.lighting.fixtures.last?.group == "Garden")
        #expect(first.lighting.fixtures.last?.previewPlacement?.origin == position)
        #expect(first.lighting.cues.isEmpty && first.lighting.looks.isEmpty && first.song == nil)
        #expect(Set(first.lighting.fixtures.filter { $0.controllerID == fixture.controllerID }.flatMap(\.slots)).count == 4)
    }

    @Test func switchedPlugIconsPersistWithoutChangingOutputs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = makeSession()
        defer { session.finish() }
        session.newShow()
        session.addFixture(.plug)
        session.addFixture(.rgb)
        let original = try #require(session.project.lighting.fixtures.first)
        let legacyData = try JSONEncoder().encode(original)
        #expect(!String(decoding: legacyData, as: UTF8.self).contains("switchedPlugIcon"))
        let legacy = try JSONDecoder().decode(PatchedFixture.self, from: legacyData)
        #expect(legacy.symbol == SwitchedPlugIcon.plug.symbol)
        for icon in SwitchedPlugIcon.allCases {
            #expect(NSImage(systemSymbolName: icon.symbol, accessibilityDescription: nil) != nil)
        }

        let entry = FixtureLookEntry(id: original.id, state: .plug(true))
        session.setCue(LightingCue(name: "Tree On", time: 1, entries: [entry]))
        session.updateFixture(original.id) { $0.switchedPlugIcon = .tree }
        let showURL = directory.appendingPathComponent("Decorations.lightshow")
        try session.write(showURL)
        let (show, _) = try ShowFiles.load(showURL)
        let decorated = try #require(show.lighting.fixtures.first)
        #expect(decorated.symbol == SwitchedPlugIcon.tree.symbol)
        #expect(decorated.kind == .plug && decorated.slots == original.slots)
        #expect(show.lighting.cues.first?.entries == [entry])
        #expect(show.lighting.fixtures.last?.symbol == FixtureKind.rgb.symbol)
        session.seek(to: 1.1)
        #expect(session.effectiveState(decorated) == .plug(true))
        session.undoEdit()
        #expect(session.project.lighting.fixtures.first == original)

        let setupURL = directory.appendingPathComponent("Decorations.lightsetup")
        try ShowFiles.saveSetup(FixtureSetup(show: show, name: "Decorations"), to: setupURL)
        let newShow = try ShowFiles.loadSetup(setupURL).newShow()
        #expect(newShow.lighting.fixtures.first == decorated)
    }

    @Test func switchedStripPointsCanBeEditedAndSavedWithoutChangingThePatch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = makeSession()
        defer { session.finish() }
        session.newShow()
        session.addFixture(.plug)
        session.addFixture(.rgb)
        let fixture = try #require(session.project.lighting.fixtures.first)
        let rgb = try #require(session.project.lighting.fixtures.last)
        session.updateFixture(fixture.id) { $0.switchedPlugIcon = .strip }
        let straight = try #require(session.project.lighting.fixtures.first?.previewPlacement)
        #expect(straight.stripPoints.count == 2 && straight.stripPoints.first != straight.stripPoints.last)
        let points: [FixturePreviewPoint] = [
            .init(x: 0.1, y: 0.7), .init(x: 0.35, y: 0.25),
            .init(x: 0.6, y: 0.25), .init(x: 0.85, y: 0.7)
        ]
        session.setStripPath(points, for: fixture.id)
        session.setStripPath(points, for: rgb.id)
        let routed = try #require(session.project.lighting.fixtures.first)
        #expect(routed.previewPlacement?.stripPoints == points && routed.slots == fixture.slots)
        #expect(session.project.lighting.fixtures.last == rgb)

        var revised = points
        revised.remove(at: 1)
        revised[2].y = 0.4
        session.setStripPath(revised, for: fixture.id)
        #expect(session.project.lighting.fixtures.first?.previewPlacement?.stripPoints == revised)
        session.setStripPath([points[0], .init(x: 1.5, y: 0.5), points[3]], for: fixture.id)
        #expect(session.project.lighting.fixtures.first?.previewPlacement?.stripPoints == revised)
        session.undoEdit()
        #expect(session.project.lighting.fixtures.first == routed)

        let showURL = directory.appendingPathComponent("Roofline.lightshow")
        try session.write(showURL)
        let (show, _) = try ShowFiles.load(showURL)
        #expect(show.lighting.fixtures.first?.previewPlacement?.stripPoints == points)
        let setupURL = directory.appendingPathComponent("Roofline.lightsetup")
        try ShowFiles.saveSetup(FixtureSetup(show: show, name: "Roofline"), to: setupURL)
        let newShow = try ShowFiles.loadSetup(setupURL).newShow()
        #expect(newShow.lighting.fixtures.first == routed)
    }

    @Test func fixtureTimelineCommandsUseExistingPlaybackAndRejectIncompatibleDrops() throws {
        let session = makeSession()
        defer { session.finish() }
        session.newShow()
        session.addFixture(.plug)
        session.addFixture(.rgb)
        session.addFixture(.movingHead)
        let fixtures = session.project.lighting.fixtures
        let plug = fixtures[0]
        let strip = fixtures[1]
        let head = fixtures[2]

        let incompatible = session.placeTimelineCommand(.red, fixtureID: plug.id, at: 1)
        #expect(!incompatible && session.cues.isEmpty)
        #expect(session.placeTimelineCommand(.on, fixtureID: plug.id, at: 1))
        #expect(session.placeTimelineCommand(.off, fixtureID: plug.id, at: 3))
        #expect(session.placeTimelineCommand(.cyan, fixtureID: strip.id, at: 1))
        #expect(session.placeTimelineCommand(.dimmer, fixtureID: head.id, at: 1))
        #expect(session.placeTimelineCommand(.fade, fixtureID: head.id, at: 3))
        #expect(session.placeTimelineCommand(.movement, fixtureID: head.id, at: 4))
        #expect(session.placeTimelineCommand(.chase, fixtureID: plug.id, at: 5))
        #expect(!session.placeTimelineCommand(.off, fixtureID: plug.id, at: 1))
        session.seek(to: 1)
        #expect(session.effectiveState(plug) == .plug(true))
        #expect(session.effectiveState(strip) == .rgb(.cyan))
        session.seek(to: 2.5)
        guard case .head(let fading) = session.effectiveState(head) else { Issue.record("Missing head state."); return }
        #expect(fading.dimmer == 0.25)
        session.seek(to: 3)
        #expect(session.effectiveState(plug) == .plug(false))
        session.seek(to: 4)
        guard case .head(let moved) = session.effectiveState(head) else { Issue.record("Missing head position."); return }
        #expect(moved.pan != fading.pan && moved.dimmer == 0)
        session.seek(to: 5.1)
        #expect(session.effectiveState(plug) == .plug(true))
        session.seek(to: 5.3)
        #expect(session.effectiveState(plug) == .plug(false))

        let encoded = try JSONEncoder().encode(session.project)
        let reopened = try JSONDecoder().decode(LightShow.self, from: encoded)
        try reopened.validate()
        #expect(reopened == session.project)
        #expect(reopened.lighting.cues.contains { $0.timelineCommand == .cyan })
        #expect(FixtureTimelineCommand(dragValue: FixtureTimelineCommand.cyan.dragValue) == .cyan)
        #expect(FixtureTimelineCommand(dragValue: "Cyan") == nil)
    }

    @Test func fixtureTimelineSplitsSingleTileWithoutMovingTheOtherCommands() throws {
        let session = makeSession()
        defer { session.finish() }
        session.newShow()
        session.addFixture(.plug)
        session.addFixture(.rgb)
        let fixtures = session.project.lighting.fixtures
        let plug = FixtureLookEntry(id: fixtures[0].id, state: .plug(true))
        let strip = FixtureLookEntry(id: fixtures[1].id, state: .rgb(.red))
        let group = LightingCue(name: "Chorus", time: 2, entries: [plug, strip])
        let blocked = LightingCue(name: "Off", time: 4, entries: [.init(id: plug.id, state: .plug(false))])
        session.setCue(group)
        session.setCue(blocked)
        let original = session.project
        session.moveFixtureCommand(cueID: group.id, fixtureID: plug.id, to: 4)
        #expect(session.project == original)
        session.moveFixtureCommand(cueID: group.id, fixtureID: plug.id, to: 3)
        #expect(session.cues.first?.entries == [strip] && session.cues.first?.id == group.id)
        let moved = try #require(session.cues.first { $0.time == 3 })
        #expect(moved.entries == [plug] && moved.id != group.id)
        session.undoEdit()
        #expect(session.project == original)
        session.selectCue(group.id)
        session.moveSelectedCues(by: 1)
        #expect(session.cues.first?.time == 3 && session.cues.first?.entries == [plug, strip])
        session.removeFixtureCommand(cueID: group.id, fixtureID: strip.id)
        #expect(session.cues.first?.entries == [plug])
    }

    @Test func patchConflictsAndDuplicateFixtureCueTimesDoNotPartiallyCommit() throws {
        let session = makeSession()
        defer { session.finish() }
        session.newShow()
        session.addFixture(.plug)
        session.addFixture(.plug)
        let fixtures = session.project.lighting.fixtures
        let original = session.project
        session.updateFixture(fixtures[1].id) { $0.address = fixtures[0].address }
        #expect(session.project == original)
        let entry = FixtureLookEntry(id: fixtures[0].id, state: .plug(true))
        session.setCue(LightingCue(name: "First", time: 1, entries: [entry]))
        session.setCue(LightingCue(name: "Duplicate", time: 1, entries: [entry]))
        #expect(session.project.lighting.cues.count == 1)
        session.undoEdit()
        #expect(session.project == original)
    }

    @Test func recordsAgainstTheAudioClockAndRunsReopenedShow() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let track = directory.appendingPathComponent("Click.wav")
        try writeSilentWAV(to: track)
        let session = makeSession()
        defer { session.finish() }
        session.newShow()
        session.addFixture(.plug)
        let plug = try #require(session.project.lighting.fixtures.first)
        session.audition(plug, state: .plug(true))
        session.captureLook("On")
        session.audition(plug, state: .plug(false))
        session.captureLook("Off")
        let on = try #require(session.project.lighting.looks.first)
        let off = try #require(session.project.lighting.looks.last)
        try session.importSong(PreparedSoundtrack.read(track))
        session.songMuted = true
        session.startRecording()
        try waitForRecording(session)
        try await until { session.position >= 0.2 }
        session.triggerLook(on)
        let first = try #require(session.take.first)
        #expect(session.effectiveState(plug) == .plug(true))
        try await until { session.position >= first.time + 0.15 }
        session.triggerLook(off)
        session.pause()
        try #require(session.take.count == 2)
        let recorded = session.take
        #expect(recorded[0].time >= 0.2 && recorded[1].time > recorded[0].time)
        try #require(session.addTake(Set(recorded.map(\.id))))
        #expect(!session.recording && session.take.isEmpty)

        let file = directory.appendingPathComponent("Ready.lightshow")
        try session.write(file)
        try FileManager.default.removeItem(at: track)
        session.finish()
        let reopened = makeSession()
        defer { reopened.finish() }
        try reopened.load(file)
        #expect(reopened.project.lighting.cues == recorded)
        #expect(reopened.project.song?.name == "Click")
        reopened.songMuted = true
        reopened.switchWorkspace(.show)
        reopened.play()
        #expect(!reopened.playing)
        reopened.armShow()
        reopened.play()
        try await until { reopened.effectiveState(plug) == .plug(true) }
        try await until { reopened.position >= recorded[1].time && reopened.effectiveState(plug) == .plug(false) }
        reopened.setBlackout(true)
        #expect(reopened.effectiveState(plug) == .plug(false))
        reopened.stop()
        #expect(reopened.position == 0 && !reopened.playing && reopened.simulation.isStopped)
    }

    @Test func movementKeysAndChasePresetReachTheSimulation() throws {
        let session = makeSession()
        defer { session.finish() }
        session.newShow()
        session.addFixture(.movingHead)
        let fixture = try #require(session.project.lighting.fixtures.first)
        session.putPosition(HeadPositionKey(fixtureID: fixture.id, time: 1, pan: 0.2, tilt: 0.25))
        session.putPosition(HeadPositionKey(fixtureID: fixture.id, time: 3, pan: 0.8, tilt: 0.75))
        session.seek(to: 2)
        guard case .head(let head) = session.effectiveState(fixture) else { Issue.record("Expected a simulated head."); return }
        #expect(abs(head.pan - 0.5) < 0.00001 && abs(head.tilt - 0.5) < 0.00001)
        session.createChase()
        let chase = try #require(session.project.chases.first)
        #expect(chase.targets.map(\.id) == [fixture.id])
        session.savePreset(from: chase)
        let preset = try #require(session.project.lighting.lightingEffectPresets.first)
        session.seek(to: 4)
        session.placePreset(preset)
        #expect(session.project.chases.count == 2)
        #expect(session.effectiveState(fixture) != .head(head))
    }

    @Test func movesAndDuplicatesCueGroupsAsSingleEdits() throws {
        let session = makeSession()
        defer { session.finish() }
        session.newShow()
        session.addFixture(.plug)
        let fixture = try #require(session.project.lighting.fixtures.first)
        let state = FixtureLookEntry(id: fixture.id, state: .plug(true))
        let first = LightingCue(name: "First", time: 1, entries: [state])
        let second = LightingCue(name: "Second", time: 2, entries: [state])
        let occupied = LightingCue(name: "Occupied", time: 5, entries: [state])
        for item in [first, second, occupied] { session.setCue(item) }
        session.selectCue(first.id)
        session.selectCue(second.id, extending: true)
        session.moveSelectedCues(by: 3)
        #expect(session.project.lighting.cues.map(\.time) == [1, 2, 5])
        session.moveSelectedCues(by: 1)
        #expect(session.project.lighting.cues.map(\.time) == [2, 3, 5])
        session.duplicateSelectedCues(at: 8)
        #expect(session.project.lighting.cues.map(\.time) == [2, 3, 5, 8, 9])
        #expect(session.selectedCueIDs.count == 2 && !session.selectedCueIDs.contains(first.id))
        session.undoEdit()
        #expect(session.project.lighting.cues.map(\.time) == [2, 3, 5])
        session.undoEdit()
        #expect(session.project.lighting.cues == [first, second, occupied])
        let marker = TimelineMarker(kind: .beat, time: 4)
        #expect(CueTiming.nearestMarker(to: 4.08, in: [marker], tolerance: 0.1) == 4)
        #expect(CueTiming.nearestMarker(to: 4.18, in: [marker], tolerance: 0.1) == 4.18)
    }

    @Test func cuePreviewIsTemporaryAndAppliedFixtureEditsPersist() throws {
        let session = makeSession()
        defer { session.finish() }
        session.newShow()
        session.addFixture(.plug)
        session.addFixture(.rgb)
        let fixtures = session.project.lighting.fixtures
        let original = LightingCue(name: "Original", time: 1, entries: [.init(id: fixtures[0].id, state: .plug(true))])
        session.setCue(original)
        var draft = original
        draft.entries = [.init(id: fixtures[0].id, state: .plug(false)), .init(id: fixtures[1].id, state: .rgb(.cyan))]
        session.previewCue(draft)
        #expect(session.project.lighting.cues == [original])
        #expect(session.effectiveState(fixtures[1]) == .rgb(.cyan))
        session.clearAudition()
        #expect(session.effectiveState(fixtures[1]) == .rgb(.off))
        session.setCue(draft)
        #expect(session.project.lighting.cues == [draft])
        session.seek(to: 1.1)
        #expect(session.effectiveState(fixtures[1]) == .rgb(.cyan))
    }

    @Test func embeddedStagePhotoAndWaveformSurviveReopeningAndSetupReuse() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let photoFile = directory.appendingPathComponent("Stage.png")
        let soundFile = directory.appendingPathComponent("Pulse.wav")
        let context = try #require(CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8,
            bytesPerRow: 160, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        let image = try #require(context.makeImage())
        let output = try #require(CGImageDestinationCreateWithURL(photoFile as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(output, image, nil)
        try #require(CGImageDestinationFinalize(output))
        var photo = try StagePhoto.read(photoFile)
        photo.locked = true
        photo.opacity = 0.4
        try writeSilentWAV(to: soundFile, pulse: true)
        let sound = try PreparedSoundtrack.read(soundFile)
        #expect(sound.waveform.max() ?? 0 >= 0.4)
        #expect(sound.waveform.contains(0))
        var show = LightShow()
        show.stagePhoto = photo
        show.song = sound.song
        show.timeMarkers = [TimelineMarker(kind: .section, time: 1, name: "Verse")]
        let url = directory.appendingPathComponent("Design.lightshow")
        try ShowFiles.save(show, soundtrack: sound.data, to: url, replacing: false)
        try FileManager.default.removeItem(at: photoFile)
        try FileManager.default.removeItem(at: soundFile)
        let (reopened, soundtrack) = try ShowFiles.load(url)
        #expect(reopened == show && soundtrack?.waveform == sound.waveform)
        let setup = FixtureSetup(show: reopened, name: "Stage")
        let fresh = try setup.newShow()
        #expect(fresh.stagePhoto == photo && fresh.song == nil && fresh.markers.isEmpty)
    }

    private func makeSession() -> ShowSession {
        ShowSession(defaults: UserDefaults(suiteName: "LightShowStudioTests." + UUID().uuidString)!)
    }

    private func waitForRecording(_ session: ShowSession) throws { try #require(session.recording && session.playing) }

    private func until(_ condition: () -> Bool) async throws {
        let limit = ProcessInfo.processInfo.systemUptime + 4
        while !condition() {
            guard ProcessInfo.processInfo.systemUptime < limit else { throw ShowError.invalid("Timed out waiting for the soundtrack or simulated fixture.") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func writeSilentWAV(to url: URL, pulse: Bool = false) throws {
        let rate: UInt32 = 8000
        let sampleBytes = rate * 3 * 2
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8)
        append(UInt32(36) + sampleBytes)
        data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(rate); append(rate * 2); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: "data".utf8)
        append(sampleBytes)
        if pulse {
            for index in 0..<(sampleBytes / 2) { append(Int16(index < 300 ? 16384 : 0)) }
        } else { data.append(Data(repeating: 0, count: Int(sampleBytes))) }
        try data.write(to: url)
    }
}
