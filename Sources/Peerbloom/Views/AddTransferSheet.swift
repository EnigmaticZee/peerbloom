import SwiftUI

struct AddTransferSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let source: AddSource
    @State private var magnet = ""
    @State private var wanted: Set<Int> = []
    @State private var savePath = ""
    @State private var tag: UUID?
    @State private var stream = false
    @State private var start = true

    private var preview: TorrentPreview? {
        if case .file(let p) = source { return p }
        return nil
    }

    private var selectedSize: Int64 {
        preview?.files.filter { wanted.contains($0.index) }.reduce(0) { $0 + $1.size } ?? 0
    }

    private var canAdd: Bool {
        if preview != nil { return !wanted.isEmpty }
        return magnet.lowercased().hasPrefix("magnet:")
    }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let preview { filesSection(preview) }
                    options
                }
                .padding(20)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Transfer") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
            }
            .padding(16)
        }
        .frame(width: 600, height: preview == nil ? 430 : 600)
        .onAppear {
            if case .magnet(let uri) = source { magnet = uri }
            wanted = Set(preview?.files.map(\.index) ?? [])
            savePath = store.preferences.defaultSavePath
            start = store.preferences.startImmediately
        }
        .onChange(of: tag) { _, newTag in savePath = store.defaultSavePath(for: newTag) }
    }

    @ViewBuilder private var header: some View {
        if let preview {
            HStack(spacing: 12) {
                KindBadge(name: preview.files.count == 1 ? preview.files[0].name : preview.name, large: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(preview.name).font(.headline).lineLimit(2)
                    Text("\(preview.files.count) file\(preview.files.count == 1 ? "" : "s") · \(Format.bytes(preview.totalSize))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Add Magnet Link").font(.headline)
                TextField("magnet:?xt=urn:btih:…", text: $magnet, axis: .vertical)
                    .font(.body.monospaced())
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                Text("The file list appears once Peerbloom finds peers who have it. You can skip files from the Files tab then.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func filesSection(_ preview: TorrentPreview) -> some View {
        let risky = RiskyFiles.check(preview.files)
        let riskyIndices = Set(risky.flatMap(\.indices))
        return VStack(alignment: .leading, spacing: 8) {
            if !risky.isEmpty {
                RiskyFilesBanner(findings: risky, allSkipped: riskyIndices.isDisjoint(with: wanted)) {
                    wanted.subtract(riskyIndices)
                }
            }
            HStack {
                Text("Files").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(wanted.count) of \(preview.files.count) selected · \(Format.bytes(selectedSize))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            VStack(spacing: 0) {
                ForEach(preview.files) { file in
                    Toggle(isOn: Binding(
                        get: { wanted.contains(file.index) },
                        set: { if $0 { wanted.insert(file.index) } else { wanted.remove(file.index) } }
                    )) {
                        HStack {
                            if riskyIndices.contains(file.index) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Theme.uploadText)
                                    .help("An app, installer or script")
                            }
                            Text(file.path).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(Format.bytes(file.size)).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .toggleStyle(.checkbox)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    Divider()
                }
            }
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.2)))
            HStack {
                Button("Select All") { wanted = Set(preview.files.map(\.index)) }
                Button("Select None") { wanted = [] }
            }
            .buttonStyle(.link).font(.caption)
        }
    }

    private var options: some View {
        Form {
            LabeledContent("Save to") {
                HStack {
                    Text(Format.shortPath(savePath)).lineLimit(1).truncationMode(.middle)
                    Button("Choose…") { chooseFolder() }
                }
            }
            Picker("Tag", selection: $tag) {
                Text("None").tag(UUID?.none)
                ForEach(store.tags) { t in
                    Text(t.name).tag(Optional(t.id))
                }
            }
            Toggle("Stream while downloading", isOn: $stream)
            Text("Fetches pieces in order so you can start watching right away.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Start immediately", isOn: $start)
        }
        .formStyle(.columns)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: savePath)
        if panel.runModal() == .OK, let url = panel.url { savePath = url.path }
    }

    private func add() {
        let finalSource: AddSource
        var priorities: [FilePriority]?
        if let preview {
            finalSource = source
            // libtorrent expects one priority per file index, including padding files.
            let count = (preview.files.map(\.index).max() ?? -1) + 1
            priorities = (0..<count).map { wanted.contains($0) ? .normal : .skip }
        } else {
            finalSource = .magnet(magnet.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        store.add(finalSource, savePath: savePath, tag: tag, start: start, sequential: stream, priorities: priorities)
        dismiss()
    }
}

/// Warns that a torrent contains apps, installers or scripts, which media and documents never need.
struct RiskyFilesBanner: View {
    let findings: [RiskyFiles.Finding]
    let allSkipped: Bool
    let skip: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3).foregroundStyle(Theme.uploadText)
            VStack(alignment: .leading, spacing: 4) {
                Text("This torrent contains programs").font(.subheadline.weight(.semibold))
                Text(RiskyFiles.summary(findings) + " Movies, music and documents never need them, so only keep "
                     + "them if you trust where this torrent came from.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(findings.prefix(3).map(\.name).joined(separator: ", ") + (findings.count > 3 ? ", …" : ""))
                    .font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                if allSkipped {
                    Label("Skipped", systemImage: "checkmark").font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.protectedText)
                } else {
                    Button("Skip These Files", action: skip)
                        .buttonStyle(.link).font(.caption.weight(.semibold))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.warningFill, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.warningStroke))
    }
}
