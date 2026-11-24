import AVFoundation
import Darwin
import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let lightShow = UTType(exportedAs: "local.keith.lightshowstudio.show", conformingTo: .package)
    static let lightSetup = UTType(exportedAs: "local.keith.lightshowstudio.setup", conformingTo: .json)
}

enum ShowError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self { case .invalid(let message): message }
    }
}

struct ShowSong: Codable, Equatable, Sendable {
    static let maximumBytes = 96 * 1024 * 1024
    static let extensions = ["wav", "mp3", "m4a", "aiff", "aif", "caf", "flac"]
    var name: String
    var ext: String
    var duration: Double
    var bytes: Int
    var waveform: [Float]?

    var isValid: Bool {
        !name.isEmpty && name.count <= 120 && Self.extensions.contains(ext) &&
            (0.1...3600).contains(duration) && (1...Self.maximumBytes).contains(bytes) &&
            (waveform.map { (1...2048).contains($0.count) && $0.allSatisfy { (0...1).contains($0) } } ?? true)
    }

    var fileName: String { "soundtrack." + ext }
}

struct PreparedSoundtrack: Sendable {
    let song: ShowSong
    let data: Data
    let waveform: [Float]

    static func read(_ url: URL, expected: ShowSong? = nil) throws -> Self {
        let ext = url.pathExtension.lowercased()
        guard ShowSong.extensions.contains(ext) else { throw ShowError.invalid("Choose WAV, MP3, M4A, AIFF, CAF, or FLAC audio.") }
        let data = try ShowFiles.readRegular(url, maximum: ShowSong.maximumBytes)
        let audio = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let duration = Double(audio.length) / audio.processingFormat.sampleRate
        var song = expected ?? ShowSong(name: String(url.deletingPathExtension().lastPathComponent.prefix(120)),
                                        ext: ext, duration: duration, bytes: data.count)
        guard song.isValid, song.ext == ext, data.count == song.bytes, abs(song.duration - duration) < 0.05 else {
            throw ShowError.invalid("The soundtrack is missing, changed, or longer than one hour.")
        }
        let waveform = try song.waveform ?? measure(audio)
        if expected == nil { song.waveform = waveform }
        return Self(song: song, data: data, waveform: waveform)
    }

    private static func measure(_ audio: AVAudioFile) throws -> [Float] {
        let length = audio.length
        guard length > 0, (1...8).contains(audio.processingFormat.channelCount),
              let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 8192) else {
            throw ShowError.invalid("The soundtrack’s audio format is unsupported.")
        }
        let count = Int(min(length, 2048))
        var peaks = [Float](repeating: 0, count: count)
        var start: Int64 = 0
        let step = max(1, length / 262_144)
        while start < length {
            try Task.checkCancellation()
            try audio.read(into: buffer)
            let frames = Int64(buffer.frameLength)
            guard frames > 0, let samples = buffer.floatChannelData else { break }
            var offset = (step - start % step) % step
            while offset < frames {
                let bucket = min(count - 1, Int((start + offset) * Int64(count) / length))
                for channel in 0..<Int(buffer.format.channelCount) {
                    let sample = abs(samples[channel][Int(offset)])
                    if sample.isFinite { peaks[bucket] = max(peaks[bucket], min(1, sample)) }
                }
                offset += step
            }
            start += frames
        }
        return peaks
    }
}

struct LightShow: Codable, Equatable, Sendable {
    static let currentVersion = 3
    var version = Self.currentVersion
    var id = UUID()
    var name = "Untitled Light Show"
    var lighting = ProjectLighting()
    var song: ShowSong?
    var chases: [ChoreographyClip] = []
    var stagePhoto: StagePhoto?
    var timeMarkers: [TimelineMarker]?
    var markers: [TimelineMarker] { timeMarkers ?? [] }

    var duration: Double {
        let programmingEnd = max(markers.map(\.time).max() ?? 0, lighting.cues.map(\.end).max() ?? 0,
                                 lighting.positionKeys.map(\.time).max() ?? 0, chases.map(\.end).max() ?? 0)
        if let song { return song.duration }
        return min(3600, max(15, programmingEnd + 0.5))
    }

    func validate() throws {
        guard (1...Self.currentVersion).contains(version), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 80, song?.isValid != false else { throw ShowError.invalid("This show has invalid settings or an unsupported format.") }
        guard stagePhoto?.isValid != false, markers.count <= 2048,
              Set(markers.map(\.id)).count == markers.count, markers.allSatisfy(\.isValid) else {
            throw ShowError.invalid("Check the stage photo and timeline markers.")
        }
        if let issue = lighting.validationIssue() { throw ShowError.invalid(issue) }
        if let song, lighting.cues.contains(where: { !$0.isManual && $0.end > song.duration + 0.000001 }) ||
            lighting.positionKeys.contains(where: { $0.time > song.duration }) ||
            chases.contains(where: { $0.end > song.duration + 0.000001 }) || markers.contains(where: { $0.time > song.duration }) {
            throw ShowError.invalid("Timed cues, motion keys, and chases must fit inside the soundtrack.")
        }
        let fixtureIDs = Set(lighting.fixtures.map(\.id))
        guard ChoreographyClip.validSequence(chases),
              chases.allSatisfy({ $0.targets.allSatisfy { fixtureIDs.contains($0.id) } }) else {
            throw ShowError.invalid("Check chase targets and timing. Chases on the same fixture can’t overlap.")
        }
    }
}

struct FixtureSetup: Codable, Equatable, Sendable {
    var version = 2
    var name: String
    var controllers: [LightingController]
    var fixtures: [PatchedFixture]
    var stagePhoto: StagePhoto?

    init(show: LightShow, name: String) {
        self.name = name
        controllers = show.lighting.controllers
        fixtures = show.lighting.fixtures
        stagePhoto = show.stagePhoto
    }

    func newShow() throws -> LightShow {
        guard (1...2).contains(version) else { throw ShowError.invalid("This fixture setup uses an unsupported format.") }
        var show = LightShow()
        show.name = name
        show.lighting.controllers = controllers
        show.lighting.fixtures = fixtures
        show.stagePhoto = stagePhoto
        try stagePhoto?.validateImage()
        try show.validate()
        return show
    }
}

enum ShowFiles {
    static func readRegular(_ url: URL, maximum: Int) throws -> Data {
        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isRegularFile == true, info.isSymbolicLink == false, let size = info.fileSize,
              (1...maximum).contains(size) else { throw ShowError.invalid("A required file is missing or exceeds its size limit.") }
        let data = try Data(contentsOf: url)
        guard data.count == size else { throw ShowError.invalid("The file changed while it was being read.") }
        return data
    }

    static func load(_ url: URL) throws -> (LightShow, PreparedSoundtrack?) {
        let info = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard info.isDirectory == true, info.isSymbolicLink == false else { throw ShowError.invalid("Choose a Light Show Studio show package.") }
        let data = try readRegular(url.appendingPathComponent("manifest.json"), maximum: 16 * 1024 * 1024)
        var show = try JSONDecoder().decode(LightShow.self, from: data)
        try show.validate()
        show.version = LightShow.currentVersion
        try show.stagePhoto?.validateImage()
        let song = try show.song.map { try PreparedSoundtrack.read(url.appendingPathComponent($0.fileName), expected: $0) }
        return (show, song)
    }

    static func save(_ show: LightShow, soundtrack: Data?, to url: URL, replacing: Bool) throws {
        try show.validate()
        try show.stagePhoto?.validateImage()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var currentShow = show
        currentShow.version = LightShow.currentVersion
        let manifest = try encoder.encode(currentShow)
        guard manifest.count <= 16 * 1024 * 1024 else { throw ShowError.invalid("This show exceeds its saved size limit.") }
        let directory = url.deletingLastPathComponent()
            .appendingPathComponent(".lightshow-" + UUID().uuidString, isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: directory) }
        try manifest.write(to: directory.appendingPathComponent("manifest.json"))
        if let song = show.song {
            guard let soundtrack, soundtrack.count == song.bytes else { throw ShowError.invalid("The soundtrack needs to be imported again.") }
            try soundtrack.write(to: directory.appendingPathComponent(song.fileName))
        }
        let exists = fm.fileExists(atPath: url.path)
        if exists {
            guard replacing else { throw ShowError.invalid("A show already exists at that location.") }
            let info = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard info.isDirectory == true, info.isSymbolicLink == false else {
                throw ShowError.invalid("Choose a Light Show Studio package to replace.")
            }
            let old = try readRegular(url.appendingPathComponent("manifest.json"), maximum: 16 * 1024 * 1024)
            try JSONDecoder().decode(LightShow.self, from: old).validate()
        }
        let rule = exists ? RENAME_SWAP : RENAME_EXCL
        let result = directory.path.withCString { source in
            url.path.withCString { destination in
                renameatx_np(AT_FDCWD, source, AT_FDCWD, destination, UInt32(rule))
            }
        }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    static func loadSetup(_ url: URL) throws -> FixtureSetup {
        let setup = try JSONDecoder().decode(FixtureSetup.self, from: readRegular(url, maximum: 8 * 1024 * 1024))
        _ = try setup.newShow()
        return setup
    }

    static func saveSetup(_ setup: FixtureSetup, to url: URL) throws {
        _ = try setup.newShow()
        try JSONEncoder().encode(setup).write(to: url, options: .atomic)
    }
}
