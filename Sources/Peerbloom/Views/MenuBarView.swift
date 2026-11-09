import SwiftUI

struct MenuBarView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                SpeedTile(title: "Down", value: store.totalDownloadRate, color: Theme.downloadText)
                SpeedTile(title: "Up", value: store.totalUploadRate, color: Theme.uploadText)
            }

            let active = store.transfers.filter(\.isActive).sorted { $0.downloadRate > $1.downloadRate }.prefix(4)
            VStack(alignment: .leading, spacing: 12) {
                Text("Active").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if active.isEmpty {
                    Text("Nothing is transferring right now.").font(.callout).foregroundStyle(.secondary)
                }
                ForEach(Array(active)) { t in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(t.name).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(t.state == .seeding ? "Seeding · \(Format.ratio(t.ratio))" : Format.eta(t.eta))
                                .font(.caption).foregroundStyle(Theme.textColor(for: t.state)).monospacedDigit()
                        }
                        ProgressBar(value: t.progress, color: Theme.color(for: t.state))
                    }
                }
            }

            Divider()

            HStack(spacing: 10) {
                switch store.vpnStatus {
                case .protected(let iface):
                    Image(systemName: "checkmark.shield").foregroundStyle(Theme.protectedText)
                    Text("VPN bound · \(iface)")
                    Spacer()
                    Text("Protected").font(.caption).foregroundStyle(Theme.protectedText)
                case .bound(let iface):
                    Image(systemName: "network").foregroundStyle(.secondary)
                    Text("Bound to \(iface)")
                    Spacer()
                    Text("Not a VPN").font(.caption).foregroundStyle(.secondary)
                case .down(let iface):
                    Image(systemName: "exclamationmark.shield").foregroundStyle(Theme.uploadText)
                    Text("\(iface) disconnected")
                    Spacer()
                    openVPNAppOr("Paused")
                case .waitingForVPN:
                    Image(systemName: "exclamationmark.shield").foregroundStyle(Theme.uploadText)
                    Text("No VPN connected")
                    Spacer()
                    openVPNAppOr("Waiting")
                case .notBound where store.preferences.proxyCoversPeers:
                    Image(systemName: "checkmark.shield").foregroundStyle(Theme.protectedText)
                    Text("Proxy · \(store.preferences.proxyHost)").lineLimit(1)
                    Spacer()
                    Text("Protected").font(.caption).foregroundStyle(Theme.protectedText)
                case .notBound:
                    Image(systemName: "shield").foregroundStyle(.secondary)
                    Text(store.detectedVPN != nil ? "VPN detected" : "Not bound to a VPN")
                    Spacer()
                    if store.detectedVPN != nil {
                        Button("Use VPN Only") { store.bindToAnyVPN() }
                            .buttonStyle(.link).font(.caption)
                    }
                }
            }
            Toggle(isOn: Binding(get: { store.altSpeedActive }, set: { _ in store.toggleAltSpeed() })) {
                HStack {
                    Image(systemName: "tortoise")
                    Text("Slow mode")
                }
            }
            .toggleStyle(.switch)
            .disabled(store.preferences.scheduleEnabled && store.preferences.altSpeedActive() && !store.preferences.altSpeedManual)

            HStack(spacing: 8) {
                if store.transfers.contains(where: { !$0.isPaused }) {
                    Button { store.pauseAll() } label: { Label("Pause All", systemImage: "pause.fill").frame(maxWidth: .infinity) }
                } else {
                    Button { store.resumeAll() } label: { Label("Resume All", systemImage: "play.fill").frame(maxWidth: .infinity) }
                }
                Button {
                    openWindow(id: "main")
                    NSApp.activate()
                } label: { Text("Open Peerbloom").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
        .padding(14)
        .frame(width: 340)
    }

    /// A button to open the user's VPN app, or a plain status word for people without one.
    @ViewBuilder private func openVPNAppOr(_ status: String) -> some View {
        if let app = store.vpnApp {
            Button("Open \(app.name)") { store.openVPNApp() }
                .buttonStyle(.link).font(.caption)
        } else {
            Text(status).font(.caption).foregroundStyle(Theme.uploadText)
        }
    }
}

private struct SpeedTile: View {
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(color)
            Text(Format.totalRate(value)).font(.title3.weight(.bold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
    }
}
