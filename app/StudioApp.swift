import AppKit
import SwiftUI

@main
struct LightShowStudioApp: App {
    @NSApplicationDelegateAdaptor(StudioDelegate.self) private var delegate

    var body: some Scene {
        Window("Light Show Studio", id: "studio") {
            StudioWindow(session: delegate.session, remote: delegate.remote, updates: delegate.updates, version: delegate.version)
                .frame(minWidth: 1050, minHeight: 690)
        }
        .defaultSize(width: 1220, height: 770)
        .commands { StudioCommands(session: delegate.session, checkUpdates: { delegate.checkUpdates(manual: true) }) }
    }
}

@MainActor
final class StudioDelegate: NSObject, NSApplicationDelegate {
    let session = ShowSession()
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

struct StudioCommands: Commands {
    let session: ShowSession
    let checkUpdates: () -> Void
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…", action: checkUpdates)
        }
        CommandGroup(replacing: .newItem) {
            Button("New Light Show") { session.newShow() }.keyboardShortcut("n")
            Button("Open Light Show…") { session.chooseShow() }.keyboardShortcut("o")
            Button("New Show from Setup…") { session.chooseSetup() }
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save Light Show") { session.save() }.keyboardShortcut("s").disabled(session.isHome)
            Button("Save Light Show As…") { session.save(asCopy: true) }.keyboardShortcut("s", modifiers: [.command, .shift]).disabled(session.isHome)
            Button("Save Fixture Setup…") { session.saveSetup() }.disabled(session.isHome)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { session.undoEdit() }.keyboardShortcut("z").disabled(!session.canUndo)
            Button("Redo") { session.redoEdit() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!session.canRedo)
        }
    }
}
