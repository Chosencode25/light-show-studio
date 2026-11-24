import Foundation
import Observation

enum EditorPanel: String, CaseIterable, Codable, Identifiable {
    case fixtures = "Fixtures"
    case stage = "Stage Preview"
    case inspector = "Inspector"
    case timeline = "Timeline"

    var id: Self { self }

    var minimumSize: CGSize {
        switch self {
        case .fixtures: CGSize(width: 175, height: 120)
        case .stage: CGSize(width: 250, height: 160)
        case .inspector: CGSize(width: 300, height: 140)
        case .timeline: CGSize(width: 275, height: 190)
        }
    }
}

enum EditorDockSide: String, CaseIterable, Identifiable {
    case left = "Left", right = "Right", above = "Above", below = "Below"
    var id: Self { self }
    var axis: EditorSplitAxis { self == .left || self == .right ? .horizontal : .vertical }
    var insertsFirst: Bool { self == .left || self == .above }
}

enum EditorSplitAxis: String, Codable {
    case horizontal, vertical

    func length(_ size: CGSize) -> CGFloat {
        self == .horizontal ? size.width : size.height
    }
}

enum EditorLayoutPreset: String, CaseIterable, Codable, Identifiable {
    case stageDesign = "Stage Design"
    case showTiming = "Show Timing"

    var id: Self { self }

    var defaultLayout: EditorLayoutNode {
        switch self {
        case .stageDesign:
            .split(UUID(), .horizontal, 0.18, .panel(.fixtures),
                   .split(UUID(), .horizontal, 0.66, .panel(.stage), .panel(.inspector)))
        case .showTiming:
            .panel(.timeline)
        }
    }
}

indirect enum EditorLayoutNode: Codable {
    case panel(EditorPanel)
    case split(UUID, EditorSplitAxis, CGFloat, EditorLayoutNode, EditorLayoutNode)

    var panels: [EditorPanel] {
        switch self {
        case .panel(let panel): [panel]
        case .split(_, _, _, let first, let second): first.panels + second.panels
        }
    }

    func replacing(_ panel: EditorPanel, with replacement: Self?) -> Self? {
        switch self {
        case .panel(let current):
            return current == panel ? replacement : self
        case .split(let id, let axis, let fraction, let first, let second):
            let leading = first.replacing(panel, with: replacement)
            let trailing = second.replacing(panel, with: replacement)
            guard let leading, let trailing else { return leading ?? trailing }
            return .split(id, axis, fraction, leading, trailing)
        }
    }

    func resizing(_ divider: UUID, to fraction: CGFloat) -> Self {
        guard case .split(let id, let axis, let current, let first, let second) = self else { return self }
        if id == divider { return .split(id, axis, fraction, first, second) }
        return .split(id, axis, current, first.resizing(divider, to: fraction), second.resizing(divider, to: fraction))
    }
}

@MainActor @Observable
final class EditorLayoutSettings {
    private struct Saved: Codable {
        var preset: EditorLayoutPreset = .stageDesign
        var arrangements: [EditorLayoutPreset: EditorLayoutNode] = [:]
    }

    private static let key = "ProgramEditorLayouts.v1"
    private let defaults: UserDefaults
    private var saved: Saved
    private(set) var layout: EditorLayoutNode

    var preset: EditorLayoutPreset { saved.preset }
    var availablePanels: [EditorPanel] { EditorPanel.allCases.filter { !layout.panels.contains($0) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let restored = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) } ?? Saved()
        saved = restored
        layout = restored.arrangements[restored.preset] ?? restored.preset.defaultLayout
    }

    func select(_ preset: EditorLayoutPreset) {
        guard preset != saved.preset else { return }
        saved.arrangements[saved.preset] = layout
        saved.preset = preset
        layout = saved.arrangements[preset] ?? preset.defaultLayout
        commit()
    }

    func open(_ panel: EditorPanel, beside anchor: EditorPanel, on side: EditorDockSide) {
        guard availablePanels.contains(panel), layout.panels.contains(anchor) else { return }
        let first = EditorLayoutNode.panel(side.insertsFirst ? panel : anchor)
        let second = EditorLayoutNode.panel(side.insertsFirst ? anchor : panel)
        let split = EditorLayoutNode.split(UUID(), side.axis, 0.5, first, second)
        guard let updated = layout.replacing(anchor, with: split) else { return }
        layout = updated
        commit()
    }

    func close(_ panel: EditorPanel) {
        guard layout.panels.count > 1, let updated = layout.replacing(panel, with: nil) else { return }
        layout = updated
        commit()
    }

    func resize(_ divider: UUID, to fraction: CGFloat) {
        layout = layout.resizing(divider, to: fraction)
        commit()
    }

    func reset() {
        layout = preset.defaultLayout
        commit()
    }

    private func commit() {
        saved.arrangements[saved.preset] = layout
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: Self.key) }
    }
}

struct EditorLayoutGeometry {
    struct Divider: Identifiable {
        let id: UUID
        let axis: EditorSplitAxis
        let frame: CGRect
        let available: CGFloat
        let leading: CGFloat
        let limits: ClosedRange<CGFloat>

        func fraction(after translation: CGFloat) -> CGFloat {
            let position = min(max(leading + translation, limits.lowerBound), limits.upperBound)
            return available > 0 ? position / available : 0.5
        }
    }

    fileprivate static let dividerWidth: CGFloat = 7
    private(set) var panels: [EditorPanel: CGRect] = [:]
    private(set) var dividers: [Divider] = []

    init(layout: EditorLayoutNode, size: CGSize) {
        place(layout, in: CGRect(origin: .zero, size: size))
    }

    private mutating func place(_ node: EditorLayoutNode, in bounds: CGRect) {
        switch node {
        case .panel(let panel):
            panels[panel] = bounds
        case .split(let id, let axis, let fraction, let first, let second):
            let thickness = min(axis.length(bounds.size), Self.dividerWidth)
            let available = axis.length(bounds.size) - thickness
            let firstMinimum = axis.length(first.minimumSize)
            let secondMinimum = axis.length(second.minimumSize)
            let compression = min(1, available / (firstMinimum + secondMinimum))
            let lower = firstMinimum * compression
            let upper = max(lower, available - secondMinimum * compression)
            let leading = min(max(available * fraction, lower), upper)

            var firstFrame = bounds
            var secondFrame = bounds
            var dividerFrame = bounds
            if axis == .horizontal {
                firstFrame.size.width = leading
                dividerFrame.origin.x += leading
                dividerFrame.size.width = thickness
                secondFrame.origin.x += leading + thickness
                secondFrame.size.width = available - leading
            } else {
                firstFrame.size.height = leading
                dividerFrame.origin.y += leading
                dividerFrame.size.height = thickness
                secondFrame.origin.y += leading + thickness
                secondFrame.size.height = available - leading
            }
            dividers.append(Divider(id: id, axis: axis, frame: dividerFrame, available: available,
                                    leading: leading, limits: lower...upper))
            place(first, in: firstFrame)
            place(second, in: secondFrame)
        }
    }
}

private extension EditorLayoutNode {
    var minimumSize: CGSize {
        switch self {
        case .panel(let panel): return panel.minimumSize
        case .split(_, let axis, _, let first, let second):
            let a = first.minimumSize
            let b = second.minimumSize
            switch axis {
            case .horizontal: return CGSize(width: a.width + b.width + EditorLayoutGeometry.dividerWidth, height: max(a.height, b.height))
            case .vertical: return CGSize(width: max(a.width, b.width), height: a.height + b.height + EditorLayoutGeometry.dividerWidth)
            }
        }
    }
}
