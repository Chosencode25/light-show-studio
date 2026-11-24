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
        let cues: [LightingCue]
        var offset = 0.0
    }

    let session: ShowSession
    @State private var lookID: UUID?
    @State private var zoom = 1.0
    @State private var snapping = true
    @State private var drag: CueDrag?
    @State private var namingSection = false
    @State private var sectionName = ""
    @State private var draggedCommand: FixtureTimelineCommand?
    @State private var editingPosition: HeadPositionKey?
    @State private var editingChase: ChoreographyClip?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            scrollWhenNarrow { toolbar }
            scrollWhenNarrow { palette }
            fixtureTimeline
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
            .sheet(item: $editingPosition) { PositionForm(session: session, draft: $0) }
            .sheet(item: $editingChase) { ChaseForm(session: session, draft: $0) }
            .onChange(of: session.project.id) { _, _ in drag = nil; zoom = 1 }
    }

    private func scrollWhenNarrow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ViewThatFits(in: .horizontal) {
            content()
            ScrollView(.horizontal) { content().fixedSize(horizontal: true, vertical: false) }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
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

    private var palette: some View {
        HStack(spacing: 6) {
            ForEach(FixtureTimelineCommand.allCases) { command in
                let appearance = TimelineTileAppearance(command)
                TimelineTile(appearance: appearance, selected: false)
                    .help(command == .fade ? "Fade Out · Starts fading at the drop time" : command.rawValue)
                    .accessibilityLabel(command.rawValue)
                    .onDrag {
                        draggedCommand = command
                        return NSItemProvider(object: command.dragValue as NSString)
                    }
                if command == .off || command == .white { Divider().frame(height: 16).padding(.horizontal, 3) }
            }
            Spacer()
        }.disabled(!session.canEdit)
    }

    private var fixtureTimeline: some View {
        let fixtures = session.project.lighting.fixtures
        let duration = session.project.duration
        let commands = TimelineFixtureEvent.rows(cues: session.cues, keys: session.project.lighting.positionKeys, chases: session.project.chases)
        let headingHeight = 90.0
        let rowHeight = TimelineFixtureLane.height
        let labelWidth = 145.0
        let height = headingHeight + rowHeight * Double(fixtures.count)
        return GeometryReader { geometry in
            let viewport = max(1, geometry.size.width - labelWidth)
            let totalWidth = viewport * zoom
            let scale = max(1, totalWidth - 28) / duration
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Time").frame(height: 29)
                        Text("Soundtrack").frame(height: 35)
                        Text("Cue Groups").frame(height: 26)
                        ForEach(fixtures) { fixture in
                            Button {
                                session.selection = .fixture(fixture.id)
                            } label: {
                                Label(fixture.name, systemImage: fixture.symbol)
                                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 6).frame(height: rowHeight)
                            }.buttonStyle(.plain)
                                .background(session.selection == .fixture(fixture.id) ? studioAccent.opacity(0.13) : .white.opacity(0.028))
                                .overlay(alignment: .bottom) { Divider() }
                                .help(fixture.name)
                        }
                    }.font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: labelWidth, alignment: .leading)
                    ScrollView(.horizontal) {
                        ZStack(alignment: .topLeading) {
                            grid(width: scale * duration, duration: duration)
                            VStack(spacing: 0) {
                                tracks(scale: scale)
                                    .frame(height: headingHeight)
                                ForEach(fixtures) { fixture in
                                    TimelineFixtureLane(session: session, fixture: fixture,
                                        events: commands[fixture.id] ?? [], scale: scale, duration: duration,
                                        snapping: snapping, draggedCommand: draggedCommand,
                                        editPosition: { editingPosition = $0 }, editChase: { editingChase = $0 })
                                }
                            }
                            TimelinePlayhead(session: session, scale: scale, height: height)
                        }
                        .frame(width: totalWidth, height: height)
                        .background(.black.opacity(0.25))
                        .coordinateSpace(name: "studio-timeline")
                    }.frame(height: height)
                }
            }
        }
    }

    private func tracks(scale: Double) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle()).gesture(SpatialTapGesture().onEnded { event in
                guard !session.playing else { return }
                session.seek(to: max(0, Double(event.location.x - 14) / scale))
            })
            ForEach(session.project.markers) { marker in
                Button { if !session.playing { session.seek(to: marker.time) } } label: {
                    Image(systemName: marker.kind == .beat ? "circle.fill" : "flag.fill")
                        .font(.system(size: 8)).foregroundStyle(marker.kind == .beat ? .pink : studioAccent)
                }.buttonStyle(.plain).offset(x: 11 + marker.time * scale, y: 18)
                    .help("\(marker.label) · \(studioTime(marker.time))").accessibilityLabel(marker.label)
            }
            ForEach(session.cues.filter { !$0.isManual }) { cue in
                cueMarker(cue, scale: scale)
            }
        }
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
        }.buttonStyle(.plain).offset(x: 4 + time * scale, y: 65)
            .help("\(cue.name) · \(studioTime(time))").accessibilityLabel(cue.name)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .highPriorityGesture(DragGesture(minimumDistance: 5, coordinateSpace: .named("studio-timeline"))
                .onChanged { event in
                    guard session.canEdit else { return }
                    if drag == nil {
                        if !session.selectedCueIDs.contains(cue.id) { session.selectCue(cue.id) }
                        let entries = session.cues.filter { session.selectedCueIDs.contains($0.id) }
                        drag = CueDrag(anchor: cue.time, times: Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.time) }), cues: entries)
                    }
                    guard let pending = drag else { return }
                    let target = pending.anchor + event.translation.width / scale
                    let time = snapping ? CueTiming.nearestMarker(to: target, in: session.project.markers, tolerance: 9 / scale) : target
                    drag?.offset = CueTiming.boundedOffset(time - pending.anchor, cues: pending.cues,
                                                            end: session.project.song?.duration ?? 3600)
                }
                .onEnded { _ in
                    defer { drag = nil }
                    guard let drag, session.canEdit, Set(drag.times.keys) == session.selectedCueIDs,
                          session.cues.filter({ drag.times[$0.id] != nil }) == drag.cues else { return }
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
                let x = 14 + time * scale
                var line = Path()
                line.move(to: CGPoint(x: x, y: 17))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(.white.opacity(0.11)))
                context.draw(Text(studioTime(time)).font(.system(size: 9)).foregroundStyle(.secondary),
                             at: CGPoint(x: x + 3, y: 4), anchor: .topLeading)
            }
            for y in [29.0, 64.0, 90.0] {
                let divider = Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) }
                context.stroke(divider, with: .color(.white.opacity(0.10)))
            }
            if peaks.count > 1 {
                var shape = Path()
                let middle = 46.0
                var first = true
                for index in peaks.indices {
                    let point = CGPoint(x: 14 + Double(index) * width / Double(peaks.count - 1), y: middle - max(0.5, Double(peaks[index]) * 15))
                    if first { shape.move(to: point); first = false } else { shape.addLine(to: point) }
                }
                for index in peaks.indices.reversed() {
                    shape.addLine(to: CGPoint(x: 14 + Double(index) * width / Double(peaks.count - 1), y: middle + max(0.5,Double(peaks[index]) * 15)))
                }
                shape.closeSubpath()
                context.fill(shape, with: .color(studioAccent.opacity(0.76)))
            }
            for marker in markers {
                let x = 14 + marker.time * scale
                let line = Path { p in p.move(to: CGPoint(x: x, y: 26)); p.addLine(to: CGPoint(x: x, y: size.height)) }
                context.stroke(line, with: .color((marker.kind == .beat ? Color.pink : studioAccent).opacity(0.35)),
                               style: StrokeStyle(lineWidth: 1, dash: [3,4]))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct TimelinePlayhead: View {
    let session: ShowSession
    let scale: Double
    let height: Double

    var body: some View {
        Rectangle().fill(studioAccent.opacity(0.9)).frame(width: 1.5, height: height)
            .offset(x: 14 + session.position * scale).allowsHitTesting(false).accessibilityHidden(true)
    }
}

private enum TimelineFixtureEvent: Identifiable {
    case cue(LightingCue, FixtureState)
    case position(HeadPositionKey)
    case chase(ChoreographyClip)

    struct ID: Hashable {
        let kind: Int
        let value: UUID
    }

    var id: ID {
        switch self {
        case .cue(let cue, _): ID(kind: 0, value: cue.id)
        case .position(let key): ID(kind: 1, value: key.id)
        case .chase(let clip): ID(kind: 2, value: clip.id)
        }
    }

    var time: Double {
        switch self {
        case .cue(let cue, _): cue.time
        case .position(let key): key.time
        case .chase(let clip): clip.start
        }
    }

    var label: String {
        switch self {
        case .cue(let cue, let state): "\(cue.name) · \(state.label)"
        case .position: "Movement"
        case .chase(let clip): clip.name
        }
    }

    var appearance: TimelineTileAppearance {
        switch self {
        case .cue(let cue, let state):
            if let command = cue.timelineCommand { return TimelineTileAppearance(command) }
            if (cue.dimmerFade ?? 0) > 0 { return TimelineTileAppearance(.fade) }
            if cue.lead > 0, state.kind == .movingHead { return TimelineTileAppearance(.movement) }
            let color = TimelineTileAppearance.lightColor(state)
            return TimelineTileAppearance(symbol: color == nil ? "power" : state.kind == .plug ? "lightbulb.fill" : nil,
                                          color: color ?? .gray)
        case .position: return TimelineTileAppearance(.movement)
        case .chase: return TimelineTileAppearance(.chase)
        }
    }

    static func rows(cues: [LightingCue], keys: [HeadPositionKey], chases: [ChoreographyClip]) -> [UUID: [Self]] {
        var rows: [UUID: [Self]] = [:]
        for cue in cues where !cue.isManual {
            for entry in cue.entries { rows[entry.id, default: []].append(.cue(cue, entry.state)) }
        }
        for key in keys { rows[key.fixtureID, default: []].append(.position(key)) }
        for clip in chases {
            for target in clip.targets { rows[target.id, default: []].append(.chase(clip)) }
        }
        return rows
    }
}

private struct TimelineTileAppearance {
    let symbol: String?
    let color: Color

    init(symbol: String?, color: Color) {
        self.symbol = symbol
        self.color = color
    }

    init(_ command: FixtureTimelineCommand) {
        switch command {
        case .on: self.init(symbol: "lightbulb.fill", color: .yellow)
        case .off: self.init(symbol: "power", color: .gray)
        case .dimmer: self.init(symbol: "sun.max.half.filled", color: .orange)
        case .fade: self.init(symbol: "circle.lefthalf.filled", color: .orange)
        case .chase: self.init(symbol: "bolt.fill", color: .mint)
        case .movement: self.init(symbol: "arrow.up.and.down.and.arrow.left.and.right", color: .purple)
        default: self.init(symbol: nil, color: command.relayColor?.displayColor ?? .white)
        }
    }

    static func lightColor(_ state: FixtureState) -> Color? {
        switch state {
        case .plug(let on): return on ? .yellow : nil
        case .rgb(let color): return color == .off ? nil : color.displayColor
        case .head(let head):
            let colors: [Color] = [.white, .red, .green, .blue, .yellow, .cyan, .pink, .pink,
                                   .orange, .orange, .blue, .purple, .green]
            return head.dimmer > 0 ? colors[head.color].opacity(max(0.25, head.dimmer)) : nil
        }
    }
}

private struct TimelineTile: View {
    let appearance: TimelineTileAppearance
    let selected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(appearance.color.opacity(0.18))
            if let symbol = appearance.symbol {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(appearance.color)
            } else {
                RoundedRectangle(cornerRadius: 2).fill(appearance.color).frame(width: 13, height: 10)
            }
        }.frame(width: 24, height: 19)
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(selected ? studioAccent : .white.opacity(0.21)) }
            .contentShape(Rectangle())
    }
}

private struct TimelineFixtureLane: View {
    static let height = 52.0
    let session: ShowSession
    let fixture: PatchedFixture
    let events: [TimelineFixtureEvent]
    let scale: Double
    let duration: Double
    let snapping: Bool
    let draggedCommand: FixtureTimelineCommand?
    let editPosition: (HeadPositionKey) -> Void
    let editChase: (ChoreographyClip) -> Void

    @State private var targeted = false
    @GestureState private var movement: TileMove?
    private struct TileMove {
        let id: TimelineFixtureEvent.ID
        let time: Double
        var end: Double? = nil
    }

    private enum ClipDragPart {
        case body, start, end
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(targeted && session.canEdit && draggedCommand?.supports(fixture.kind) == true
                      ? studioAccent.opacity(0.23) : .white.opacity(0.025))
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { event in
                    guard !session.playing else { return }
                    session.seek(to: max(0, (event.location.x - 14) / scale))
                })
            stateBand.allowsHitTesting(false).accessibilityHidden(true)
            ForEach(events) { event in
                if case .cue(let cue, _) = event, cue.clipDuration != nil {
                    clipTile(event, cue: cue)
                } else {
                    tile(event)
                }
            }
        }
        .frame(height: Self.height)
        .overlay(alignment: .bottom) { Divider().allowsHitTesting(false) }
        .dropDestination(for: String.self) { items, location in
            guard session.canEdit, let item = items.first, let command = FixtureTimelineCommand(dragValue: item),
                  command.supports(fixture.kind) else { return false }
            return session.placeTimelineCommand(command, fixtureID: fixture.id, at: adjusted((location.x - 14) / scale))
        } isTargeted: { targeted = $0 }
    }

    private var stateBand: some View {
        let states: [(Double, FixtureState)] = events.compactMap { event in
            guard case .cue(let cue, let state) = event, cue.clipDuration == nil else { return nil }
            let time = movement?.id == event.id ? movement?.time ?? cue.time : cue.time
            return (time, state)
        }.sorted { $0.0 < $1.0 }
        return Canvas { context, _ in
            func band(from start: Double, to end: Double, y: Double, color: Color) {
                let width = (end - start) * scale
                guard width > 0 else { return }
                let rect = CGRect(x: 14 + start * scale, y: y, width: width, height: 4)
                context.fill(Path(rect), with: .color(color))
            }
            band(from: 0, to: duration, y: 24, color: .gray.opacity(0.22))
            for index in states.indices {
                guard let color = TimelineTileAppearance.lightColor(states[index].1) else { continue }
                let next = index + 1 < states.count ? states[index + 1].0 : duration
                band(from: states[index].0, to: next, y: 24, color: color.opacity(0.78))
            }
            for event in events {
                switch event {
                case .cue(let cue, let state) where cue.clipDuration != nil && cue.timelineCommand != .movement:
                    let start = movement?.id == event.id ? movement?.time ?? cue.time : cue.time
                    let end = movement?.id == event.id ? movement?.end ?? cue.end : cue.end
                    let color = cue.timelineCommand == .chase ? Color.mint : TimelineTileAppearance.lightColor(state)
                    band(from: start, to: end, y: 24, color: color ?? Color(white: 0.24))
                case .chase(let clip):
                    let start = movement?.id == event.id ? movement?.time ?? clip.start : clip.start
                    band(from: start, to: start + clip.duration, y: 46, color: .mint.opacity(0.62))
                default: break
                }
            }
        }
    }

    private func clipTile(_ event: TimelineFixtureEvent, cue: LightingCue) -> some View {
        let preview = movement?.id == event.id ? movement : nil
        let start = preview?.time ?? cue.time
        let end = preview?.end ?? cue.end
        let width = max(1, (end - start) * scale)
        let gripWidth = min(9, width / 4)
        let selected = session.selectedCueIDs.contains(cue.id)
        let appearance = event.appearance
        return ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(white: 0.13))
                .overlay { RoundedRectangle(cornerRadius: 4).fill(appearance.color.opacity(0.26)) }
                .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(selected ? studioAccent : appearance.color.opacity(0.60)) }
            HStack(spacing: 0) {
                trimHandle(width: gripWidth, label: "Trim clip start")
                    .gesture(clipDrag(event, cue: cue, part: .start))
                Button { open(event) } label: {
                    ZStack {
                        Color.clear
                        if width >= 16 {
                            if let symbol = appearance.symbol {
                                Image(systemName: symbol).font(.system(size: min(11, width / 3), weight: .semibold))
                                    .foregroundStyle(appearance.color)
                            } else {
                                RoundedRectangle(cornerRadius: 2).fill(appearance.color)
                                    .frame(width: min(13, width / 3), height: 8)
                            }
                        }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel(event.label)
                    .highPriorityGesture(clipDrag(event, cue: cue, part: .body))
                trimHandle(width: gripWidth, label: "Trim clip end")
                    .gesture(clipDrag(event, cue: cue, part: .end))
            }.padding(.vertical, 2)
        }
        .frame(width: width, height: 22)
        .offset(x: 14 + start * scale, y: 1)
        .zIndex(selected || preview != nil ? 2 : 1)
        .help("\(event.label) · \(studioTime(start)) to \(studioTime(end))")
        .contextMenu {
            Button("Remove Clip", role: .destructive) { remove(event) }.disabled(!session.canEdit)
        }
    }

    private func trimHandle(width: Double, label: String) -> some View {
        Rectangle().fill(.clear)
            .overlay {
                if width >= 4 {
                    Capsule().fill(.white.opacity(0.6)).frame(width: 2, height: 10)
                }
            }
            .contentShape(Rectangle())
            .frame(width: width)
            .accessibilityLabel(label)
            .help(label)
            .allowsHitTesting(session.canEdit)
    }

    private func clipDrag(_ event: TimelineFixtureEvent, cue: LightingCue, part: ClipDragPart) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("studio-timeline"))
            .updating($movement) { drag, value, _ in
                guard session.canEdit else { return }
                value = clipTiming(event, cue: cue, part: part, delta: drag.translation.width / scale)
            }
            .onEnded { drag in
                guard session.canEdit else { return }
                let timing = clipTiming(event, cue: cue, part: part, delta: drag.translation.width / scale)
                if let end = timing.end {
                    if part == .body {
                        session.moveFixtureCommand(cueID: cue.id, fixtureID: fixture.id, to: timing.time)
                    } else {
                        session.resizeClip(cueID: cue.id, fixtureID: fixture.id, start: timing.time, end: end)
                    }
                }
            }
    }

    private func clipTiming(_ event: TimelineFixtureEvent, cue: LightingCue, part: ClipDragPart, delta: Double) -> TileMove {
        let limit = session.project.song?.duration ?? 3600
        let minimum = CueTiming.minimumClipDuration
        func snap(_ time: Double) -> Double {
            snapping ? CueTiming.nearestMarker(to: time, in: session.project.markers, tolerance: 9 / scale) : time
        }
        switch part {
        case .body:
            let length = cue.clipDuration ?? minimum
            let start = min(max(0, limit - length), max(0, snap(cue.time + delta)))
            return TileMove(id: event.id, time: start, end: start + length)
        case .start:
            let maximum = max(0, cue.end - minimum)
            let start = min(maximum, max(0, snap(cue.time + delta)))
            return TileMove(id: event.id, time: start, end: cue.end)
        case .end:
            let end = min(limit, max(cue.time + minimum, snap(cue.end + delta)))
            return TileMove(id: event.id, time: cue.time, end: end)
        }
    }

    private func tile(_ event: TimelineFixtureEvent) -> some View {
        let time = movement?.id == event.id ? movement?.time ?? event.time : event.time
        let selected = session.selectedCueIDs.contains(event.id.value) && event.id.kind == 0
        let y = event.id.kind == 0 ? 2.0 : 29.0
        return Button { open(event) } label: {
            TimelineTile(appearance: event.appearance, selected: selected)
        }.buttonStyle(.plain)
            .offset(x: 2 + time * scale, y: y)
            .help("\(event.label) · \(studioTime(time))")
            .accessibilityLabel(event.label)
            .highPriorityGesture(DragGesture(minimumDistance: 5, coordinateSpace: .named("studio-timeline"))
                .updating($movement) { drag, value, _ in
                    guard session.canEdit else { return }
                    value = TileMove(id: event.id, time: adjusted(event.time + drag.translation.width / scale, event: event))
                }
                .onEnded { drag in
                    guard session.canEdit else { return }
                    retime(event, to: adjusted(event.time + drag.translation.width / scale, event: event))
                })
            .contextMenu {
                Button(event.id.kind == 2 ? "Remove Chase" : "Remove Command", role: .destructive) {
                    remove(event)
                }.disabled(!session.canEdit)
            }
    }

    private func adjusted(_ time: Double, event: TimelineFixtureEvent? = nil) -> Double {
        let snapped = snapping ? CueTiming.nearestMarker(to: time, in: session.project.markers, tolerance: 9 / scale) : time
        let limit: Double
        if case .chase(let clip) = event { limit = max(0, duration - clip.duration) }
        else { limit = duration }
        return min(limit, max(0, snapped))
    }

    private func open(_ event: TimelineFixtureEvent) {
        session.selection = .fixture(fixture.id)
        switch event {
        case .cue(let cue, _):
            session.selectCue(cue.id, extending: !NSEvent.modifierFlags.intersection([.shift, .command]).isEmpty)
        case .position(let key): if session.canEdit { editPosition(key) }
        case .chase(let clip): if session.canEdit { editChase(clip) }
        }
    }

    private func retime(_ event: TimelineFixtureEvent, to time: Double) {
        switch event {
        case .cue(let cue, _): session.moveFixtureCommand(cueID: cue.id, fixtureID: fixture.id, to: time)
        case .position(var key):
            key.time = time
            session.putPosition(key)
        case .chase(var clip):
            clip.start = time
            session.putChase(clip)
        }
    }

    private func remove(_ event: TimelineFixtureEvent) {
        switch event {
        case .cue(let cue, _): session.removeFixtureCommand(cueID: cue.id, fixtureID: fixture.id)
        case .position(let key): session.removePosition(key)
        case .chase(let clip): session.removeChase(clip)
        }
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
