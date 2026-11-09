import AppKit
import SwiftUI

/// A Peerbloom theme. Themes are plain data (a `.peerbloomtheme` JSON file): colours, light or dark, and a
/// font style. They can't contain code, so a theme from anywhere can't do anything harmful.
/// The format is documented in Themes/README.md.
struct AppTheme: Codable, Identifiable, Equatable {
    static let format = 1
    static let fileExtension = "peerbloomtheme"

    enum Appearance: String, Codable { case system, light, dark }
    enum FontStyle: String, Codable { case standard, rounded, serif, monospaced }

    struct Colors: Codable, Equatable {
        /// Buttons, switches and links.
        var accent: ThemeColor
        /// Downloading transfers, progress bars and download speeds.
        var download: ThemeColor
        /// Seeding (sharing) transfers and upload speeds.
        var seeding: ThemeColor
        /// The "Protected" VPN status.
        var protected: ThemeColor
        /// Warnings, like a lost VPN connection.
        var warning: ThemeColor
        /// Window background. Nil keeps the standard Mac window colour.
        var background: ThemeColor?
        /// Sidebar background. Nil keeps the standard Mac sidebar.
        var sidebar: ThemeColor?
    }

    var format: Int
    var name: String
    var author: String?
    var appearance: Appearance
    var colors: Colors
    var font: FontStyle?

    /// Set when loading: "builtin.<name>" or the file name. Not stored in the file.
    var id: String = ""

    private enum CodingKeys: String, CodingKey { case format, name, author, appearance, colors, font }

    var colorScheme: ColorScheme? {
        switch appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var fontDesign: Font.Design {
        switch font ?? .standard {
        case .standard: .default
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        }
    }
}

/// A colour in a theme file: "#RRGGBB" for both light and dark mode, or {"light": "#…", "dark": "#…"}.
struct ThemeColor: Codable, Equatable {
    var light: String
    var dark: String

    init(_ both: String) { light = both; dark = both }
    init(light: String, dark: String) { self.light = light; self.dark = dark }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer().decode(String.self) {
            self.init(single)
        } else {
            let pair = try decoder.container(keyedBy: CodingKeys.self)
            self.init(light: try pair.decode(String.self, forKey: .light), dark: try pair.decode(String.self, forKey: .dark))
        }
    }

    func encode(to encoder: Encoder) throws {
        if light == dark {
            var c = encoder.singleValueContainer()
            try c.encode(light)
        } else {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(light, forKey: .light)
            try c.encode(dark, forKey: .dark)
        }
    }

    private enum CodingKeys: String, CodingKey { case light, dark }

    /// A colour that follows the light or dark appearance it's drawn in.
    var nsColor: NSColor {
        let l = RGB(hex: light) ?? RGB(r: 0.5, g: 0.5, b: 0.5)
        let d = RGB(hex: dark) ?? l
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? d.nsColor : l.nsColor
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    /// This colour mixed towards black (light mode) or white (dark mode), for text that needs more contrast.
    var textVariant: ThemeColor {
        guard let l = RGB(hex: light), let d = RGB(hex: dark) else { return self }
        return ThemeColor(light: l.mixed(with: RGB(r: 0, g: 0, b: 0), 0.2).hex, dark: d.mixed(with: RGB(r: 1, g: 1, b: 1), 0.35).hex)
    }
}

/// An sRGB colour with components from 0 to 1.
struct RGB: Equatable {
    var r, g, b: Double

    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        r = Double((v >> 16) & 0xFF) / 255
        g = Double((v >> 8) & 0xFF) / 255
        b = Double(v & 0xFF) / 255
    }

    var hex: String {
        String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }

    func mixed(with other: RGB, _ t: Double) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    /// WCAG relative luminance.
    var luminance: Double {
        func channel(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    /// WCAG contrast ratio, from 1 (none) to 21 (black on white).
    func contrast(with other: RGB) -> Double {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

// MARK: - Validation

enum ThemeError: LocalizedError, Equatable {
    case tooLarge, unreadable, unsupportedFormat(Int), badName, badColor(String), lowContrast(String, Double)

    var errorDescription: String? {
        switch self {
        case .tooLarge: "This file is too large to be a Peerbloom theme."
        case .unreadable: "This isn't a Peerbloom theme file, or it's damaged."
        case .unsupportedFormat(let v): "This theme uses format \(v), which this version of Peerbloom can't read."
        case .badName: "The theme needs a name of 1 to 40 characters."
        case .badColor(let key): "The \(key) colour isn't a valid #RRGGBB colour."
        case .lowContrast(let key, let ratio):
            "The \(key) colour is too close to the background to read (contrast \(String(format: "%.1f", ratio)), needs at least 3)."
        }
    }
}

extension AppTheme {
    static let maxFileSize = 64 * 1024
    /// Standard Mac window colours, used for the contrast check when a theme keeps them.
    private static let standardBackground = (light: RGB(r: 1, g: 1, b: 1), dark: RGB(hex: "#1E1E1E")!)

    /// Reads and checks a theme file.
    static func load(from data: Data) throws -> AppTheme {
        guard data.count <= maxFileSize else { throw ThemeError.tooLarge }
        guard let theme = try? JSONDecoder().decode(AppTheme.self, from: data) else { throw ThemeError.unreadable }
        try theme.validate()
        return theme
    }

    /// Checks the format, the name, every colour, and that coloured text stays readable on the background.
    func validate() throws {
        guard format == Self.format else { throw ThemeError.unsupportedFormat(format) }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...40).contains(trimmed.count) else { throw ThemeError.badName }

        let all: [(String, ThemeColor?)] = [
            ("accent", colors.accent), ("download", colors.download), ("seeding", colors.seeding),
            ("protected", colors.protected), ("warning", colors.warning),
            ("background", colors.background), ("sidebar", colors.sidebar),
        ]
        for (key, value) in all {
            guard let value else { continue }
            guard RGB(hex: value.light) != nil, RGB(hex: value.dark) != nil else { throw ThemeError.badColor(key) }
        }

        // Only the appearances the theme can actually show need checking.
        let modes: [(light: Bool, bg: RGB)] = {
            let bgLight = colors.background.flatMap { RGB(hex: $0.light) } ?? Self.standardBackground.light
            let bgDark = colors.background.flatMap { RGB(hex: $0.dark) } ?? Self.standardBackground.dark
            switch appearance {
            case .light: return [(true, bgLight)]
            case .dark: return [(false, bgDark)]
            case .system: return [(true, bgLight), (false, bgDark)]
            }
        }()
        for (key, value) in [("download", colors.download), ("seeding", colors.seeding),
                             ("protected", colors.protected), ("warning", colors.warning)] {
            for mode in modes {
                let fg = RGB(hex: mode.light ? value.light : value.dark)!
                let ratio = fg.contrast(with: mode.bg)
                if ratio < 3 { throw ThemeError.lowContrast(key, ratio) }
            }
        }
    }
}

// MARK: - Built-in themes

extension AppTheme {
    private static func builtIn(_ name: String, author: String = "Peerbloom", appearance: Appearance, font: FontStyle? = nil,
                                _ colors: Colors) -> AppTheme {
        var theme = AppTheme(format: format, name: name, author: author, appearance: appearance, colors: colors, font: font)
        theme.id = "builtin." + name.lowercased().replacingOccurrences(of: " ", with: "-")
        return theme
    }

    /// The original look: follows the Mac's light or dark mode.
    static let standard = builtIn("Peerbloom", appearance: .system, Colors(
        accent: ThemeColor(light: "#0A64D6", dark: "#4C9EFF"),
        download: ThemeColor(light: "#0A64D6", dark: "#4C9EFF"),
        seeding: ThemeColor(light: "#C25E00", dark: "#F5A04A"),
        protected: ThemeColor(light: "#146C3A", dark: "#7EE2A8"),
        warning: ThemeColor(light: "#C25E00", dark: "#F5A04A")))

    static let builtIns: [AppTheme] = [
        standard,
        builtIn("Ocean", appearance: .dark, Colors(
            accent: ThemeColor("#3C8DFF"), download: ThemeColor("#4FA3FF"), seeding: ThemeColor("#2DE1C2"),
            protected: ThemeColor("#7EE2A8"), warning: ThemeColor("#F5B04A"),
            background: ThemeColor("#0B1A2E"), sidebar: ThemeColor("#08131F"))),
        builtIn("Forest", appearance: .dark, Colors(
            accent: ThemeColor("#6FD39A"), download: ThemeColor("#6FD39A"), seeding: ThemeColor("#E8C468"),
            protected: ThemeColor("#9BE7B4"), warning: ThemeColor("#F0A35E"),
            background: ThemeColor("#0F1A14"), sidebar: ThemeColor("#0B140F"))),
        builtIn("Paper", appearance: .light, font: .serif, Colors(
            accent: ThemeColor("#2B59C3"), download: ThemeColor("#2B59C3"), seeding: ThemeColor("#B4532A"),
            protected: ThemeColor("#2E7D4F"), warning: ThemeColor("#B4532A"),
            background: ThemeColor("#FBF8F2"), sidebar: ThemeColor("#F2EDE3"))),
        builtIn("Terminal", appearance: .dark, font: .monospaced, Colors(
            accent: ThemeColor("#33FF66"), download: ThemeColor("#33FF66"), seeding: ThemeColor("#FFB000"),
            protected: ThemeColor("#33FF66"), warning: ThemeColor("#FFB000"),
            background: ThemeColor("#050505"), sidebar: ThemeColor("#0C0C0C"))),
        builtIn("High Contrast", appearance: .system, Colors(
            accent: ThemeColor(light: "#0040A0", dark: "#6FB6FF"),
            download: ThemeColor(light: "#0040A0", dark: "#6FB6FF"),
            seeding: ThemeColor(light: "#8A3B00", dark: "#FFB547"),
            protected: ThemeColor(light: "#00632B", dark: "#5CF59A"),
            warning: ThemeColor(light: "#8A3B00", dark: "#FFB547"))),
    ]
}
