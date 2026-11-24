import Foundation
import Testing

@MainActor
struct ConnectedTests {
    @Test func phoneNeedsApprovalAndRevocationBlocksFurtherCommands() async throws {
        let binding = PhoneNetworkBinding(interfaceName: "lo0", address: "127.0.0.1", netmask: "255.0.0.0")
        let session = ShowSession(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        session.newShow()
        session.addFixture(.plug)
        let fixture = try #require(session.project.lighting.fixtures.first)
        session.setCue(LightingCue(name: "GO test", time: 0, manualOnly: true,
                                   entries: [FixtureLookEntry(id: fixture.id, state: .plug(true))]))
        let port: UInt16 = 19444
        let remote = StudioPhoneRemote(session: session, port: port, currentBinding: { $0 == binding.address ? binding : nil })
        defer { remote.stop(); session.finish() }
        remote.start(on: binding)
        let origin = "http://127.0.0.1:\(port)"
        let end = ProcessInfo.processInfo.systemUptime + 3
        while remote.invitation == nil && ProcessInfo.processInfo.systemUptime < end { try await Task.sleep(for: .milliseconds(15)) }
        let invite = try #require(remote.invitation?.fragment)
        let unauthenticated = try await post("/state", [:], origin: origin)
        #expect(unauthenticated.status == 403)
        let paired = try await post("/pair", ["code": invite], origin: origin)
        let token = try #require(paired.payload["token"] as? String)
        let replay = try await post("/pair", ["code": invite], origin: origin)
        #expect(replay.status == 403)
        let pending = try await post("/command", ["sequence": 1, "action": "go"], origin: origin, token: token)
        #expect(pending.payload["pending"] as? Bool == true && session.effectiveState(fixture) == .plug(false))
        remote.approve()
        let response = try await post("/command", ["sequence": 1, "action": "go"], origin: origin, token: token)
        #expect(response.status == 200 && session.effectiveState(fixture) == .plug(true))
        let badOrigin = try await post("/command", ["sequence": 2, "action": "blackout"], origin: origin, token: token, validOrigin: false)
        #expect(badOrigin.status == 400 && !session.simulation.blackout)
        let reusedSequence = try await post("/command", ["sequence": 1, "action": "blackout"], origin: origin, token: token)
        #expect(reusedSequence.status == 409)
        remote.invitePhone()
        let revoked = try await post("/state", [:], origin: origin, token: token)
        #expect(revoked.status == 403 && !remote.isPaired)
    }

    @Test func repositoryUpdatesIgnorePreviewsAndUseTheOfficialReleaseLink() throws {
        func payload(_ tag: String, preview: Bool = false) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["tag_name": tag, "draft": false, "prerelease": preview,
                "assets": [["name": "LightShowStudio-v0.3-macOS-universal.zip", "state": "uploaded", "size": 100]]])
        }
        let update = try #require(try GitHubReleaseUpdates.update(from: payload("v0.3"), installed: "0.2"))
        #expect(update.page.absoluteString == "https://github.com/Chosencode25/light-show-studio/releases/tag/v0.3")
        #expect(try GitHubReleaseUpdates.update(from: payload("v0.3-preview", preview: true), installed: "0.2") == nil)
        #expect(try GitHubReleaseUpdates.update(from: payload("v0.1"), installed: "0.2") == nil)
    }

    @Test func manualCheckExplainsWhenThePublicRepositoryHasNoRelease() async throws {
        let name = "updates." + UUID().uuidString
        let prefs = try #require(UserDefaults(suiteName: name))
        defer { prefs.removePersistentDomain(forName: name) }
        let checker = ReleaseUpdateChecker(defaults: prefs) { throw GitHubReleaseUpdates.ReleaseError.notPublished }
        await checker.check()
        #expect(checker.notice == nil)
        await checker.check(manual: true)
        #expect(checker.notice == .notPublished)
    }

    private func post(_ path: String, _ data: [String: Any], origin: String, token: String = "",
                      validOrigin: Bool = true) async throws -> (status: Int, payload: [String: Any]) {
        var request = URLRequest(url: URL(string: origin + path)!, timeoutInterval: 3)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(validOrigin ? origin : "http://invalid.example", forHTTPHeaderField: "Origin")
        if !token.isEmpty { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: data)
        let (bytes, response) = try await URLSession.shared.data(for: request)
        return (try #require((response as? HTTPURLResponse)?.statusCode),
                try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any]))
    }
}
