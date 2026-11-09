import Charts
import SwiftUI

enum InspectorTab: String, CaseIterable, Identifiable {
    case overview = "Overview", files = "Files", peers = "Peers", trackers = "Trackers"
    var id: String { rawValue }
}

struct InspectorView: View {
    @Environment(AppStore.self) private var store
    @State private var tab = InspectorTab.overview

    var body: some View {
        if let t = store.focused {
            VStack(spacing: 0) {
                InspectorHeader(transfer: t, buckets: store.detail?.pieceBuckets ?? [])
                    .padding(16)
                Divider()
                Picker("Section", selection: $tab) {
                    ForEach(InspectorTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                Divider()
                ScrollView {
                    Group {
                        switch tab {
                        case .overview: OverviewTab(transfer: t)
                        case .files: FilesTab(transfer: t)
                        case .peers: PeersTab()
                        case .trackers: TrackersTab()
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            ContentUnavailableView(
                store.selection.count > 1 ? "\(store.selection.count) transfers selected" : "No selection",
                systemImage: "sidebar.right",
                description: Text(store.selection.count > 1 ? "Select one transfer to see its details."
                                                            : "Select a transfer to see its details."))
        }
    }
}

private struct InspectorHeader: View {
    let transfer: Transfer
    let buckets: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                KindBadge(name: transfer.name, large: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(transfer.name).font(.headline).lineLimit(3).textSelection(.enabled)
                    Text(Format.shortPath(transfer.savePath)).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text(transfer.hasMetadata
                     ? "\(Format.bytes(transfer.totalDone)) of \(Format.bytes(transfer.totalWanted))"
                     : "Waiting for file list")
                Spacer()
                Text(transfer.state.label).fontWeight(.semibold).foregroundStyle(Theme.textColor(for: transfer.state))
            }
            .font(.caption)
            .monospacedDigit()
            PieceMap(buckets: buckets, color: Theme.color(for: transfer.state))
        }
    }
}

/// Grid of cells showing which parts of the transfer are downloaded.
struct PieceMap: View {
    let buckets: [Double]
    let color: Color
    private let columns = 64

    var body: some View {
        Canvas { ctx, size in
            let count = max(buckets.count, 1)
            let rows = Int((Double(count) / Double(columns)).rounded(.up))
            let gap: CGFloat = 2
            let w = (size.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
            let h = (size.height - gap * CGFloat(max(rows - 1, 0))) / CGFloat(max(rows, 1))
            for i in 0..<count {
                let value = buckets.isEmpty ? 0 : buckets[i]
                let rect = CGRect(x: CGFloat(i % columns) * (w + gap), y: CGFloat(i / columns) * (h + gap), width: w, height: h)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(Theme.track))
                if value > 0 {
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(color.opacity(0.35 + 0.65 * value)))
                }
            }
        }
        .frame(height: buckets.count > columns ? CGFloat(buckets.count / columns) * 9 : 8)
        .accessibilityElement()
        .accessibilityLabel("Piece map")
        .accessibilityValue(buckets.isEmpty ? "No data yet"
                            : Format.percent(buckets.reduce(0, +) / Double(buckets.count)) + " downloaded")
    }
}

private struct OverviewTab: View {
    @Environment(AppStore.self) private var store
    let transfer: Transfer

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SpeedChart(samples: store.history[transfer.id] ?? [])

            Grid(horizontalSpacing: 1, verticalSpacing: 1) {
                GridRow {
                    StatCell(title: "Download", value: Format.totalRate(transfer.downloadRate))
                    StatCell(title: "Upload", value: Format.totalRate(transfer.uploadRate))
                }
                GridRow {
                    StatCell(title: "Peers", value: "\(transfer.peers) (\(transfer.seeds) seeds)")
                    StatCell(title: "Ratio", value: Format.ratio(transfer.ratio))
                }
                GridRow {
                    StatCell(title: "Time left", value: transfer.state == .seeding ? "∞" : Format.eta(transfer.eta))
                    StatCell(title: "Availability",
                             value: transfer.availability >= 0 ? String(format: "%.1f", transfer.availability) : "—")
                }
            }
            .background(Color.secondary.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(spacing: 8) {
                InfoRow(label: "Save to", value: Format.shortPath(transfer.savePath))
                InfoRow(label: "Added", value: Format.date(transfer.addedDate))
                if let done = transfer.completedDate { InfoRow(label: "Completed", value: Format.date(done)) }
                InfoRow(label: "Uploaded", value: Format.bytes(transfer.uploaded))
                if let d = store.detail, d.pieceCount > 0 {
                    InfoRow(label: "Pieces", value: "\(d.pieceCount) × \(Format.bytes(Int64(d.pieceSize)))")
                }
                HStack {
                    Text("Info hash").foregroundStyle(.secondary)
                    Spacer()
                    Text(transfer.id.prefix(8) + "…" + transfer.id.suffix(4))
                        .font(.caption.monospaced())
                        .help(transfer.id)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(transfer.id, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Copy info hash")
                }
                if let comment = store.detail?.comment {
                    InfoRow(label: "Comment", value: comment)
                }
            }
            .font(.callout)

            Toggle("Stream while downloading", isOn: Binding(
                get: { transfer.sequential },
                set: { store.setSequential($0, for: transfer.id) }))
                .help("Downloads pieces in order so you can open a video before it finishes.")
        }
    }
}

struct SpeedChart: View {
    let samples: [SpeedSample]
    var height: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Speed, last 5 min").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                LegendDot(color: Theme.download, label: "Down")
                LegendDot(color: Theme.upload, label: "Up")
            }
            Chart(samples) { s in
                LineMark(x: .value("Time", s.time), y: .value("Speed", s.down), series: .value("Direction", "Down"))
                    .foregroundStyle(Theme.download)
                LineMark(x: .value("Time", s.time), y: .value("Speed", s.up), series: .value("Direction", "Up"))
                    .foregroundStyle(Theme.upload)
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Int.self) { Text(Format.bytes(Int64(v)) + "/s").font(.caption2) }
                    }
                }
            }
            .frame(height: height)
            .accessibilityLabel("Speed chart")
            .accessibilityValue("Down \(Format.totalRate(samples.last?.down ?? 0)), up \(Format.totalRate(samples.last?.up ?? 0))")
        }
    }
}

private struct LegendDot: View {
    let color: Color
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Capsule().fill(color).frame(width: 10, height: 2)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct StatCell: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.semibold)).monospacedDigit().lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
    }
}

private struct FilesTab: View {
    @Environment(AppStore.self) private var store
    let transfer: Transfer

    var body: some View {
        if let files = store.detail?.files, !files.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(files) { file in
                    HStack(spacing: 10) {
                        Toggle(isOn: Binding(
                            get: { file.priority != .skip },
                            set: { store.setPriority($0 ? .normal : .skip, file: file.index, for: transfer.id) }
                        )) { EmptyView() }
                            .toggleStyle(.checkbox)
                            .accessibilityLabel("Download \(file.name)")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(file.name).lineLimit(1).truncationMode(.middle).help(file.path)
                            HStack(spacing: 8) {
                                ProgressBar(value: file.progress, color: Theme.color(for: transfer.state), height: 3)
                                Text("\(Format.bytes(file.downloaded)) / \(Format.bytes(file.size))")
                                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        Menu(file.priority.label) {
                            ForEach(FilePriority.allCases) { p in
                                Button(p.label) { store.setPriority(p, file: file.index, for: transfer.id) }
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .font(.caption)
                    }
                    .padding(.vertical, 5)
                    .opacity(file.priority == .skip ? 0.55 : 1)
                }
                Text("Untick a file to skip it. Video files can stream in order while they download.")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }
        } else {
            Text(transfer.hasMetadata ? "Loading files…" : "The file list appears once Peerbloom finds peers who have it.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct PeersTab: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let peers = store.detail?.peers ?? []
        if peers.isEmpty {
            Text("Not connected to any peers.").foregroundStyle(.secondary)
        } else {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Peer"); Text("Down").gridColumnAlignment(.trailing); Text("Up").gridColumnAlignment(.trailing)
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Divider()
                ForEach(peers.prefix(100)) { p in
                    GridRow {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(p.address).font(.caption.monospaced())
                                if p.encrypted {
                                    Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
                                        .accessibilityLabel("Encrypted")
                                }
                            }
                            Text(p.client + (p.isSeed ? " · seed" : "")).font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(Format.rate(p.downloadRate)).font(.caption).monospacedDigit()
                        Text(Format.rate(p.uploadRate)).font(.caption).monospacedDigit()
                    }
                }
            }
        }
    }
}

private struct TrackersTab: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let trackers = store.detail?.trackers ?? []
        VStack(alignment: .leading, spacing: 8) {
            ForEach(trackers) { t in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(t.url).lineLimit(1).truncationMode(.middle).font(.callout).textSelection(.enabled)
                        Spacer()
                        Text(status(t)).font(.caption).foregroundStyle(t.working ? Theme.protectedText : .secondary)
                    }
                    if !t.message.isEmpty {
                        Text(t.message).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Text("DHT")
                Spacer()
                Text(store.preferences.enableDHT ? "On · \(store.session.dhtNodes) nodes" : "Off")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func status(_ t: TrackerItem) -> String {
        if t.updating { return "Contacting…" }
        if t.working { return t.seeds >= 0 ? "Working · \(t.seeds) seeds" : "Working" }
        return t.message.isEmpty ? "Not contacted" : "Error"
    }
}
