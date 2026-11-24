import AppKit
import SwiftUI

let studioAccent = Color(red: 0.36, green: 0.83, blue: 0.96)
let studioBackground = Color(red: 0.055, green: 0.067, blue: 0.088)
let panelBackground = Color(red: 0.088, green: 0.103, blue: 0.128)

struct StudioWindow: View {
    let session: ShowSession
    let remote: StudioPhoneRemote
    let updates: ReleaseUpdateChecker
    let version: String
    @State private var showPhone = false
    @State private var showPatch = false
    @State private var renaming = false
    @State private var draftName = ""

    var body: some View {
        Group {
            if session.isHome { home }
            else { studio }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(studioBackground)
        .preferredColorScheme(.dark)
        .tint(studioAccent)
        .overlay(alignment: .topTrailing) {
            if !session.playing, !session.recording, !session.ready, !session.loadingSong,
               !session.reviewingTake, !showPatch, !showPhone {
                StudioUpdateNotice(checker: updates, installed: version)
            }
        }
        .onChange(of: session.project.id) { _, _ in remote.stop() }
        .sheet(isPresented: $showPhone) { StudioPhonePanel(remote: remote) }
        .sheet(isPresented: $showPatch) { ControllerEditor(session: session) }
        .sheet(isPresented: Binding(get: { session.reviewingTake && session.workspace == .edit },
                                    set: { session.reviewTake($0) })) {
            TakeReview(session: session)
        }
    }

    private var home: some View {
        HStack(alignment: .top, spacing: 54) {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "light.beacon.max.fill")
                        .font(.system(size: 31)).foregroundStyle(studioAccent)
                    Text("Light Show Studio").font(.system(size: 39, weight: .semibold))
                }
                Button { session.newShow() } label: {
                    Label("New Light Show", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                Button { session.chooseShow() } label: {
                    Label("Open Light Show…", systemImage: "folder")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.controlSize(.large)
                Button { session.chooseSetup() } label: {
                    Label("New Show from Setup…", systemImage: "square.stack.3d.up")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.controlSize(.large)
            }.frame(width: 370, alignment: .leading)
            VStack(alignment: .leading, spacing: 14) {
                Text("Recent Shows").font(.title3.bold())
                if session.recentShows.isEmpty {
                    Text("Saved shows appear here.").foregroundStyle(.secondary).padding(.vertical, 8)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(session.recentShows, id: \.self) { url in
                                Button {
                                    session.open(url)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "waveform.path").font(.title3).foregroundStyle(studioAccent)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(url.deletingPathExtension().lastPathComponent).fontWeight(.medium)
                                            Text(url.deletingLastPathComponent().lastPathComponent).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.up.right").foregroundStyle(.secondary).font(.caption)
                                    }.padding(13)
                                        .background(panelBackground, in: RoundedRectangle(cornerRadius: 9))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                if let message = session.message { Text(message).font(.callout).foregroundStyle(.orange) }
            }.frame(maxWidth: 460, maxHeight: 400, alignment: .topLeading)
        }.padding(46)
    }

    private var studio: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if session.workspace == .edit {
                HSplitView {
                    FixtureSidebar(session: session, openPatch: { showPatch = true }).frame(minWidth: 185, idealWidth: 205, maxWidth: 270)
                    StageView(session: session, interactive: true).frame(minWidth: 345)
                    StudioInspector(session: session).frame(minWidth: 295, idealWidth: 320, maxWidth: 440)
                }
                Divider()
                TimelineView(session: session)
            } else {
                HSplitView {
                    StageView(session: session, interactive: false).frame(minWidth: 430)
                    OperatorPanel(session: session).frame(minWidth: 295, idealWidth: 330, maxWidth: 450)
                }
            }
            Divider()
            TransportBar(session: session)
            if let message = session.message {
                HStack {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Dismiss", systemImage: "xmark") { session.message = nil }
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                }.padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Button("Project Home", systemImage: "house") { session.showHome() }
                .labelStyle(.iconOnly).help("Project Home")
            HStack(spacing: 5) {
                Button {
                    draftName = session.project.name
                    renaming = true
                } label: {
                    Text(session.project.name).fontWeight(.semibold).lineLimit(1)
                }.buttonStyle(.plain).disabled(!session.canEdit).help("Rename show")
                    .popover(isPresented: $renaming) {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("Rename Show").font(.headline)
                            TextField("Show name", text: $draftName)
                                .textFieldStyle(.roundedBorder)
                            Button("Rename") {
                                session.rename(draftName)
                                if session.message == nil { renaming = false }
                            }.disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draftName.count > 80)
                                .keyboardShortcut(.defaultAction)
                        }.padding(14).frame(width: 260)
                    }
                if session.hasUnsavedChanges { Circle().fill(.secondary).frame(width: 5, height: 5).help("Unsaved changes") }
            }.frame(minWidth: 140, alignment: .leading)
            Spacer()
            Picker("Workspace", selection: Binding(get: { session.workspace }, set: { session.switchWorkspace($0) })) {
                ForEach(StudioWorkspace.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().fixedSize()
            Spacer()
            if session.workspace == .edit {
                Button("Soundtrack…", systemImage: "music.note") { session.chooseSong() }.disabled(!session.canEdit)
            }
            Button(remote.isPaired ? "Phone Connected" : "Phone Remote", systemImage: "iphone") { showPhone = true }
            Button("Save", systemImage: "square.and.arrow.down") { session.save() }.disabled(session.loadingSong)
        }.padding(.horizontal, 14).padding(.vertical, 11)
            .background(panelBackground)
    }
}

struct FixtureSidebar: View {
    let session: ShowSession
    let openPatch: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Fixtures").font(.headline)
                Spacer()
                Menu {
                    ForEach(FixtureKind.allCases) { kind in
                        Button(kind.rawValue) { session.addFixture(kind) }
                    }
                } label: { Image(systemName: "plus") }
                    .menuIndicator(.hidden).fixedSize().help("Add fixture").disabled(!session.canEdit)
            }.padding(13)
            List(selection: Binding<StudioSelection?>(get: { session.selection }, set: { session.selection = $0 ?? .all })) {
                Label("All Fixtures", systemImage: "lightbulb.2").tag(StudioSelection.all)
                if !session.groups.isEmpty {
                    Section("Groups") {
                        ForEach(session.groups, id: \.self) { group in
                            Label(group, systemImage: "square.stack.3d.up").tag(StudioSelection.group(group))
                        }
                    }
                }
                Section("Patch") {
                    ForEach(session.project.lighting.fixtures) { fixture in
                        VStack(alignment: .leading, spacing: 2) {
                            Label(fixture.name, systemImage: fixture.kind.symbol).lineLimit(1)
                            Text(fixture.slots.map(String.init).joined(separator: " · "))
                                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }.tag(StudioSelection.fixture(fixture.id))
                    }
                }
            }.listStyle(.sidebar).scrollContentBackground(.hidden)
            Divider()
            Button("Controller Patch…", systemImage: "slider.horizontal.3", action: openPatch)
                .disabled(!session.canEdit).frame(maxWidth: .infinity).padding(10)
        }.background(panelBackground)
    }
}

extension FixtureKind {
    var symbol: String {
        switch self {
        case .movingHead: "light.beacon.max"
        case .plug: "powerplug.fill"
        case .rgb: "light.strip.2"
        }
    }
}

struct StageView: View {
    let session: ShowSession
    let interactive: Bool
    @State private var moving: UUID?
    @State private var point: CGPoint = .zero
    @State private var photoOptions = false
    @State private var opacity = 0.65
    @State private var photoImage: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(interactive ? "Fixture Layout" : "Stage Monitor").font(.headline)
                Spacer()
                if interactive {
                    Button("Stage Photo", systemImage: "photo") {
                        opacity = session.project.stagePhoto?.opacity ?? 0.65
                        photoOptions = true
                    }.popover(isPresented: $photoOptions) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Stage Photo").font(.headline)
                            if let photo = session.project.stagePhoto {
                                Toggle("Lock Photo", isOn: Binding(get: { photo.locked }, set: session.setStagePhotoLock))
                                Slider(value: $opacity, in: 0...1) { editing in
                                    if !editing { session.setStagePhotoOpacity(opacity) }
                                }.accessibilityLabel("Photo opacity").disabled(photo.locked)
                                Button("Replace Photo…") { photoOptions = false; session.chooseStagePhoto() }.disabled(photo.locked)
                                Button("Remove Photo") { session.removeStagePhoto(); photoOptions = false }.disabled(photo.locked)
                            } else {
                                Button("Choose Photo…") { photoOptions = false; session.chooseStagePhoto() }.buttonStyle(.borderedProminent)
                            }
                        }.padding(14).frame(width: 220)
                    }.disabled(!session.canEdit)
                }
                Label("Simulation", systemImage: "circle.dotted")
                    .font(.caption.weight(.medium)).foregroundStyle(studioAccent)
            }
            GeometryReader { geometry in
                let size = geometry.size
                let rect = stageRect(in: size)
                ZStack(alignment: .topLeading) {
                    Canvas { context, bounds in
                        var grid = Path()
                        for x in stride(from: 0.0, through: bounds.width, by: 22) {
                            grid.move(to: CGPoint(x: x, y: 0))
                            grid.addLine(to: CGPoint(x: x, y: bounds.height))
                        }
                        for y in stride(from: 0.0, through: bounds.height, by: 22) {
                            grid.move(to: CGPoint(x: 0, y: y))
                            grid.addLine(to: CGPoint(x: bounds.width, y: y))
                        }
                        context.stroke(grid, with: .color(.white.opacity(0.075)), lineWidth: 1)
                        let outline = Path(roundedRect: CGRect(origin: .zero, size: bounds).insetBy(dx: 18, dy: 18), cornerRadius: 10)
                        context.stroke(outline, with: .color(.white.opacity(0.15)), style: StrokeStyle(lineWidth: 1, dash: [4,5]))
                    }.background(.black.opacity(0.26))
                    if let photoImage, let photo = session.project.stagePhoto {
                        Image(nsImage: photoImage).resizable()
                            .frame(width: rect.width, height: rect.height)
                            .opacity(photoOptions && !photo.locked ? opacity : photo.opacity)
                            .position(x: rect.midX, y: rect.midY)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                    if session.project.lighting.fixtures.isEmpty {
                        ContentUnavailableView("Add a Fixture", systemImage: "lightbulb")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ForEach(Array(session.project.lighting.fixtures.enumerated()), id: \.element.id) { index, fixture in
                            let origin = fixture.previewPlacement?.origin ?? FixturePreviewPlacement.initial(index: index, kind: fixture.kind).origin
                            let state = session.effectiveState(fixture)
                            let selected = session.selection == .fixture(fixture.id)
                            FixtureNode(fixture: fixture, state: state, selected: selected)
                                .position(moving == fixture.id ? point : location(origin, in: rect))
                                .onTapGesture { if interactive { session.selection = .fixture(fixture.id) } }
                                .gesture(DragGesture(minimumDistance: 5, coordinateSpace: .named("fixture-stage"))
                                    .onChanged { event in
                                        guard interactive && session.canEdit else { return }
                                        moving = fixture.id
                                        point = bounded(event.location, in: rect)
                                    }
                                    .onEnded { event in
                                        defer { moving = nil }
                                        guard interactive, session.canEdit, moving == fixture.id, rect.width > 0, rect.height > 0 else { return }
                                        let end = bounded(event.location, in: rect)
                                        session.move(fixture, to: FixturePreviewPoint(x: (end.x - rect.minX)/rect.width, y: (end.y - rect.minY)/rect.height))
                                        session.selection = .fixture(fixture.id)
                                    })
                        }
                    }
                }.coordinateSpace(name: "fixture-stage").clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }.padding(16)
            .task(id: session.project.stagePhoto?.data) {
                photoImage = session.project.stagePhoto.flatMap { NSImage(data: $0.data) }
            }
    }

    private func stageRect(in size: CGSize) -> CGRect {
        let available = CGRect(x: 25, y: 26, width: max(0, size.width - 50), height: max(0, size.height - 55))
        guard let photo = session.project.stagePhoto, available.width > 0, available.height > 0 else { return available }
        let scale = min(available.width / Double(photo.width), available.height / Double(photo.height))
        let width = Double(photo.width) * scale
        let height = Double(photo.height) * scale
        return CGRect(x: available.midX - width/2, y: available.midY - height/2, width: width, height: height)
    }

    private func location(_ point: FixturePreviewPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
    }

    private func bounded(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: min(rect.maxX, max(rect.minX, point.x)), y: min(rect.maxY, max(rect.minY, point.y)))
    }
}

struct FixtureNode: View {
    let fixture: PatchedFixture
    let state: FixtureState
    let selected: Bool

    private var lamp: Color {
        switch state {
        case .plug(let on): on ? .yellow : .gray
        case .rgb(let color): color.displayColor
        case .head(let head): head.dimmer > 0.01 ? .white.opacity(max(0.25,head.dimmer)) : .gray
        }
    }
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: fixture.kind.symbol)
                .foregroundStyle(lamp).font(.system(size: 18, weight: .medium))
                .frame(width: 38, height: 35)
                .background(lamp.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
                .overlay { RoundedRectangle(cornerRadius: 9).stroke(selected ? studioAccent : lamp.opacity(0.45)) }
            Text(fixture.name).font(.caption2).lineLimit(1).padding(.horizontal, 4)
                .background(studioBackground.opacity(0.85))
        }.frame(width: 103).contentShape(Rectangle())
            .accessibilityLabel("\(fixture.name), \(state.label)")
            .help("\(fixture.name) · \(state.label)")
    }
}

extension RelayColor {
    var displayColor: Color {
        switch self {
        case .off: .gray
        case .red: .red
        case .green: .green
        case .blue: .blue
        case .yellow: .yellow
        case .magenta: .pink
        case .cyan: .cyan
        case .white: .white
        }
    }
}
