import Foundation

/// Display formatting, in one place so units stay consistent across screens.
enum Format {

    static func distance(_ metres: Double) -> String {
        if metres < 1_000 {
            return "\(Int(metres.rounded())) m"
        }
        return String(format: "%.1f km", metres / 1_000)
    }

    static func longDistance(_ metres: Double) -> String {
        String(format: "%.0f km", metres / 1_000)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m \(total % 60)s"
    }

    static func speed(_ metresPerSecond: Double) -> String {
        String(format: "%.1f km/h", metresPerSecond * 3.6)
    }

    static func percent(_ fraction: Double) -> String {
        String(format: "%.1f%%", min(1, max(0, fraction)) * 100)
    }

    static func xp(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    static let relativeDate: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func relative(_ date: Date) -> String {
        relativeDate.localizedString(for: date, relativeTo: Date())
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}
