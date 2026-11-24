import AppKit
import Foundation
import Network
import Observation
import Security

@MainActor @Observable
final class StudioPhoneRemote {
    private let session: ShowSession
    private let listener = PhoneHTTPListener()
    private let port: UInt16
    private let currentBinding: (String) -> PhoneNetworkBinding?
    private var binding: PhoneNetworkBinding?
    private var monitor: NWPathMonitor?
    private var invite: (code: String, expiry: Date)?
    private var pending: (token: String, expiry: Date)?
    private var active: (token: String, expiry: Date, show: UUID, sequence: Int)?
    private var windowStart = Date.distantPast
    private var requests = 0
    private var expiryTask: Task<Void, Never>?
    private var origin = ""
    private(set) var isRunning = false
    private(set) var invitation: URL?
    private(set) var awaitingApproval = false
    private(set) var isPaired = false
    private(set) var status = "Off"

    init(session: ShowSession, port: UInt16 = 9444, currentBinding: @escaping (String) -> PhoneNetworkBinding? = PhoneNetworkBinding.current) {
        self.session = session
        self.port = port
        self.currentBinding = currentBinding
        listener.handle = { [weak self] request in
            self?.handle(request) ?? .json(["error": "Remote is off."], status: "503 Service Unavailable")
        }
        listener.acceptsPeer = { [weak self] in self?.binding?.contains($0) == true }
        listener.stateChanged = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.invitePhone()
            case .failed(let error):
                self.stop()
                self.status = error.localizedDescription
            default: break
            }
        }
    }

    func start(on selected: PhoneNetworkBinding) {
        guard !session.isHome, currentBinding(selected.address) == selected else {
            status = "Open a show and select an available local network."
            return
        }
        stop()
        origin = "http://\(selected.address):\(port)"
        do { try listener.startLocal(address: selected.address, port: port) }
        catch { status = error.localizedDescription; return }
        binding = selected
        isRunning = true
        status = "Starting…"
        let watcher = NWPathMonitor()
        monitor = watcher
        watcher.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkBinding() }
        }
        watcher.start(queue: .main)
    }

    func stop() {
        listener.stop()
        monitor?.cancel()
        monitor = nil
        expiryTask?.cancel()
        expiryTask = nil
        binding = nil
        origin = ""
        invite = nil; pending = nil; active = nil
        isRunning = false
        invitation = nil; awaitingApproval = false; isPaired = false
        status = "Off"
    }

    func invitePhone() {
        guard isRunning, let code = randomToken() else { status = "Couldn’t make a pairing code."; return }
        active = nil; pending = nil
        awaitingApproval = false; isPaired = false
        invite = (code, .now.addingTimeInterval(120))
        invitation = URL(string: "\(origin)/#\(code)")
        status = "Scan the code on your phone."
        watchExpiry(after: 120)
    }

    func approve() {
        guard let pending, pending.expiry > .now, !session.isHome else { invitePhone(); return }
        active = (pending.token, .now.addingTimeInterval(8 * 3600), session.project.id, 0)
        self.pending = nil
        awaitingApproval = false
        isPaired = true
        status = "Phone connected."
        watchExpiry(after: 8 * 3600)
    }

    private func watchExpiry(after seconds: Int) {
        expiryTask?.cancel()
        expiryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, self.isRunning else { return }
            self.invite = nil; self.pending = nil; self.active = nil
            self.invitation = nil; self.awaitingApproval = false; self.isPaired = false
            self.status = "Pairing expired. Start a new invitation."
        }
    }

    private func checkBinding() {
        guard let binding else { return }
        if currentBinding(binding.address) != binding {
            stop()
            status = "The local network changed. Restart Phone Remote to pair again."
        }
    }

    private func randomToken() -> String? {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        return bytes.map { String(format: "%02x", Int($0)) }.joined()
    }

    private func handle(_ request: PhoneRequest) -> PhoneResponse {
        checkBinding()
        guard isRunning, let binding, request.headers["host"] == "\(binding.address):\(port)" else {
            return .json(["error": "Remote address unavailable."], status: "403 Forbidden")
        }
        let now = Date.now
        if now.timeIntervalSince(windowStart) >= 1 { windowStart = now; requests = 0 }
        requests += 1
        guard requests <= 24 else { return .json(["error": "Too many requests."], status: "429 Too Many Requests") }
        if request.method == "GET" {
            switch request.path {
            case "/": return text(StudioPhonePage.html, type: "text/html; charset=utf-8")
            case "/remote.js": return text(StudioPhonePage.script, type: "text/javascript; charset=utf-8")
            case "/remote.css": return text(StudioPhonePage.css, type: "text/css; charset=utf-8")
            default: return .json(["error": "Unknown page."], status: "404 Not Found")
            }
        }
        guard request.headers["origin"] == origin, request.headers["content-type"] == "application/json",
              let payload = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] else {
            return .json(["error": "Invalid request."], status: "400 Bad Request")
        }
        if request.path == "/pair" {
            guard let invite, invite.expiry > now, payload["code"] as? String == invite.code, let token = randomToken() else {
                return .json(["error": "Invitation expired. Scan a new code."], status: "403 Forbidden")
            }
            self.invite = nil
            invitation = nil
            pending = (token, now.addingTimeInterval(120))
            awaitingApproval = true
            status = "Approve the phone on this Mac."
            watchExpiry(after: 120)
            return .json(["token": token])
        }

        let authorization = request.headers["authorization"]
        if let pending, pending.expiry > now, authorization == "Bearer " + pending.token {
            return .json(["pending": true])
        }
        guard let active, active.expiry > now, authorization == "Bearer " + active.token,
              active.show == session.project.id, !session.isHome else {
            return .json(["error": "Pair this phone again."], status: "403 Forbidden")
        }
        if request.path == "/state" { return snapshot() }
        guard request.path == "/command", let number = payload["sequence"] as? Int,
              number > active.sequence, number - active.sequence <= 100,
              let action = payload["action"] as? String,
              !session.loadingSong, !session.reviewingTake,
              NSApp?.modalWindow == nil, NSApp?.keyWindow?.attachedSheet == nil else {
            return .json(["error": "Operator controls are temporarily unavailable."], status: "409 Conflict")
        }
        self.active?.sequence = number
        switch action {
        case "play":
            guard session.canPlay, !session.recording else { return unavailable() }
            session.play()
        case "pause":
            guard !session.recording else { return unavailable() }
            session.pause()
        case "stop":
            guard !session.recording else { return unavailable() }
            session.stop()
        case "go":
            guard (session.workspace == .edit || session.ready), !session.cues.isEmpty else { return unavailable() }
            if let raw = payload["cue"] as? String {
                guard let id = UUID(uuidString: raw), session.cues.contains(where: { $0.id == id }) else { return unavailable() }
                session.nextCueID = id
            }
            session.go()
        case "blackout": session.setBlackout(true)
        case "restore": session.setBlackout(false)
        default: return unavailable()
        }
        return snapshot()
    }

    private func unavailable() -> PhoneResponse {
        .json(["error": "That control is unavailable right now."], status: "409 Conflict")
    }

    private func snapshot() -> PhoneResponse {
        .json(["name": session.project.name, "playing": session.playing, "position": session.position,
               "ready": session.canPlay, "blackout": session.simulation.blackout, "recording": session.recording,
               "sequence": active?.sequence ?? 0,
               "next": session.nextCueID?.uuidString ?? "",
               "cues": session.cues.prefix(100).map { ["id": $0.id.uuidString, "name": $0.name] },
               "fixtures": session.project.lighting.fixtures.prefix(100).map {
                   ["name": $0.name, "state": session.effectiveState($0).label]
               }])
    }

    private func text(_ body: String, type: String) -> PhoneResponse {
        PhoneResponse(status: "200 OK", type: type, body: Data(body.utf8))
    }
}
