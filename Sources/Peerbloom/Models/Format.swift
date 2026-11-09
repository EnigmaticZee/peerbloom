import Foundation

enum Format {
    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f
    }()

    static func bytes(_ value: Int64) -> String {
        byteFormatter.string(fromByteCount: max(0, value))
    }

    static func rate(_ bytesPerSecond: Int) -> String {
        bytesPerSecond <= 0 ? "—" : bytes(Int64(bytesPerSecond)) + "/s"
    }

    /// Like `rate`, but shows "0 KB/s" instead of a dash. For totals.
    static func totalRate(_ bytesPerSecond: Int) -> String {
        bytes(Int64(max(0, bytesPerSecond))) + "/s"
    }

    static func eta(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "—" }
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        if s < 86_400 { return "\(s / 3600)h \((s % 3600) / 60)m" }
        return "\(s / 86_400)d \((s % 86_400) / 3600)h"
    }

    static func ratio(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    static func percent(_ fraction: Double) -> String {
        let p = fraction * 100
        if p >= 100 { return "100%" }
        return p < 10 ? String(format: "%.1f%%", p) : "\(Int(p))%"
    }

    static func date(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today, " + date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func shortPath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
