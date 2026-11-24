import AppKit
import SwiftUI

struct ControllerEditor: View {
    let session: ShowSession
    @Environment(\.dismiss) private var dismiss
    @State private var draft = LightingController(name: "", kind: .dmx)
    @State private var selected: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Controller Patch").font(.title2.bold())
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    List(session.project.lighting.controllers, selection: $selected) { controller in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(controller.name).fontWeight(.medium)
                            Text("\(controller.kind.rawValue) · \(controller.capacity) outputs").font(.caption).foregroundStyle(.secondary)
                        }.tag(controller.id)
                    }
                    Button("New Controller", systemImage: "plus") { selected = nil; draft = LightingController(name: "", kind: .dmx) }
                }.frame(width: 220)
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Controller name", text: $draft.name)
                    Picker("Type", selection: $draft.kind) {
                        ForEach(LightingControllerKind.allCases) { Text($0.rawValue).tag($0) }
                    }.disabled(selected != nil)
                    if draft.kind == .arduino {
                        TextField("Relay count", value: $draft.relayCount, format: .number)
                    }
                    Text("Simulation").foregroundStyle(studioAccent)
                    HStack {
                        if let id = selected, let original = session.project.lighting.controllers.first(where: { $0.id == id }) {
                            Button("Remove", role: .destructive) {
                                session.removeController(original)
                                if session.message == nil {
                                    selected = nil
                                    draft = LightingController(name: "", kind: .dmx)
                                }
                            }
                        }
                        Spacer()
                        Button(selected == nil ? "Add Controller" : "Apply") {
                            session.setController(draft)
                            if session.message == nil { selected = draft.id }
                        }.buttonStyle(.borderedProminent)
                    }
                    if let message = session.message { Text(message).foregroundStyle(.orange).font(.caption) }
                }.textFieldStyle(.roundedBorder).padding(.top, 6)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(18).frame(width: 580, height: 360)
            .onChange(of: selected) { _, id in
                if let controller = session.project.lighting.controllers.first(where: { $0.id == id }) { draft = controller }
            }
    }
}

struct PositionForm: View {
    let session: ShowSession
    @State var draft: HeadPositionKey
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Movement Key").font(.title2.bold())
            TextField("Time (seconds)", value: $draft.time, format: .number)
            LabeledContent("Pan") { Slider(value: $draft.pan, in: 0...1) }
            LabeledContent("Tilt") { Slider(value: $draft.tilt, in: 0...1) }
            Picker("Curve", selection: $draft.curve) {
                ForEach(CueCurve.allCases) { Text($0.rawValue).tag($0) }
            }
            if let message = session.message { Text(message).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Delete", role: .destructive) { session.removePosition(draft); dismiss() }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply") { session.putPosition(draft); if session.message == nil { dismiss() } }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 355).textFieldStyle(.roundedBorder)
    }
}

struct ChaseForm: View {
    let session: ShowSession
    @State var draft: ChoreographyClip
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edit Chase").font(.title2.bold())
            TextField("Name", text: $draft.name)
            Picker("Pattern", selection: $draft.pattern) {
                ForEach(ChoreographyPattern.allCases) { Text($0.rawValue).tag($0) }
            }
            HStack {
                TextField("Start (s)", value: $draft.start, format: .number)
                TextField("Step (s)", value: $draft.interval, format: .number)
                TextField("Repeats", value: $draft.repeats, format: .number)
            }
            if draft.pattern == .wave {
                LabeledContent("Wave angle") { Slider(value: $draft.angle, in: -180...180) }
            }
            HStack {
                ForEach(draft.colors.indices, id: \.self) { index in
                    ColorPicker("Color \(index + 1)", selection: color(index), supportsOpacity: false)
                }
            }
            List(Array(draft.targets.enumerated()), id: \.element.id) { index, target in
                HStack {
                    Text(session.project.lighting.fixtures.first { $0.id == target.id }?.name ?? "Fixture")
                    Spacer()
                    Button("Move Up", systemImage: "arrow.up") { draft.targets.swapAt(index, index - 1) }.disabled(index == 0)
                    Button("Move Down", systemImage: "arrow.down") { draft.targets.swapAt(index, index + 1) }.disabled(index == draft.targets.count - 1)
                }.labelStyle(.iconOnly)
            }.frame(height: 130)
            if let message = session.message { Text(message).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Delete Chase", role: .destructive) { session.removeChase(draft); dismiss() }
                Button("Save Preset") { session.savePreset(from: draft) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply") { session.putChase(draft); if session.message == nil { dismiss() } }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 465).textFieldStyle(.roundedBorder)
    }

    private func color(_ index: Int) -> Binding<Color> {
        Binding(get: {
            let c = draft.colors[index]
            return Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z))
        }, set: { value in
            guard let c = NSColor(value).usingColorSpace(.sRGB) else { return }
            draft.colors[index] = SIMD4(Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent), 1)
        })
    }
}

struct TakeReview: View {
    let session: ShowSession
    @State private var selected: Set<UUID> = []
    @State private var times: [UUID: Double] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Review Cue Take").font(.title2.bold())
            Text("Choose which cues to add and adjust their song times.").foregroundStyle(.secondary)
            List(session.take) { cue in
                HStack {
                    Toggle(isOn: Binding(get: { selected.contains(cue.id) }, set: {
                        if $0 { selected.insert(cue.id) } else { selected.remove(cue.id) }
                    })) { Text(cue.name) }.toggleStyle(.checkbox)
                    Spacer()
                    TextField("Time for \(cue.name)", value: Binding(get: { times[cue.id] ?? cue.time }, set: { times[cue.id] = $0 }),
                              format: .number.precision(.fractionLength(3))).multilineTextAlignment(.trailing).frame(width: 80)
                        .disabled(!selected.contains(cue.id))
                    Text("s").foregroundStyle(.secondary)
                }
            }.frame(minHeight: 180)
            if let message = session.message { Text(message).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Discard Take", role: .destructive) { session.discardTake() }
                Spacer()
                Button("Close") { session.reviewTake(false) }.keyboardShortcut(.cancelAction)
                Button("Add Selected to Timeline") { _ = session.addTake(selected, times: times) }
                    .keyboardShortcut(.defaultAction).disabled(selected.isEmpty)
            }
        }.padding(18).frame(width: 540)
            .onAppear { selected = Set(session.take.map(\.id)) }
    }
}
