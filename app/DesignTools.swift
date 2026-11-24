import Foundation
import ImageIO
import UniformTypeIdentifiers

struct StagePhoto: Codable, Equatable, Sendable {
    let data: Data
    let width: Int
    let height: Int
    var opacity = 0.65
    var locked = false

    var isValid: Bool {
        (1...2048).contains(width) && (1...2048).contains(height) &&
            (1...4_194_304).contains(data.count) && (0...1).contains(opacity)
    }

    static func read(_ url: URL) throws -> Self {
        let data = try ShowFiles.readRegular(url, maximum: 32 * 1024 * 1024)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048
              ] as CFDictionary) else { throw ShowError.invalid("Choose a readable stage or house photo.") }
        let output = NSMutableData()
        guard let target = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ShowError.invalid("The stage photo couldn’t be prepared.")
        }
        CGImageDestinationAddImage(target, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(target) else { throw ShowError.invalid("The stage photo couldn’t be saved.") }
        let photo = Self(data: output as Data, width: image.width, height: image.height)
        try photo.validateImage()
        return photo
    }

    func validateImage() throws {
        guard isValid, let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.jpeg.identifier,
              let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              info[kCGImagePropertyPixelWidth] as? Int == width, info[kCGImagePropertyPixelHeight] as? Int == height else {
            throw ShowError.invalid("The stage photo is invalid or damaged.")
        }
    }
}

struct TimelineMarker: Codable, Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case beat = "Beat", section = "Section"
        var id: Self { self }
    }

    var id = UUID()
    var kind: Kind
    var time: Double
    var name = ""

    var label: String { name.isEmpty ? kind.rawValue : name }
    var isValid: Bool { (0...3600).contains(time) && name.count <= 80 }
}

enum CueTiming {
    static let defaultClipDuration = 5.0
    static let minimumClipDuration = 0.05

    static func boundedOffset(_ offset: Double, cues: [LightingCue], end: Double) -> Double {
        guard let start = cues.map(\.time).min(), let last = cues.map(\.end).max() else { return 0 }
        return min(max(0, end - last), max(-start, offset))
    }

    static func nearestMarker(to time: Double, in markers: [TimelineMarker], tolerance: Double) -> Double {
        guard let marker = markers.min(by: { abs($0.time - time) < abs($1.time - time) }),
              abs(marker.time - time) <= tolerance else { return time }
        return marker.time
    }

    static func boundedOffset(_ offset: Double, times: [Double], end: Double) -> Double {
        guard offset.isFinite, let first = times.min(), let last = times.max() else { return 0 }
        return min(max(0, end - last), max(-first, offset))
    }
}
