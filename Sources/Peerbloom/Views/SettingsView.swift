import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettings().tabItem { Label("Appearance", systemImage: "paintpalette") }
            NetworkSettings().tabItem { Label("Network & Privacy", systemImage: "network.badge.shield.half.filled") }
            SpeedSettings().tabItem { Label("Speed", systemImage: "speedometer") }
            TagSettings().tabItem { Label("Tags", systemImage: "tag") }
        }
        .frame(width: 600)
    }
}

private struct GeneralSettings: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section("Downloads") {
                LabeledContent("Save new transfers to") {
                    HStack {
                        Text(Format.shortPath(store.preferences.defaultSavePath)).lineLimit(1).truncationMode(.middle)
                        Button("Choose…") {
                            if let path = chooseFolder(start: store.preferences.defaultSavePath) {
                                store.preferences.defaultSavePath = path
                            }
                        }
                    }
                }
                Toggle("Start new transfers immediately", isOn: $store.preferences.startImmediately)
                Stepper("Active downloads at once: \(store.preferences.activeDownloads)",
                        value: $store.preferences.activeDownloads, in: 1...20)
                Stepper("Active seeds at once: \(store.preferences.activeSeeds)",
                        value: $store.preferences.activeSeeds, in: 1...50)
                Stepper(store.preferences.minFreeSpaceGB == 0
                        ? "Pause downloads when disk is low: off"
                        : "Pause downloads below \(store.preferences.minFreeSpaceGB) GB free",
                        value: $store.preferences.minFreeSpaceGB, in: 0...500, step: 5)
            }
            Section("While running") {
                Toggle("Notify me when a download finishes", isOn: $store.preferences.notifyOnFinish)
                Toggle("Keep my Mac awake while downloading", isOn: $store.preferences.preventSleep)
                Toggle("Show in menu bar", isOn: $store.preferences.showMenuBarIcon)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppearanceSettings: View {
    @Environment(AppStore.self) private var store
    @State private var copied = false

    private var library: ThemeLibrary { .shared }

    var body: some View {
        @Bindable var store = store
        Form {
            Section("Theme") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(library.all) { theme in
                        ThemeCard(theme: theme, selected: theme.id == store.preferences.themeID)
                            .onTapGesture { store.preferences.themeID = theme.id }
                            .contextMenu {
                                if !library.isBuiltIn(theme) {
                                    Button("Delete Theme", role: .destructive) {
                                        if store.preferences.themeID == theme.id { store.preferences.themeID = AppTheme.standard.id }
                                        library.delete(theme)
                                    }
                                }
                            }
                    }
                }
                .padding(.vertical, 4)
                HStack {
                    Button("Import Theme…", action: importTheme)
                    Button("Show Themes Folder") {
                        try? FileManager.default.createDirectory(at: library.folder, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(library.folder)
                    }
                    Spacer()
                }
                Text("You can also double-click a .peerbloomtheme file. Right-click a theme you imported to delete it.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Make your own") {
                Text("Copy the Theme Maker and paste it into any AI assistant. It asks what you'd like, "
                     + "then writes a theme file you can import here. Themes are only colours and fonts, so they "
                     + "can't run code or change anything else.")
                    .font(.caption).foregroundStyle(.secondary)
                Button(copied ? "Copied" : "Copy Theme Maker", action: copyThemeMaker)
                    .disabled(themeMakerURL == nil)
            }

            Section("Layout") {
                Picker("Row size", selection: $store.preferences.rowDensity) {
                    ForEach(RowDensity.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
    }

    private var themeMakerURL: URL? { Bundle.main.url(forResource: "ThemeMaker", withExtension: "md") }

    private func copyThemeMaker() {
        guard let url = themeMakerURL, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
    }

    private func importTheme() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: AppTheme.fileExtension) ?? .json, .json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            store.importTheme(from: url)
        }
    }
}

/// A small preview of a theme: its window and sidebar colours, a download and a seeding progress bar.
private struct ThemeCard: View {
    let theme: AppTheme
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                (theme.colors.sidebar?.color ?? Color(nsColor: .underPageBackgroundColor))
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 7) {
                    bar(theme.colors.download.color, 0.7)
                    bar(theme.colors.seeding.color, 1)
                    HStack(spacing: 4) {
                        Circle().fill(theme.colors.protected.color).frame(width: 7, height: 7)
                        Capsule().fill(theme.colors.accent.color).frame(width: 30, height: 7)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.colors.background?.color ?? Color(nsColor: .windowBackgroundColor))
            }
            .frame(height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.25)))
            .environment(\.colorScheme, theme.colorScheme ?? systemScheme)
            Text(theme.name).font(.callout.weight(.medium)).fontDesign(theme.fontDesign)
            Text(theme.author.map { "by \($0)" } ?? " ").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(8)
        .background(selected ? Theme.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Theme.accent : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @Environment(\.colorScheme) private var systemScheme

    private func bar(_ color: Color, _ value: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.2))
                Capsule().fill(color).frame(width: geo.size.width * value)
            }
        }
        .frame(height: 5)
    }
}

private struct NetworkSettings: View {
    @Environment(AppStore.self) private var store
    @State private var interfaces: [NetworkInterface] = []
    @State private var proxyPassword = ""

    var body: some View {
        @Bindable var store = store
        let privacy = store.preferences.privacyMode
        Form {
            Section {
                Toggle(isOn: $store.preferences.privacyMode) {
                    Label("Privacy mode", systemImage: "eye.slash")
                }
                Text("Sends traffic only through your VPN (or a SOCKS5 proxy), requires encryption, hides "
                     + "Peerbloom's name, and stops local network broadcasts and router port opening. The "
                     + "settings it controls are greyed out below.")
                    .font(.caption).foregroundStyle(.secondary)
            } footer: {
                Text("With or without it, Peerbloom never collects or shares anything about you.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("VPN protection") {
                // Only connections that are up can be picked, so nobody binds to one that would stall transfers.
                Picker("Send traffic through", selection: $store.preferences.boundInterface) {
                    Text("Any connection (no binding)").tag(String?.none)
                    let vpns = interfaces.filter(\.isActiveVPN)
                    if !vpns.isEmpty || store.preferences.boundInterface == Preferences.anyVPN {
                        Section("VPN") {
                            Text("Any active VPN (recommended)").tag(Optional(Preferences.anyVPN))
                            ForEach(vpns) { Text($0.displayName).tag(Optional($0.name)) }
                        }
                    }
                    let connections = interfaces.filter(\.isActiveConnection)
                    if !connections.isEmpty {
                        Section("Wi-Fi and Ethernet") {
                            ForEach(connections) { Text($0.displayName).tag(Optional($0.name)) }
                        }
                    }
                    if let current = store.preferences.boundInterface, current != Preferences.anyVPN,
                       !vpns.contains(where: { $0.name == current }), !connections.contains(where: { $0.name == current }) {
                        Text("\(current) (not connected)").tag(Optional(current)).disabled(true)
                    }
                }
                .disabled(privacy && !store.preferences.proxyCoversPeers)
                Toggle(store.preferences.bindsToVPN ? "Pause transfers while the VPN is off" : "Pause transfers if this connection drops",
                       isOn: $store.preferences.killSwitch)
                    .disabled(store.preferences.effectiveBinding == nil)
                Text(vpnHelp).font(.caption).foregroundStyle(.secondary)
                LabeledContent("Peers see you as") {
                    Text(store.publicAddress ?? "Not known yet").monospacedDigit().textSelection(.enabled)
                }
                Text("Reported by peers and trackers, so no outside service is asked. When your VPN or proxy works, "
                     + "this is its address, not your home connection's.")
                    .font(.caption).foregroundStyle(.secondary)
                VPNAppPicker()
            }

            Section("Proxy") {
                Picker("Proxy", selection: $store.preferences.proxyType) {
                    ForEach(ProxyType.allCases) { Text($0.label).tag($0) }
                }
                if store.preferences.proxyType != .none {
                    TextField("Server", text: $store.preferences.proxyHost, prompt: Text("proxy.example.com"))
                    TextField("Port", value: $store.preferences.proxyPort, format: .number.grouping(.never))
                    TextField("Username", text: $store.preferences.proxyUsername, prompt: Text("Optional"))
                    SecureField("Password", text: $proxyPassword, prompt: Text("Saved in your Keychain"))
                        .disabled(store.preferences.proxyUsername.isEmpty)
                        .onChange(of: proxyPassword) { _, new in store.setProxyPassword(new) }
                    Toggle("Use for connections to peers", isOn: $store.preferences.proxyPeerConnections)
                    Toggle("Use for trackers", isOn: $store.preferences.proxyTrackerConnections)
                }
                Text("A proxy hides your address from peers only when it carries peer connections. Many VPN providers "
                     + "offer a SOCKS5 proxy. HTTP proxies can't carry DHT, uTP or UDP trackers, so that traffic uses "
                     + "your normal connection, and Privacy mode doesn't count on them. A proxy doesn't encrypt "
                     + "anything; a VPN does.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Peer connections") {
                Picker("Encryption", selection: privacy ? .constant(.require) : $store.preferences.encryption) {
                    ForEach(EncryptionMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(privacy)
                Toggle("Anonymous mode", isOn: privacy ? .constant(true) : $store.preferences.anonymousMode)
                    .disabled(privacy)
                Text("Hides Peerbloom's name and version from peers and trackers. Some private trackers reject this.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Find peers with DHT", isOn: $store.preferences.enableDHT)
                Toggle("Find peers on my local network", isOn: privacy ? .constant(false) : $store.preferences.enableLSD)
                    .disabled(privacy)
            }

            Section("IP blocklist") {
                Toggle("Block IP addresses from a list", isOn: $store.preferences.blocklistEnabled)
                TextField("List URL (P2P or DAT text format)", text: $store.preferences.blocklistURL)
                    .disabled(!store.preferences.blocklistEnabled)
                HStack {
                    Text(blocklistStatus).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Update Now") { store.updateBlocklist() }
                        .disabled(!store.preferences.blocklistEnabled || store.preferences.blocklistURL.isEmpty)
                }
            }

            Section("Listening port") {
                TextField("Incoming port", value: $store.preferences.listenPort, format: .number.grouping(.never))
                Toggle("Open the port on my router automatically (UPnP / NAT-PMP)",
                       isOn: privacy ? .constant(false) : $store.preferences.enablePortMapping)
                    .disabled(privacy)
                Text(portStatus).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if !store.preferences.proxyUsername.isEmpty { proxyPassword = Keychain.proxyPassword }
        }
        .task {
            // Keep the list current while Settings is open, e.g. when a VPN connects.
            while !Task.isCancelled {
                interfaces = NetworkInterfaces.current()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private var vpnHelp: String {
        switch store.vpnStatus {
        case .notBound:
            store.detectedVPN != nil
                ? "A VPN is connected. Choose Any active VPN so Peerbloom only sends traffic through it, even after it reconnects."
                : "Peerbloom doesn't include a VPN. If you use one, connect it first, then choose it here. Peerbloom will only send traffic through it."
        case .waitingForVPN:
            store.preferences.privacyMode
                ? "Privacy mode only sends traffic through a VPN, and none is connected. Connect your VPN, or set up a SOCKS5 proxy below."
                : "No VPN is connected, so nothing is transferring. Transfers start again as soon as a VPN connects."
        case .protected(let iface):
            "Connected through \(iface). If it disconnects, " + (store.preferences.killSwitch
                ? "Peerbloom pauses everything until it's back." : "traffic stops because Peerbloom is bound to it.")
        case .bound(let iface):
            "\(iface) is a regular network connection, not a VPN. Peerbloom will only use it, but your IP address isn't hidden. If it disconnects, " + (store.preferences.killSwitch
                ? "Peerbloom pauses everything until it's back." : "traffic stops because Peerbloom is bound to it.")
        case .down(let iface):
            "\(iface) isn't connected. Transfers are on hold until it comes back."
        }
    }

    private var blocklistStatus: String {
        guard store.preferences.blocklistEnabled else { return "Off" }
        guard store.blocklistRuleCount > 0 else { return "No list loaded yet" }
        let when = store.blocklistUpdated.map { " · updated \(Format.date($0))" } ?? ""
        return "\(store.blocklistRuleCount.formatted()) ranges blocked\(when). Updates daily."
    }

    private var portStatus: String {
        let s = store.session
        if !s.listening { return "Peerbloom isn't listening for incoming connections. Another app may be using this port." }
        if s.portMapped { return "Listening on \(s.listenPort). Your router opened the port." }
        return "Listening on \(s.listenPort). Your router didn't confirm the port is open, so fewer peers may reach you."
    }
}

private struct SpeedSettings: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section("Normal limits") {
                LimitField(title: "Download", value: $store.preferences.downloadLimitKB)
                LimitField(title: "Upload", value: $store.preferences.uploadLimitKB)
            }
            Section("Slow mode limits") {
                LimitField(title: "Download", value: $store.preferences.altDownloadLimitKB)
                LimitField(title: "Upload", value: $store.preferences.altUploadLimitKB)
                Toggle("Slow mode on now", isOn: $store.preferences.altSpeedManual)
            }
            Section("Schedule") {
                Toggle("Use slow mode on a schedule", isOn: $store.preferences.scheduleEnabled)
                Group {
                    DatePicker("From", selection: minutesBinding(\.scheduleStart), displayedComponents: .hourAndMinute)
                    DatePicker("To", selection: minutesBinding(\.scheduleEnd), displayedComponents: .hourAndMinute)
                    HStack {
                        Text("On")
                        Spacer()
                        ForEach(Array(Calendar.current.veryShortWeekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                            let day = index + 1
                            Toggle(symbol, isOn: Binding(
                                get: { store.preferences.scheduleDays.contains(day) },
                                set: { on in
                                    if on { store.preferences.scheduleDays.insert(day) }
                                    else { store.preferences.scheduleDays.remove(day) }
                                }))
                            .toggleStyle(.button)
                            .accessibilityLabel(Calendar.current.weekdaySymbols[index])
                        }
                    }
                }
                .disabled(!store.preferences.scheduleEnabled)
            }
        }
        .formStyle(.grouped)
    }

    private func minutesBinding(_ key: WritableKeyPath<Preferences, Int>) -> Binding<Date> {
        Binding(
            get: {
                let m = store.preferences[keyPath: key]
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                store.preferences[keyPath: key] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            })
    }
}

private struct LimitField: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        LabeledContent(title) {
            HStack {
                TextField(title, value: $value, format: .number.grouping(.never))
                    .labelsHidden()
                    .frame(width: 90)
                    .multilineTextAlignment(.trailing)
                Text(value == 0 ? "KB/s (unlimited)" : "KB/s").foregroundStyle(.secondary)
            }
        }
    }
}

private struct TagSettings: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                ForEach($store.tags) { $tag in
                    HStack {
                        Picker("Color", selection: $tag.color) {
                            ForEach(TagColor.allCases) { c in
                                Text(c.rawValue.capitalized).tag(c)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 90)
                        TextField("Name", text: $tag.name).labelsHidden()
                        Button(tag.savePath.map(Format.shortPath) ?? "Default folder") {
                            if let path = chooseFolder(start: tag.savePath ?? store.preferences.defaultSavePath) {
                                tag.savePath = path
                            }
                        }
                        .help("Transfers with this tag are saved here")
                        if tag.savePath != nil {
                            Button { tag.savePath = nil } label: { Image(systemName: "xmark.circle") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Use default folder")
                        }
                        Button(role: .destructive) {
                            store.tags.removeAll { $0.id == tag.id }
                        } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Delete tag")
                    }
                }
                Button("Add Tag") { store.tags.append(Tag(name: "New Tag", color: .gray)) }
            } footer: {
                Text("A tag can have its own save folder. New transfers with that tag go there.")
            }
        }
        .formStyle(.grouped)
    }
}

/// Which VPN app Peerbloom offers to open when the VPN is off. With no VPN app found, it only offers to pick one.
private struct VPNAppPicker: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        LabeledContent("VPN app to open") {
            HStack {
                if !choices.isEmpty {
                    Picker("VPN app to open", selection: $store.preferences.vpnAppPath) {
                        Text(store.installedVPNApps.first.map { "Automatic (\($0.name))" } ?? "None").tag(String?.none)
                        ForEach(choices) { Text($0.name).tag(Optional($0.url.path)) }
                    }
                    .labelsHidden()
                    .fixedSize()
                } else {
                    Text("None found").foregroundStyle(.secondary)
                }
                Button("Choose…", action: choose)
            }
        }
        Text("When your VPN is off, Peerbloom shows a button to open this app so you can connect. It never controls the VPN itself.")
            .font(.caption).foregroundStyle(.secondary)
    }

    /// Installed VPN apps, plus one picked by hand that isn't among them.
    private var choices: [VPNApps.App] {
        var apps = store.installedVPNApps
        if let path = store.preferences.vpnAppPath, !apps.contains(where: { $0.url.path == path }) {
            apps.append(VPNApps.App(url: URL(fileURLWithPath: path)))
        }
        return apps
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            store.preferences.vpnAppPath = url.path
        }
    }
}

@MainActor
func chooseFolder(start: String) -> String? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.directoryURL = URL(fileURLWithPath: start)
    return panel.runModal() == .OK ? panel.url?.path : nil
}
