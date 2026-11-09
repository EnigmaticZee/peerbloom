import SwiftUI

struct SidebarView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let selection = Binding<SidebarSelection?>(
            get: { store.sidebar },
            set: { if let value = $0 { store.sidebar = value } })
        List(selection: selection) {
            Section("Library") {
                ForEach(StatusFilter.allCases) { filter in
                    Label {
                        HStack {
                            Text(filter.title)
                            Spacer()
                            Text("\(store.count(filter))").foregroundStyle(.secondary).monospacedDigit()
                        }
                    } icon: {
                        Image(systemName: filter.symbol).foregroundStyle(iconColor(filter))
                    }
                    .tag(SidebarSelection.status(filter))
                }
            }
            Section("Tags") {
                ForEach(store.tags) { tag in
                    Label {
                        HStack {
                            Text(tag.name)
                            Spacer()
                            Text("\(store.count(tag: tag))").foregroundStyle(.secondary).monospacedDigit()
                        }
                    } icon: {
                        Circle().fill(Theme.color(for: tag.color)).frame(width: 9, height: 9)
                    }
                    .tag(SidebarSelection.tag(tag.id))
                }
            }
        }
        .listStyle(.sidebar)
        .themedBackground(Theme.sidebar)
        .safeAreaInset(edge: .bottom) {
            VPNCard(status: store.vpnStatus, killSwitch: store.preferences.killSwitch,
                    detectedVPN: store.detectedVPN, vpnAppName: store.vpnApp?.name,
                    proxyHost: store.preferences.proxyCoversPeers ? store.preferences.proxyHost : nil,
                    privacyMode: store.preferences.privacyMode,
                    bindToVPN: { store.bindToAnyVPN() }, openVPNApp: { store.openVPNApp() }) {
                openSettings()
            }
            .padding(10)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
    }

    private func iconColor(_ f: StatusFilter) -> Color {
        switch f {
        case .downloading: Theme.download
        case .seeding: Theme.upload
        default: .secondary
        }
    }
}

/// Shows whether Peerbloom is bound to the user's own VPN connection. Peerbloom doesn't provide a VPN;
/// it only lets you lock traffic to one you already use.
struct VPNCard: View {
    let status: VPNStatus
    let killSwitch: Bool
    /// A VPN tunnel that is connected but not used for binding yet.
    var detectedVPN: String?
    /// The user's VPN app, offered when the VPN is off. Nil for people without one.
    var vpnAppName: String?
    /// The SOCKS5 proxy carrying peer traffic, if any.
    var proxyHost: String?
    var privacyMode = false
    var bindToVPN: () -> Void = {}
    var openVPNApp: () -> Void = {}
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch status {
            case .protected(let iface):
                Label("Protected", systemImage: "checkmark.shield")
                    .font(.headline).foregroundStyle(Theme.protectedText)
                Text("Traffic only goes through **\(iface)**. " + (killSwitch ? "Transfers pause if it drops." : "Traffic stops if it drops."))
                    .font(.caption).foregroundStyle(.secondary)
            case .bound(let iface):
                Label("Not a VPN", systemImage: "network")
                    .font(.headline)
                Text("Bound to **\(iface)**, a regular connection. Peerbloom only uses it, but your IP address isn't hidden.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Change…", action: openSettings)
                    .buttonStyle(.link).font(.caption.weight(.semibold))
            case .down(let iface):
                Label(NetworkInterface.isTunnelName(iface) ? "VPN disconnected" : "\(iface) disconnected",
                      systemImage: "exclamationmark.shield")
                    .font(.headline).foregroundStyle(Theme.uploadText)
                Text(killSwitch ? "\(iface) is gone, so transfers are paused until it's back."
                                : "\(iface) is gone. Traffic is blocked because Peerbloom is bound to it.")
                    .font(.caption).foregroundStyle(.secondary)
                openAppButton
            case .waitingForVPN:
                Label("Waiting for VPN", systemImage: "exclamationmark.shield")
                    .font(.headline).foregroundStyle(Theme.uploadText)
                Text(killSwitch ? "Transfers are paused until a VPN connects." : "Nothing transfers until a VPN connects.")
                    .font(.caption).foregroundStyle(.secondary)
                openAppButton
            case .notBound:
                if let proxyHost {
                    Label("Using a proxy", systemImage: "checkmark.shield")
                        .font(.headline).foregroundStyle(Theme.protectedText)
                    Text("Peers see **\(proxyHost)** instead of your address.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if let detectedVPN {
                    Label("VPN detected", systemImage: "shield")
                        .font(.headline)
                    Text("A VPN is connected (\(detectedVPN)), but Peerbloom can still use other connections.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Use VPN Only", action: bindToVPN)
                        .buttonStyle(.link).font(.caption.weight(.semibold))
                } else {
                    Label("Not bound to a VPN", systemImage: "shield")
                        .font(.headline)
                    Text("Using any network. If you use a VPN, you can bind Peerbloom to it.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Set Up Binding…", action: openSettings)
                        .buttonStyle(.link).font(.caption.weight(.semibold))
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if privacyMode {
                Image(systemName: "eye.slash").font(.caption).foregroundStyle(.secondary)
                    .help("Privacy mode is on")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(fill, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(stroke))
    }

    @ViewBuilder private var openAppButton: some View {
        if let vpnAppName {
            Button("Open \(vpnAppName)", action: openVPNApp)
                .buttonStyle(.link).font(.caption.weight(.semibold))
        }
    }

    private var fill: Color {
        if case .notBound = status, proxyHost != nil { return Theme.protectedFill }
        return switch status {
        case .protected: Theme.protectedFill
        case .down, .waitingForVPN: Theme.warningFill
        case .notBound, .bound: Color.secondary.opacity(0.08)
        }
    }

    private var stroke: Color {
        if case .notBound = status, proxyHost != nil { return Theme.protectedStroke }
        return switch status {
        case .protected: Theme.protectedStroke
        case .down, .waitingForVPN: Theme.warningStroke
        case .notBound, .bound: Color.secondary.opacity(0.2)
        }
    }
}
