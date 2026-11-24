import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

struct StudioPhonePanel: View {
    let remote: StudioPhoneRemote
    @Environment(\.dismiss) private var dismiss
    @State private var networks = PhoneNetworkBinding.available()
    @State private var selected: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Phone Remote").font(.title2.bold())
            Text(remote.status).foregroundStyle(.secondary)
            if remote.isRunning {
                if let invitation = remote.invitation {
                    if let qr = code(invitation) {
                        Image(nsImage: qr).interpolation(.none).resizable()
                            .frame(width: 170, height: 170)
                            .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityLabel("Phone pairing QR code")
                    }
                    Button("Copy Pairing Link", systemImage: "document.on.document") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(invitation.absoluteString, forType: .string)
                    }
                }
                if remote.awaitingApproval {
                    HStack {
                        Button("Reject") { remote.invitePhone() }
                        Button("Approve Phone") { remote.approve() }.buttonStyle(.borderedProminent)
                    }
                } else if remote.isPaired {
                    Button("Disconnect Phone", role: .destructive) { remote.invitePhone() }
                } else if remote.invitation == nil {
                    Button("New Pairing Code") { remote.invitePhone() }
                }
                Button("Turn Off Remote") { remote.stop() }
            } else {
                if networks.isEmpty { Text("Connect this Mac to the same Wi-Fi or Ethernet network as your phone.").font(.callout) }
                else {
                    Picker("Local network", selection: $selected) {
                        ForEach(networks) { network in Text(network.title).tag(Optional(network.id)) }
                    }
                }
                HStack {
                    Button("Refresh Networks") { refreshNetworks() }
                    Button("Start Phone Remote") {
                        if let network = networks.first(where: { $0.id == selected }) { remote.start(on: network) }
                    }.buttonStyle(.borderedProminent).disabled(selected == nil)
                }
            }
            Text("Use a trusted local network. The phone connection uses local HTTP.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 406)
        .onAppear { if !remote.isRunning { refreshNetworks() } }
    }

    private func refreshNetworks() {
        networks = PhoneNetworkBinding.available()
        if !networks.contains(where: { $0.id == selected }) { selected = networks.first?.id }
    }

    private func code(_ url: URL) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let image = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 6, y: 6)),
              let bitmap = CIContext().createCGImage(image, from: image.extent) else { return nil }
        return NSImage(cgImage: bitmap, size: image.extent.size)
    }
}

struct StudioUpdateNotice: View {
    let checker: ReleaseUpdateChecker
    let installed: String

    var body: some View {
        if let notice = checker.notice {
            VStack(alignment: .leading, spacing: 9) {
                switch notice {
                case .available(let update):
                    Label("Update Available", systemImage: "arrow.down.circle").font(.headline)
                    Text("Installed \(installed) · Available \(update.tag.dropFirst())").foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        Button("Later") { checker.dismiss() }
                        Button("Download Update") {
                            if NSWorkspace.shared.open(update.page) { checker.dismiss() }
                        }.buttonStyle(.borderedProminent)
                    }
                default:
                    HStack {
                        Text(message(notice)).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Dismiss", systemImage: "xmark") { checker.dismiss() }.labelStyle(.iconOnly).buttonStyle(.borderless)
                    }
                }
            }.padding(14).frame(width: 330)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.3)).allowsHitTesting(false) }
                .shadow(radius: 6, y: 2).padding(12)
        }
    }

    private func message(_ notice: ReleaseUpdateChecker.Notice) -> String {
        switch notice {
        case .upToDate: "Light Show Studio is up to date."
        case .notPublished: "No full Light Show Studio release has been published yet."
        default: "Couldn’t check for updates. Try again later."
        }
    }
}
