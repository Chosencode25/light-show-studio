import SwiftUI

struct ProgramEditor: View {
    let session: ShowSession
    let settings: EditorLayoutSettings
    let openPatch: () -> Void
    let editFixture: (PatchedFixture) -> Void
    @GestureState private var dividerDrag: DividerDrag?

    private struct DividerDrag {
        let id: UUID
        let fraction: CGFloat
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = settings.displayedLayout
            let base = EditorLayoutGeometry(layout: layout, size: proxy.size)
            let geometry = dividerDrag.map {
                EditorLayoutGeometry(layout: layout.resizing($0.id, to: $0.fraction), size: proxy.size)
            } ?? base
            ZStack(alignment: .topLeading) {
                // Keep panel identities stable so switching layouts preserves local editor drafts and zoom.
                ForEach(EditorPanel.allCases) { panel in
                    let frame = geometry.panels[panel]
                    panelView(panel)
                        .frame(width: frame?.width ?? proxy.size.width, height: frame?.height ?? proxy.size.height)
                        .clipped()
                        .contentShape(Rectangle())
                        .offset(x: frame?.minX ?? 0, y: frame?.minY ?? 0)
                        .opacity(frame == nil ? 0 : 1)
                        .allowsHitTesting(frame != nil)
                        .disabled(frame == nil)
                        .accessibilityHidden(frame == nil)
                }
                ForEach(base.dividers) { divider in
                    let frame = geometry.dividers.first { $0.id == divider.id }?.frame ?? divider.frame
                    EditorDivider(axis: divider.axis, dragging: dividerDrag?.id == divider.id)
                        .frame(width: frame.width, height: frame.height)
                        .gesture(resizeGesture(for: divider))
                        .accessibilityLabel(divider.axis == .horizontal ? "Panel width divider" : "Panel height divider")
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment: settings.resize(divider.id, to: divider.fraction(after: 20))
                            case .decrement: settings.resize(divider.id, to: divider.fraction(after: -20))
                            @unknown default: break
                            }
                        }
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .coordinateSpace(name: "program-editor")
        .clipped()
    }

    private func resizeGesture(for divider: EditorLayoutGeometry.Divider) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("program-editor"))
            .updating($dividerDrag) { event, preview, _ in
                let fraction = divider.fraction(after: divider.axis.length(event.translation))
                preview = DividerDrag(id: divider.id, fraction: fraction)
            }
            .onEnded { event in
                settings.resize(divider.id, to: divider.fraction(after: divider.axis.length(event.translation)))
            }
    }

    private func panelView(_ panel: EditorPanel) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(panel.rawValue).font(.caption.weight(.semibold)).lineLimit(1)
                Spacer()
                if panel == .fixtures {
                    Menu {
                        ForEach(FixtureKind.allCases) { kind in
                            Button(kind.rawValue) { session.addFixture(kind) }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .fixedSize()
                    .menuIndicator(.hidden)
                    .menuStyle(.borderlessButton)
                    .accessibilityLabel("Add fixture")
                    .help("Add fixture")
                    .disabled(!session.canEdit)
                }
                Menu {
                    if settings.expandedPanel != nil {
                        Button("Restore Panels") { settings.restorePanels() }
                    } else {
                        Button("Expand Panel") { settings.expand(panel) }.disabled(settings.layout.panels.count == 1)
                        Divider()
                        ForEach(EditorDockSide.allCases) { side in
                            Menu("Open \(side.rawValue)") {
                                ForEach(settings.availablePanels) { candidate in
                                    Button(candidate.rawValue) { settings.open(candidate, beside: panel, on: side) }
                                }
                            }.disabled(settings.availablePanels.isEmpty)
                        }
                        Divider()
                        Button("Close Panel") { settings.close(panel) }.disabled(settings.layout.panels.count == 1)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .fixedSize()
                .menuIndicator(.hidden)
                .menuStyle(.borderlessButton)
                .accessibilityLabel("\(panel.rawValue) panel options")
                .help("Open or close editor panels")
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(panelBackground)
            Divider()
            panelContent(panel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private func panelContent(_ panel: EditorPanel) -> some View {
        switch panel {
        case .fixtures: FixtureSidebar(session: session, openPatch: openPatch, editFixture: editFixture)
        case .stage: StageView(session: session, interactive: true, editFixture: editFixture)
        case .inspector: StudioInspector(session: session)
        case .timeline: TimelineView(session: session, editFixture: editFixture)
        }
    }
}

private struct EditorDivider: View {
    let axis: EditorSplitAxis
    let dragging: Bool
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(studioBackground)
            .overlay {
                Rectangle()
                    .fill(hovering || dragging ? studioAccent : .white.opacity(0.24))
                    .frame(width: axis == .horizontal ? 1 : nil, height: axis == .vertical ? 1 : nil)
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .help("Drag to resize panels")
    }
}
