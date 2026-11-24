import AppKit
import SwiftUI

func studioTime(_ seconds: Double) -> String {
    guard seconds.isFinite, (0...3600).contains(seconds) else { return "0:00.00" }
    let centiseconds = Int((seconds * 100).rounded())
    return String(format: "%d:%02d.%02d", centiseconds / 6000, centiseconds / 100 % 60, centiseconds % 100)
}

struct TransportBar: View {
    let session: ShowSession

    var body: some View {
        HStack(spacing: 13) {
            Button(session.playing ? "Pause" : "Play", systemImage: session.playing ? "pause.fill" : "play.fill") {
                if session.playing { session.pause() } else { session.play() }
            }.disabled(!session.canPlay && !session.playing).buttonStyle(.borderedProminent)
            Button("Stop", systemImage: "stop.fill") { session.stop() }
            Text(studioTime(session.position)).font(.callout.monospacedDigit()).frame(width: 64)
            Slider(value: Binding(get: { session.position }, set: { session.seek(to: $0) }), in: 0...session.project.duration)
                .disabled(session.playing || session.recording || (session.workspace == .show && !session.ready))
                .accessibilityLabel("Show playhead")
            Text(studioTime(session.project.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            if session.workspace == .edit {
                Divider().frame(height: 20)
                if session.recording {
                    Button("Stop Recording", systemImage: "stop.circle.fill") { session.pause() }.tint(.red)
                } else if !session.take.isEmpty {
                    Button("Review Take") { session.reviewTake(true) }
                } else {
                    Button("Record Cues", systemImage: "record.circle") { session.startRecording() }.disabled(!session.canRecord)
                        .help("Add a soundtrack and a saved look or cue to record a take.")
                }
            }
        }.controlSize(.regular).padding(.horizontal, 14).padding(.vertical, 10).background(panelBackground)
    }
}

struct ManualCueSelector: View {
    let session: ShowSession

    var body: some View {
        HStack {
            Picker("Next Cue", selection: Binding(get: { session.nextCueID }, set: { session.nextCueID = $0 })) {
                Text("Start or Continue").tag(UUID?.none)
                ForEach(session.cues) { cue in
                    Text("\(cue.name) · \(studioTime(cue.time))").tag(Optional(cue.id))
                }
            }
            Button("GO") { session.go() }.buttonStyle(.borderedProminent)
                .disabled(session.cues.isEmpty || (session.workspace == .show && !session.ready))
        }
    }
}

struct TimelineView: View {
    private struct CueDrag {
        let anchor: Double
        let times: [UUID: Double]
        var offset = 0.0
    }

    let session: ShowSession
    @State private var lookID: UUID?
    @State private var zoom = 1.0
    @State private var snapping = true
    @State private var drag: CueDrag?
    @State private var namingSection = false
    @State private var sectionName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            toolbar
            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Time").frame(height: 29)
                    Text("Soundtrack").frame(height: 36)
                    Text("Lighting Cues").frame(height: 27)
                    Text("Chases").frame(height: 22)
                    Text("Motion Keys").frame(height: 23)
                }.font(.caption.weight(.medium)).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                GeometryReader { geometry in
                    ScrollView(.horizontal) {
                        tracks(width: max(1, geometry.size.width * zoom - 22))
                            .frame(width: geometry.size.width * zoom, height: 137)
                    }
                }.frame(height: 148)
            }
        }.padding(.horizontal, 15).padding(.vertical, 8).background(panelBackground)
            .sheet(isPresented: $namingSection) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Section Marker").font(.headline)
                    TextField("Section name", text: $sectionName)
                    HStack {
                        Spacer()
                        Button("Cancel") { namingSection = false }.keyboardShortcut(.cancelAction)
                        Button("Add Marker") {
                            session.addMarker(.section, name: sectionName)
                            if session.message == nil { namingSection = false }
                        }.disabled(sectionName.count > 80).keyboardShortcut(.defaultAction)
                    }
                }.padding(20).frame(width: 345)
            }
            .onChange(of: session.project.id) { _, _ in drag = nil; zoom = 1 }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("Timeline").font(.headline)
            if let song = session.project.song {
                Label(song.name, systemImage: "music.note").lineLimit(1).foregroundStyle(.secondary)
            }
            Spacer()
            if session.recording {
                Label("\(session.take.count) recorded", systemImage: "record.circle.fill").foregroundStyle(.red)
                ManualCueSelector(session: session).frame(maxWidth: 260)
                Picker("Look", selection: $lookID) {
                    Text("Choose a Look").tag(UUID?.none)
                    ForEach(session.project.lighting.looks) { Text($0.name).tag(Optional($0.id)) }
                }.frame(maxWidth: 180)
                Button("Trigger Look") {
                    if let look = session.project.lighting.looks.first(where: { $0.id == lookID }) { session.triggerLook(look) }
                }.disabled(!session.project.lighting.looks.contains { $0.id == lookID })
            } else {
                if !session.cues.isEmpty {
                    Menu(session.selectedCueIDs.count > 1 ? "\(session.selectedCueIDs.count) Cues Selected" : "Cues") {
                        Button("Duplicate at Playhead") { session.duplicateSelectedCues(at: session.position) }
                            .disabled(!session.canEdit || session.selectedCueIDs.isEmpty)
                        Button("Delete Selected", role: .destructive) { session.removeSelectedCues() }
                            .disabled(!session.canEdit || session.selectedCueIDs.isEmpty)
                        Button("Clear Cue Selection") { session.selectedCueID = nil }.disabled(session.selectedCueIDs.isEmpty)
                        Divider()
                        ForEach(session.cues) { cue in
                            Button("\(cue.name) · \(cue.isManual ? "Manual" : studioTime(cue.time))") {
                                session.selectCue(cue.id, extending: !NSEvent.modifierFlags.intersection([.shift, .command]).isEmpty)
                            }
                        }
                    }.fixedSize().help("Shift-click or Command-click timeline cues to select several.")
                }
                Menu("Markers") {
                    Button("Add Beat at Playhead") { session.addMarker(.beat) }.disabled(!session.canEdit)
                    Button("Add Section at Playhead…") { sectionName = ""; namingSection = true }.disabled(!session.canEdit)
                    if !session.project.markers.isEmpty {
                        Menu("Remove Marker") {
                            ForEach(session.project.markers.sorted { $0.time < $1.time }) { marker in
                                Button("\(marker.label) · \(studioTime(marker.time))") { session.removeMarker(marker) }
                            }
                        }.disabled(!session.canEdit)
                    }
                }.fixedSize()
                Toggle("Snap", isOn: $snapping).toggleStyle(.checkbox).help("Snap cue drags to nearby beat and section markers.")
                Slider(value: $zoom, in: 1...16).frame(width: 82).accessibilityLabel("Timeline zoom").help("Timeline zoom")
            }
        }
    }

    private func tracks(width: Double) -> some View {
        let duration = session.project.duration
        let scale = width / duration
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.25))
            grid(width: width, duration: duration)
            Color.clear.contentShape(Rectangle()).gesture(SpatialTapGesture().onEnded { event in
                guard !session.playing else { return }
                session.seek(to: max(0, Double(event.location.x - 11)/scale))
            })
            ForEach(session.project.markers) { marker in
                Button { if !session.playing { session.seek(to: marker.time) } } label: {
                    Image(systemName: marker.kind == .beat ? "circle.fill" : "flag.fill")
                        .font(.system(size: 8)).foregroundStyle(marker.kind == .beat ? .pink : studioAccent)
                }.buttonStyle(.plain).offset(x: 8 + marker.time * scale, y: 18)
                    .help("\(marker.label) · \(studioTime(marker.time))").accessibilityLabel(marker.label)
            }
            ForEach(session.project.chases) { clip in
                Capsule().fill(studioAccent.opacity(0.55))
                    .frame(width: max(3,(clip.end - clip.start) * scale), height: 8)
                    .offset(x: 11 + clip.start * scale, y: 99).help(clip.name)
            }
            ForEach(session.project.lighting.positionKeys) { key in
                Circle().fill(Color.purple).frame(width: 5, height: 5)
                    .offset(x: 9 + key.time * scale, y: 123).help(studioTime(key.time))
            }
            ForEach(session.cues.filter { !$0.isManual }) { cue in
                cueMarker(cue, scale: scale)
            }
            Rectangle().fill(studioAccent.opacity(0.9)).frame(width: 1.5, height: 137)
                .offset(x: 11 + session.position * scale).allowsHitTesting(false)
        }.coordinateSpace(name: "studio-timeline")
    }

    private func cueMarker(_ cue: LightingCue, scale: Double) -> some View {
        let selected = session.selectedCueIDs.contains(cue.id)
        let time = (drag?.times[cue.id]).map { $0 + (drag?.offset ?? 0) } ?? cue.time
        return Button {
            session.selectCue(cue.id, extending: !NSEvent.modifierFlags.intersection([.shift, .command]).isEmpty)
        } label: {
            Image(systemName: selected ? "diamond.fill" : "diamond")
                .font(.system(size: 12)).foregroundStyle(selected ? studioAccent : .orange)
                .frame(width: 20, height: 23)
        }.buttonStyle(.plain).offset(x: 1 + time * scale, y: 68)
            .help("\(cue.name) · \(studioTime(time))").accessibilityLabel(cue.name)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .highPriorityGesture(DragGesture(minimumDistance: 5, coordinateSpace: .named("studio-timeline"))
                .onChanged { event in
                    guard session.canEdit else { return }
                    if drag == nil {
                        if !session.selectedCueIDs.contains(cue.id) { session.selectCue(cue.id) }
                        let entries = session.cues.filter { session.selectedCueIDs.contains($0.id) }
                        drag = CueDrag(anchor: cue.time, times: Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.time) }))
                    }
                    guard let pending = drag else { return }
                    let target = pending.anchor + event.translation.width / scale
                    let time = snapping ? CueTiming.nearestMarker(to: target, in: session.project.markers, tolerance: 9 / scale) : target
                    drag?.offset = CueTiming.boundedOffset(time - pending.anchor, times: Array(pending.times.values),
                                                            end: session.project.song?.duration ?? 3600)
                }
                .onEnded { _ in
                    defer { drag = nil }
                    guard let drag, session.canEdit, Set(drag.times.keys) == session.selectedCueIDs,
                          session.cues.allSatisfy({ drag.times[$0.id] == nil || drag.times[$0.id] == $0.time }) else { return }
                    session.moveSelectedCues(by: drag.offset)
                })
    }

    private func grid(width: Double, duration: Double) -> some View {
        let peaks = session.waveform
        let markers = session.project.markers
        return Canvas { context, size in
            let scale = width / duration
            let options = [0.1, 0.25, 0.5, 1, 2, 5, 10, 20, 30, 60, 120, 300, 600]
            let step = options.first { $0 * scale >= 69 } ?? 600
            for time in stride(from: 0.0, through: duration, by: step) {
                let x = 11 + time * scale
                var line = Path()
                line.move(to: CGPoint(x: x, y: 17))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(.white.opacity(0.11)))
                context.draw(Text(studioTime(time)).font(.system(size: 9)).foregroundStyle(.secondary),
                             at: CGPoint(x: x + 3, y: 4), anchor: .topLeading)
            }
            for y in [28.0, 64.0, 91.0, 113.0] {
                let divider = Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) }
                context.stroke(divider, with: .color(.white.opacity(0.10)))
            }
            if peaks.count > 1 {
                var shape = Path()
                let middle = 46.0
                var first = true
                for index in peaks.indices {
                    let point = CGPoint(x: 11 + Double(index) * width / Double(peaks.count - 1), y: middle - max(0.5, Double(peaks[index]) * 15))
                    if first { shape.move(to: point); first = false } else { shape.addLine(to: point) }
                }
                for index in peaks.indices.reversed() {
                    shape.addLine(to: CGPoint(x: 11 + Double(index) * width / Double(peaks.count - 1), y: middle + max(0.5,Double(peaks[index]) * 15)))
                }
                shape.closeSubpath()
                context.fill(shape, with: .color(studioAccent.opacity(0.76)))
            }
            for marker in markers {
                let x = 11 + marker.time * scale
                let line = Path { p in p.move(to: CGPoint(x: x, y: 26)); p.addLine(to: CGPoint(x: x, y: size.height)) }
                context.stroke(line, with: .color((marker.kind == .beat ? Color.pink : studioAccent).opacity(0.35)),
                               style: StrokeStyle(lineWidth: 1, dash: [3,4]))
            }
        }.accessibilityHidden(true)
    }
}

struct OperatorPanel: View {
    let session: ShowSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Show Controls").font(.title2.bold())
                Label(session.ready ? "Armed for Simulation" : "Simulation Disarmed",
                      systemImage: session.ready ? "checkmark.circle.fill" : "circle.dotted")
                    .foregroundStyle(session.ready ? studioAccent : .secondary)
                if !session.ready {
                    Button("Check & Arm") { session.armShow() }.buttonStyle(.borderedProminent)
                }
                Toggle("Blackout", isOn: Binding(get: { session.simulation.blackout }, set: { session.setBlackout($0) }))
                    .toggleStyle(.switch).tint(.orange)
                ManualCueSelector(session: session)
                Divider()
                if let song = session.project.song {
                    Label(song.name, systemImage: "music.note").lineLimit(1).foregroundStyle(.secondary)
                }
                Text("Fixture Status").font(.headline)
                ForEach(session.project.lighting.fixtures) { fixture in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(fixture.name, systemImage: fixture.symbol)
                        Text(session.effectiveState(fixture).label).font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9).background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
                }
            }.padding(16)
        }.background(panelBackground)
    }
}
