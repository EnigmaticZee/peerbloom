import AppKit
import Observation

/// The built-in themes plus the ones the user imported, kept as files in
/// ~/Library/Application Support/Peerbloom/Themes.
@MainActor @Observable
final class ThemeLibrary {
    static let shared = ThemeLibrary()

    private(set) var imported: [AppTheme] = []

    let folder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Peerbloom/Themes", isDirectory: true)

    var all: [AppTheme] { AppTheme.builtIns + imported }

    private init() { reload() }

    /// The theme with this id, or the standard one if it's gone (for example, its file was deleted).
    func theme(id: String) -> AppTheme {
        all.first { $0.id == id } ?? .standard
    }

    func isBuiltIn(_ theme: AppTheme) -> Bool { theme.id.hasPrefix("builtin.") }

    /// Reads every theme file in the folder, skipping any that fail the checks.
    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        imported = files
            .filter { $0.pathExtension == AppTheme.fileExtension }
            .compactMap { url in
                guard var theme = try? AppTheme.load(from: Data(contentsOf: url)) else { return nil }
                theme.id = "file." + url.lastPathComponent
                return theme
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Checks a theme file and copies it into the themes folder. Returns the imported theme.
    @discardableResult
    func importTheme(from url: URL) throws -> AppTheme {
        let theme = try AppTheme.load(from: Data(contentsOf: url))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let slug = theme.name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let destination = folder.appendingPathComponent(String(slug) + "." + AppTheme.fileExtension)
        // Write the checked, re-encoded theme rather than copying the original bytes.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(theme).write(to: destination, options: .atomic)
        reload()
        return imported.first { $0.id == "file." + destination.lastPathComponent } ?? theme
    }

    func delete(_ theme: AppTheme) {
        guard !isBuiltIn(theme), theme.id.hasPrefix("file.") else { return }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(String(theme.id.dropFirst(5))))
        reload()
    }

    /// Applies the theme's light or dark choice to every window, menus included.
    func applyAppearance(of theme: AppTheme) {
        switch theme.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
