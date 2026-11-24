import Foundation

enum ChoreographyPattern: String, Codable, CaseIterable, Identifiable, Sendable {
    case forward = "Forward", reverse = "Reverse", bounce = "Bounce", wave = "Wave"
    var id: Self { self }
}

struct ChoreographyTarget: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var position: FixturePreviewPoint
}

/// A reusable recipe. Target IDs, positions and start times belong to each placement.
struct LightingEffectPreset: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var pattern: ChoreographyPattern
    var colors: [SIMD4<Float>]
    var interval: Double
    var repeats: Int
    var angle: Double

    init(clip: ChoreographyClip) {
        name = clip.name.trimmingCharacters(in: .whitespacesAndNewlines)
        pattern = clip.pattern
        colors = clip.colors
        interval = clip.interval
        repeats = clip.repeats
        angle = clip.angle
    }

    var isValid: Bool {
        !name.isEmpty && name.count <= 80 &&
            (1...16).contains(colors.count) &&
            colors.allSatisfy { color in (0..<4).allSatisfy { (0...1).contains(color[$0]) } } &&
            (0.05...60).contains(interval) && (1...64).contains(repeats) && (-360...360).contains(angle)
    }

    func apply(to clip: inout ChoreographyClip) {
        clip.name = name
        clip.pattern = pattern
        clip.colors = colors
        clip.interval = interval
        clip.repeats = repeats
        clip.angle = angle
    }
}

struct ChoreographyClip: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name = "Color Chase"
    var pattern = ChoreographyPattern.forward
    var targets: [ChoreographyTarget] = []
    var colors: [SIMD4<Float>] = [SIMD4(1, 0, 0, 1), SIMD4(0, 0.5, 1, 1)]
    var start = 0.0
    var interval = 0.5
    var repeats = 1
    var angle = 0.0

    private var steps: Int { pattern == .bounce ? max(1, targets.count * 2 - 2) : targets.count }
    var duration: Double { interval * Double(steps * repeats) }
    var end: Double { start + duration }
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 80 &&
        (1...128).contains(targets.count) && targets.allSatisfy { $0.position.isValid } &&
        Set(targets.map(\.id)).count == targets.count && (1...16).contains(colors.count) &&
        colors.allSatisfy { c in (0..<4).allSatisfy { (0...1).contains(c[$0]) } } &&
        (0...3600).contains(start) && (0.05...60).contains(interval) && (1...64).contains(repeats) &&
        (-360...360).contains(angle) && end <= 3600
    }

    func sample(at time: Double, target id: UUID) -> (color: SIMD4<Float>, active: Bool, stepStart: Double)? {
        guard time >= start, time < end, let index = targets.firstIndex(where: { $0.id == id }) else { return nil }
        let step = min(steps * repeats - 1, Int((time - start) / interval))
        let phase = step % steps
        let active: Bool
        switch pattern {
        case .forward: active = index == phase
        case .reverse: active = index == targets.count - phase - 1
        case .bounce: active = index == min(phase, steps - phase)
        case .wave:
            let radians = angle * .pi / 180
            func coordinate(_ target: ChoreographyTarget) -> Double {
                target.position.x * cos(radians) + target.position.y * sin(radians)
            }
            let values = targets.map(coordinate)
            let minimum = values.min() ?? 0
            let span = (values.max() ?? minimum) - minimum
            let slot = span > 0.00001 ? Int(((values[index] - minimum) / span * Double(steps - 1)).rounded()) : 0
            active = phase == slot
        }
        return (colors[step % colors.count], active, start + Double(step) * interval)
    }

    static func validSequence(_ clips: [Self]) -> Bool {
        guard clips.count <= 128, Set(clips.map(\.id)).count == clips.count, clips.allSatisfy(\.isValid) else { return false }
        for (index, clip) in clips.enumerated() {
            let ids = Set(clip.targets.map(\.id))
            if clips[..<index].contains(where: { other in
                clip.start < other.end && other.start < clip.end &&
                    other.targets.contains { ids.contains($0.id) }
            }) { return false }
        }
        return true
    }
}

