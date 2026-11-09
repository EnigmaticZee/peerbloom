import SwiftUI

struct MainWindow: View {
    @Environment(AppStore.self) private var store
    @State private var showInspector = true

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            SidebarView()
        } detail: {
            VStack(spacing: 0) {
                TransferListView()
                Divider()
                StatusBar()
            }
            .inspector(isPresented: $showInspector) {
                InspectorView()
                    .themedBackground(Theme.background)
                    .inspectorColumnWidth(min: 300, ideal: 340, max: 460)
            }
        }
        .navigationTitle(store.sidebarTitle)
        .navigationSubtitle("↓ \(Format.totalRate(store.totalDownloadRate))  ↑ \(Format.totalRate(store.totalUploadRate))")
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "Search transfers")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("Open Torrent File…") { store.chooseTorrentFile() }
                    Button("Add Magnet Link…") { store.pendingAdd = .magnet("") }
                } label: {
                    Label("Add", systemImage: "plus")
                } primaryAction: {
                    store.chooseTorrentFile()
                }
                .help("Add a torrent file or magnet link")
                Button { store.resume() } label: { Label("Resume", systemImage: "play.fill") }
                    .disabled(store.selection.isEmpty)
                    .help("Resume selected")
                Button { store.pause() } label: { Label("Pause", systemImage: "pause.fill") }
                    .disabled(store.selection.isEmpty)
                    .help("Pause selected")
                Button { store.requestRemove() } label: { Label("Remove", systemImage: "trash") }
                    .disabled(store.selection.isEmpty)
                    .help("Remove selected")
                Button { showInspector.toggle() } label: { Label("Details", systemImage: "sidebar.right") }
                    .help("Show or hide details")
            }
        }
        .sheet(item: $store.pendingAdd) { source in
            AddTransferSheet(source: source)
        }
        .confirmationDialog(removalTitle, isPresented: Binding(
            get: { store.pendingRemoval != nil },
            set: { if !$0 { store.pendingRemoval = nil } }
        )) {
            Button("Remove from List") { store.confirmRemove(deleteFiles: false) }
            Button("Remove and Delete Files", role: .destructive) { store.confirmRemove(deleteFiles: true) }
            Button("Cancel", role: .cancel) { store.pendingRemoval = nil }
        } message: {
            Text("Removing from the list keeps the downloaded files on your Mac.")
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .alert(riskyTitle, isPresented: Binding(
            get: { !store.riskyAlerts.isEmpty },
            set: { _ in }
        )) {
            Button("Skip These Files") { store.resolveRiskyAlert(skip: true) }
            Button("Keep Them", role: .cancel) { store.resolveRiskyAlert(skip: false) }
        } message: {
            Text(riskyMessage)
        }
        .frame(minWidth: 900, minHeight: 520)
    }

    private var riskyTitle: String {
        "“\(store.riskyAlerts.first?.name ?? "This transfer")” contains programs"
    }

    private var riskyMessage: String {
        guard let alert = store.riskyAlerts.first else { return "" }
        let names = alert.findings.prefix(4).map(\.name).joined(separator: "\n")
        return RiskyFiles.summary(alert.findings) + " Movies, music and documents never need them, so only keep them "
            + "if you trust where this torrent came from.\n\n" + names + (alert.findings.count > 4 ? "\n…" : "")
    }

    private var removalTitle: String {
        let n = store.pendingRemoval?.count ?? 0
        return n == 1 ? "Remove this transfer?" : "Remove \(n) transfers?"
    }
}

struct StatusBar: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 18) {
            if store.preferences.enableDHT {
                Text("DHT: \(store.session.dhtNodes) nodes")
            }
            Text(portText)
            if let free = store.freeSpace {
                Text("Disk: \(Format.bytes(free)) free")
            }
            if store.altSpeedActive {
                Label("Slow mode on", systemImage: "tortoise").foregroundStyle(Theme.uploadText)
            }
            Spacer()
            Text("Session ratio \(Format.ratio(store.sessionRatio))")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var portText: String {
        let s = store.session
        guard s.listening else { return "Not listening" }
        return s.portMapped ? "Port \(s.listenPort): mapped" : "Port \(s.listenPort): listening"
    }
}
