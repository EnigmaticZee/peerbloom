import AppKit
import SwiftUI

/// Colors come from the active theme (Settings › Appearance). Each has a light and a dark value and
/// follows the appearance it's drawn in. The standard theme keeps the original design's colors.
@MainActor
enum Theme {
    /// The theme in use. Reading it inside a view makes the view redraw when the theme changes.
    static var current: AppTheme { ThemeLibrary.shared.theme(id: AppStore.shared.preferences.themeID) }

    static var accent: Color { current.colors.accent.color }
    static var download: Color { current.colors.download.color }
    static var upload: Color { current.colors.seeding.color }
    static var downloadText: Color { current.colors.download.textVariant.color }
    static var uploadText: Color { current.colors.seeding.textVariant.color }
    static let muted = dynamic(light: 0x8E8E93, dark: 0x7C7C86)
    static let idle = dynamic(light: 0xAEAEB2, dark: 0x55555D)
    static let track = dynamic(light: 0xE5E5EA, dark: 0x2E2E33)
    static var protectedFill: Color { current.colors.protected.color.opacity(0.14) }
    static var protectedStroke: Color { current.colors.protected.color.opacity(0.4) }
    static var protectedText: Color { current.colors.protected.color }
    static var warningFill: Color { current.colors.warning.color.opacity(0.14) }
    static var warningStroke: Color { current.colors.warning.color.opacity(0.4) }
    /// Nil keeps the standard Mac colors.
    static var background: Color? { current.colors.background?.color }
    static var sidebar: Color? { current.colors.sidebar?.color }

    static func color(for state: TransferState) -> Color {
        switch state {
        case .downloading, .fetchingMetadata, .checking: download
        case .seeding: upload
        case .completed: muted
        case .paused, .queued: idle
        case .error: .red
        }
    }

    static func textColor(for state: TransferState) -> Color {
        switch state {
        case .downloading, .fetchingMetadata, .checking: downloadText
        case .seeding: uploadText
        case .error: .red
        default: .secondary
        }
    }

    static func color(for tag: TagColor) -> Color {
        switch tag {
        case .blue: download
        case .orange: upload
        case .purple: dynamic(light: 0x7C4DDB, dark: 0xB58CFF)
        case .green: dynamic(light: 0x1E8E4A, dark: 0x5BD08A)
        case .pink: dynamic(light: 0xC2306B, dark: 0xF07AAA)
        case .gray: muted
        }
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// Thin rounded progress bar used in the list, inspector and menu bar.
struct ProgressBar: View {
    let value: Double
    let color: Color
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(color).frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue(Format.percent(value))
    }
}

/// Small tile showing a file-type badge, like "ISO" or "MOV".
struct KindBadge: View {
    let name: String
    var large = false

    private var kind: (String, Color) {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "iso", "img", "dmg": return ("ISO", Theme.download)
        case "mkv", "mp4", "mov", "avi", "webm": return ("MOV", Theme.upload)
        case "mp3", "flac", "m4a", "wav", "ogg": return ("AUD", Theme.color(for: .green))
        case "zip", "tar", "gz", "7z", "rar": return ("ARC", Theme.color(for: .purple))
        default: return (ext.isEmpty ? "DIR" : String(ext.prefix(3)).uppercased(), Theme.muted)
        }
    }

    var body: some View {
        let (label, color) = kind
        Text(label)
            .font(.system(size: large ? 11 : 9, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(color)
            .frame(width: large ? 44 : 34, height: large ? 44 : 24)
            .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: large ? 10 : 5))
            .accessibilityHidden(true)
    }
}

/// Applies the theme's accent color and font style to a window's content.
struct Themed: ViewModifier {
    func body(content: Content) -> some View {
        content
            .tint(Theme.accent)
            .fontDesign(Theme.current.fontDesign)
    }
}

/// Paints a theme's background behind a list or table, or leaves the standard one when the theme has none.
struct ThemedBackground: ViewModifier {
    let color: Color?

    func body(content: Content) -> some View {
        if let color {
            content.scrollContentBackground(.hidden).background(color)
        } else {
            content
        }
    }
}

extension View {
    func themed() -> some View { modifier(Themed()) }
    func themedBackground(_ color: Color?) -> some View { modifier(ThemedBackground(color: color)) }
}
