import AppKit
import SwiftUI

@main
struct LightShowStudioApp: App {
    @NSApplicationDelegateAdaptor(StudioDelegate.self) private var delegate

    var body: some Scene {
        Window("Light Show Studio", id: "studio") {
            StudioWindow(session: delegate.session, layouts: delegate.layouts, remote: delegate.remote, updates: delegate.updates, version: delegate.version)
                .frame(minWidth: 1050, minHeight: 690)
        }
        .defaultSize(width: 1220, height: 770)
        .commands { StudioCommands(session: delegate.session, layouts: delegate.layouts, checkUpdates: { delegate.checkUpdates(manual: true) }) }
        Window("Keyboard Shortcuts", id: "studio-shortcuts") {
            StudioShortcutGuide()
                .frame(minWidth: 440, minHeight: 375)
        }
        .defaultSize(width: 500, height: 550)
    }
}

@MainActor
final class StudioDelegate: NSObject, NSApplicationDelegate {
    let session = ShowSession()
    let layouts = EditorLayoutSettings()
    lazy var remote = StudioPhoneRemote(session: session)
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    lazy var updates = ReleaseUpdateChecker { [version] in try await GitHubReleaseUpdates.check(installed: version) }

    func applicationDidFinishLaunching(_ notification: Notification) { checkUpdates(manual: false) }
    func applicationDidBecomeActive(_ notification: Notification) { checkUpdates(manual: false) }
    func checkUpdates(manual: Bool) { Task { await updates.check(manual: manual) } }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard let first = filenames.first else { sender.reply(toOpenOrPrint: .cancel); return }
        session.open(URL(fileURLWithPath: first))
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        session.confirmLeaving() ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { remote.stop(); session.finish() }
}
