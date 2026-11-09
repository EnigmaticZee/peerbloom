import SwiftUI
import UniformTypeIdentifiers

struct TransferListView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        let compact = store.preferences.rowDensity == .compact

        Table(store.visibleTransfers, selection: $store.selection, sortOrder: $store.sortOrder) {
            TableColumn("Name", value: \.name) { t in
                HStack(spacing: 10) {
                    if !compact { KindBadge(name: t.name) }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.name).lineLimit(1).truncationMode(.middle)
                        if !compact {
                            Text(subtitle(t)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .padding(.vertical, compact ? 0 : 3)
                .help(t.name)
            }
            .width(min: 220, ideal: 360)

            TableColumn("Size", value: \.sortSize) { t in
                Text(t.hasMetadata ? Format.bytes(t.totalWanted) : "—").foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 76)

            TableColumn("Progress", value: \.progress) { t in
                HStack(spacing: 8) {
                    ProgressBar(value: t.progress, color: Theme.color(for: t.state))
                    Text(Format.percent(t.progress)).font(.caption).foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
            .width(min: 110, ideal: 150)

            TableColumn("Status", value: \.sortStatus) { t in
                Text(t.state.label).font(.callout.weight(.medium)).foregroundStyle(Theme.textColor(for: t.state))
                    .help(t.errorMessage ?? t.state.label)
            }
            .width(min: 80, ideal: 104)

            TableColumn("Down", value: \.downloadRate) { t in
                Text(Format.rate(t.downloadRate)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 64, ideal: 88)

            TableColumn("Up", value: \.uploadRate) { t in
                Text(Format.rate(t.uploadRate)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 64, ideal: 88)

            TableColumn("ETA", value: \.sortETA) { t in
                Text(t.state == .seeding ? "∞" : Format.eta(t.eta)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 50, ideal: 72)

            TableColumn("Ratio", value: \.ratio) { t in
                Text(Format.ratio(t.ratio)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 44, ideal: 56)

            TableColumn("Queue", value: \.sortQueue) { t in
                Text(t.queuePosition >= 0 ? "\(t.queuePosition + 1)" : "—").foregroundStyle(.secondary)
            }
            .width(min: 40, ideal: 50)
        }
        .monospacedDigit()
        .controlSize(compact ? .small : .regular)
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .themedBackground(Theme.background)
        .contextMenu(forSelectionType: String.self) { ids in
            TransferMenuItems(ids: ids)
        } primaryAction: { ids in
            store.showInFinder(ids)
        }
        .overlay {
            if store.visibleTransfers.isEmpty {
                EmptyListView(searching: !store.searchText.isEmpty)
            }
        }
        .onDrop(of: [.fileURL, .url, .plainText], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private func subtitle(_ t: Transfer) -> String {
        var parts: [String] = []
        if let tag = store.tag(for: t.id) { parts.append(tag.name) }
        switch t.state {
        case .downloading: parts.append("\(t.peers) peers")
        case .seeding: parts.append("ratio \(Format.ratio(t.ratio))")
        case .fetchingMetadata: parts.append("Finding peers for file list")
        case .error: parts.append(t.errorMessage ?? "Error")
        default: break
        }
        if t.sequential { parts.append("Streaming") }
        return parts.isEmpty ? Format.shortPath(t.savePath) : parts.joined(separator: " · ")
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, url.pathExtension.lowercased() == "torrent" else { return }
                    Task { @MainActor in store.openTorrentFile(at: url) }
                }
                return true
            }
            if provider.canLoadObject(ofClass: String.self) {
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    guard let text, text.lowercased().hasPrefix("magnet:") else { return }
                    Task { @MainActor in store.requestAdd(magnet: text) }
                }
                return true
            }
        }
        return false
    }
}

/// Right-click and menu bar actions for one or more transfers.
struct TransferMenuItems: View {
    @Environment(AppStore.self) private var store
    let ids: Set<String>

    var body: some View {
        let items = store.transfers.filter { ids.contains($0.id) }
        if !items.isEmpty {
            if items.contains(where: { !$0.isPaused }) {
                Button("Pause") { store.pause(ids) }
            }
            if items.contains(where: \.isPaused) {
                Button("Resume") { store.resume(ids) }
            }
            Divider()
            Button("Show in Finder") { store.showInFinder(ids) }
            Button("Copy Magnet Link") { store.copyMagnetLinks(ids) }
            Divider()
            Menu("Queue") {
                Button("Move to Top") { store.move(ids, .top) }
                Button("Move Up") { store.move(ids, .up) }
                Button("Move Down") { store.move(ids, .down) }
                Button("Move to Bottom") { store.move(ids, .bottom) }
            }
            Menu("Tag") {
                Button("None") { store.assign(tag: nil, to: ids) }
                Divider()
                ForEach(store.tags) { tag in
                    Button(tag.name) { store.assign(tag: tag.id, to: ids) }
                }
            }
            if items.count == 1, let t = items.first {
                Toggle("Stream While Downloading", isOn: Binding(
                    get: { t.sequential },
                    set: { store.setSequential($0, for: t.id) }))
            }
            Button("Move Files…") { store.chooseNewLocation(ids) }
            Divider()
            Button("Verify Downloaded Data") { store.recheck(ids) }
            Button("Ask Trackers for More Peers") { store.reannounce(ids) }
            Divider()
            Button("Remove…", role: .destructive) { store.requestRemove(ids) }
        }
    }
}

private struct EmptyListView: View {
    @Environment(AppStore.self) private var store
    let searching: Bool

    var body: some View {
        if searching {
            ContentUnavailableView.search
        } else {
            ContentUnavailableView {
                Label("No transfers", systemImage: "arrow.down.circle")
            } description: {
                Text("Drop a .torrent file or a magnet link here, or click Add.")
            } actions: {
                Button("Open Torrent File…") { store.chooseTorrentFile() }
            }
        }
    }
}
