import AppKit
import SwiftUI

struct StudioInspector: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case fixtures = "Fixture", looks = "Looks", motion = "Motion & Chases"
        var id: Self { self }
    }

    let session: ShowSession
    @State private var tab = Tab.fixtures

    var body: some View {
        VStack(spacing: 0) {
            Picker("Lighting inspector", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }.labelsHidden().pickerStyle(.segmented).padding(10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    if let cue = session.selectedCue {
                        CueInspector(session: session, cue: cue).id(cue.id)
                        Divider()
                    }
                    switch tab {
                    case .fixtures: fixturePanel
                    case .looks: LookInspector(session: session)
                    case .motion: MotionInspector(session: session)
                    }
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            }.textFieldStyle(.roundedBorder)
        }.background(panelBackground)
    }

    @ViewBuilder private var fixturePanel: some View {
        if case .fixture(let id) = session.selection,
           let fixture = session.project.lighting.fixtures.first(where: { $0.id == id }) {
            FixtureForm(session: session, fixture: fixture).id(fixture.id)
        } else {
            Text(session.selection == .all ? "All Fixtures" : "Fixture Group").font(.headline)
            Text("\(session.selectedFixtures.count) selected").foregroundStyle(.secondary)
            Text("Select an individual fixture to edit its patch. Open Looks to capture the selected group.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

struct FixtureForm: View {
    let session: ShowSession
    let fixture: PatchedFixture
    @State private var draft: PatchedFixture
    @State private var asksDelete = false

    init(session: ShowSession, fixture: PatchedFixture) {
        self.session = session
        self.fixture = fixture
        _draft = State(initialValue: fixture)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(fixture.kind.rawValue, systemImage: fixture.kind.symbol).font(.headline)
            VStack(spacing: 8) {
                TextField("Fixture name", text: $draft.name)
                TextField("Group", text: $draft.group)
                Picker("Controller", selection: $draft.controllerID) {
                    ForEach(session.project.lighting.controllers.filter { $0.kind == fixture.kind.controllerKind }) {
                        Text($0.name).tag($0.id)
                    }
                }
                LabeledContent(fixture.kind == .rgb ? "Red relay" : "Address") {
                    TextField("Address", value: $draft.address, format: .number).frame(width: 75)
                }
                if fixture.kind == .rgb {
                    LabeledContent("Green relay") { TextField("Green relay", value: $draft.green, format: .number).frame(width: 75) }
                    LabeledContent("Blue relay") { TextField("Blue relay", value: $draft.blue, format: .number).frame(width: 75) }
                }
                if fixture.kind == .movingHead {
                    Picker("Profile", selection: $draft.headChannels) {
                        Text("9 channels").tag(9)
                        Text("11 channels").tag(11)
                    }
                }
                HStack {
                    Button("Remove Fixture", role: .destructive) { asksDelete = true }
                    Spacer()
                    Button("Apply Patch") {
                        let changes = draft
                        session.updateFixture(fixture.id) { current in
                            let placement = current.previewPlacement
                            current = changes
                            current.previewPlacement = placement
                        }
                    }.buttonStyle(.borderedProminent).disabled(draft == fixture)
                }
            }.disabled(!session.canEdit)
            Divider()
            Text("Audition").font(.headline)
            FixtureAuditionControls(session: session, fixture: fixture)
                .disabled(!session.canEdit)
            Button("Release to Timeline") { session.clearAudition() }.disabled(!session.canEdit)
        }
        .onChange(of: fixture) { _, value in draft = value }
        .confirmationDialog("Remove \(fixture.name)?", isPresented: $asksDelete, titleVisibility: .visible) {
            Button("Remove Fixture", role: .destructive) { session.removeFixture(fixture) }
        } message: {
            Text("Its entries will be removed from looks, cues, chases, and motion keys.")
        }
    }
}

struct FixtureAuditionControls: View {
    let session: ShowSession
    let fixture: PatchedFixture
    var body: some View {
        FixtureStateControls(kind: fixture.kind, state: Binding(get: { session.effectiveState(fixture) },
            set: { session.audition(fixture, state: $0) }))
        if fixture.kind == .movingHead {
            Button("Capture Position at Playhead") { session.capturePosition(fixture) }
        }
    }
}

private struct FixtureStateControls: View {
    let kind: FixtureKind
    @Binding var state: FixtureState

    var body: some View {
        switch kind {
        case .plug:
            Toggle("Power", isOn: Binding(get: {
                if case .plug(let on) = state { return on }
                return false
            }, set: { state = .plug($0) }))
        case .rgb:
            Picker("Color", selection: Binding(get: {
                if case .rgb(let color) = state { return color }
                return .off
            }, set: { state = .rgb($0) })) {
                ForEach(RelayColor.allCases) { Text($0.label).tag($0) }
            }
        case .movingHead:
            headSlider("Pan", \.pan)
            headSlider("Tilt", \.tilt)
            headSlider("Dimmer", \.dimmer)
            Picker("Color wheel", selection: head(\.color)) {
                ForEach(HeadLook.colors.indices, id: \.self) { Text(HeadLook.colors[$0]).tag($0) }
            }
            Picker("Gobo", selection: head(\.gobo)) {
                ForEach(0...7, id: \.self) { Text($0 == 0 ? "Open" : "Gobo \( $0 )").tag($0) }
            }
        }
    }

    private func head<T>(_ path: WritableKeyPath<HeadLook,T>) -> Binding<T> {
        func current() -> HeadLook {
            if case .head(let value) = state { return value }
            return HeadLook()
        }
        return Binding(get: { current()[keyPath: path] }, set: { value in
            var next = current()
            next[keyPath: path] = value
            state = .head(next)
        })
    }

    private func headSlider(_ name: String, _ path: WritableKeyPath<HeadLook, Double>) -> some View {
        LabeledContent(name) { Slider(value: head(path), in: 0...1).accessibilityLabel(name) }
    }
}

struct LookInspector: View {
    let session: ShowSession
    @State private var name = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Fixture Looks").font(.headline)
            HStack {
                TextField("Look name", text: $name)
                Button("Capture") {
                    session.captureLook(name)
                    if session.message == nil { name = "" }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !session.canEdit || session.selectedFixtures.isEmpty)
            }
            Text("Captures the current state of \(session.selectedFixtures.count) selected fixtures.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(session.project.lighting.looks) { look in
                VStack(alignment: .leading, spacing: 7) {
                    Text(look.name).fontWeight(.semibold)
                    HStack {
                        Button(session.recording ? "Record Trigger" : "Trigger") { session.triggerLook(look) }
                        Button("Place Cue") { session.place(look) }.disabled(!session.canEdit)
                        Spacer()
                        Button("Remove Look", systemImage: "minus.circle", role: .destructive) { session.removeLook(look) }
                            .labelStyle(.iconOnly).disabled(!session.canEdit)
                    }
                }.padding(9).background(.black.opacity(0.21), in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }
}

struct CueInspector: View {
    let session: ShowSession
    @State private var cue: LightingCue
    @State private var editingFixtureID: UUID?

    init(session: ShowSession, cue: LightingCue) {
        self.session = session
        _cue = State(initialValue: cue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Selected Cue").font(.headline)
                Spacer()
                Button("Close Cue Inspector", systemImage: "xmark") { session.selectedCueID = nil }.labelStyle(.iconOnly)
            }
            Group {
                TextField("Cue name", text: $cue.name)
                LabeledContent("Time (seconds)") { TextField("Cue time", value: $cue.time, format: .number.precision(.fractionLength(3))).frame(width: 76) }
                Toggle("Manual only", isOn: Binding(get: { cue.isManual }, set: { cue.manualOnly = $0 }))
                if cue.entries.contains(where: { $0.state.kind == .movingHead }) {
                    Picker("Motion", selection: Binding(get: { cue.motionCurve ?? .snap }, set: { cue.motionCurve = $0 })) {
                        ForEach(CueCurve.allCases) { Text($0.rawValue).tag($0) }
                    }
                    LabeledContent("Move lead (s)") { TextField("Move lead", value: $cue.lead, format: .number).frame(width: 76) }
                    LabeledContent("Dimmer fade (s)") {
                        TextField("Dimmer fade", value: Binding(get: { cue.dimmerFade ?? 0 }, set: { cue.dimmerFade = $0 }), format: .number)
                            .frame(width: 76)
                    }
                }
                fixtureTargets
                HStack {
                    Button("Preview Cue") { session.previewCue(cue) }.disabled(cue.entries.isEmpty)
                    Button("Release Preview") { session.clearAudition() }
                }
                HStack {
                    Button("Delete Cue", role: .destructive) { session.removeCue(cue) }
                    Spacer()
                    Button("Apply") { session.setCue(cue) }.disabled(cue.entries.isEmpty)
                }
            }.disabled(!session.canEdit)
        }.onChange(of: session.selectedCue) { _, value in if let value { cue = value } }
    }
    private var fixtureTargets: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Cue Fixtures").font(.subheadline.bold())
                Spacer()
                let fixtures = session.project.lighting.fixtures.filter { fixture in
                    !cue.entries.contains { $0.id == fixture.id }
                }
                Menu("Add Fixture") {
                    ForEach(fixtures) { fixture in
                        Button(fixture.name) {
                            cue.entries.append(FixtureLookEntry(id: fixture.id, state: session.effectiveState(fixture)))
                            editingFixtureID = fixture.id
                        }
                    }
                }.fixedSize().disabled(fixtures.isEmpty)
            }
            ForEach(cue.entries) { entry in
                if let fixture = session.project.lighting.fixtures.first(where: { $0.id == entry.id }) {
                    HStack {
                        Button {
                            editingFixtureID = editingFixtureID == entry.id ? nil : entry.id
                        } label: {
                            Label(fixture.name, systemImage: editingFixtureID == entry.id ? "chevron.down" : "chevron.right")
                                .lineLimit(1)
                        }.buttonStyle(.plain)
                        Spacer()
                        Button("Remove from Cue", systemImage: "minus.circle", role: .destructive) {
                            cue.entries.removeAll { $0.id == entry.id }
                        }.buttonStyle(.borderless).labelStyle(.iconOnly)
                    }
                    if editingFixtureID == entry.id {
                        FixtureStateControls(kind: fixture.kind, state: Binding(get: {
                            cue.entries.first { $0.id == entry.id }?.state ?? fixture.kind.dark
                        }, set: { state in
                            if let index = cue.entries.firstIndex(where: { $0.id == entry.id }) { cue.entries[index].state = state }
                        }))
                    }
                }
            }
        }.padding(9).background(.black.opacity(0.21), in: RoundedRectangle(cornerRadius: 7))
    }

}

struct MotionInspector: View {
    let session: ShowSession
    @State private var chase: ChoreographyClip?
    @State private var key: HeadPositionKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let head = session.selectedFixtures.first(where: { $0.kind == .movingHead }),
               session.selectedFixtures.count == 1 {
                Text("Movement Path").font(.headline)
                HeadPathPreview(keys: session.project.lighting.positionKeys.filter { $0.fixtureID == head.id })
                Button("Capture Position") { session.capturePosition(head) }.disabled(!session.canEdit)
                ForEach(session.project.lighting.positionKeys.filter { $0.fixtureID == head.id }.sorted { $0.time < $1.time }) { item in
                    Button {
                        key = item
                    } label: {
                        Label("\(studioTime(item.time)) · \(item.curve.rawValue)", systemImage: "diamond")
                    }.disabled(!session.canEdit)
                }
                Divider()
            }
            HStack {
                Text("Chases").font(.headline)
                Spacer()
                Button("Add at Playhead", systemImage: "plus") { session.createChase() }
                    .disabled(!session.canEdit || session.selectedFixtures.isEmpty)
            }
            ForEach(session.project.chases) { item in
                Button { chase = item } label: {
                    HStack {
                        Text(item.name)
                        Spacer()
                        Text(studioTime(item.start)).monospacedDigit().foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.disabled(!session.canEdit)
            }
            if !session.project.lighting.lightingEffectPresets.isEmpty {
                Divider()
                Text("Chase Presets").font(.headline)
                ForEach(session.project.lighting.lightingEffectPresets) { preset in
                    Button { session.placePreset(preset) } label: {
                        Label(preset.name, systemImage: "plus.circle")
                    }.disabled(!session.canEdit || session.selectedFixtures.isEmpty)
                }
            }
        }
        .sheet(item: $chase) { ChaseForm(session: session, draft: $0) }
        .sheet(item: $key) { PositionForm(session: session, draft: $0) }
    }
}

struct HeadPathPreview: View {
    let keys: [HeadPositionKey]
    var body: some View {
        Canvas { context, size in
            let sorted = keys.sorted { $0.time < $1.time }
            for (index,key) in sorted.enumerated() {
                let point = HeadPathGeometry.point(pan: key.pan, tilt: key.tilt, size: size)
                if index > 0 {
                    let last = sorted[index - 1]
                    var line = Path()
                    line.move(to: HeadPathGeometry.point(pan: last.pan, tilt: last.tilt, size: size))
                    line.addLine(to: point)
                    context.stroke(line, with: .color(studioAccent), lineWidth: 1.5)
                }
                context.fill(Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)), with: .color(studioAccent))
            }
        }.frame(height: 89).background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 7))
            .overlay { if keys.isEmpty { Text("Capture two positions to make a path.").font(.caption).foregroundStyle(.secondary) } }
    }
}
