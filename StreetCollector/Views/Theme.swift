import SwiftUI

enum Theme {
    static let accent = Color(red: 0.16, green: 0.83, blue: 0.62)
    static let collected = Color(red: 0.16, green: 0.83, blue: 0.62)
    static let partial = Color(red: 0.99, green: 0.74, blue: 0.24)
    static let uncollected = Color(white: 0.55)
    static let hot = Color(red: 0.36, green: 0.74, blue: 1.0)

    static func tierColor(_ tier: Achievement.Tier) -> Color {
        switch tier {
        case .bronze: return Color(red: 0.80, green: 0.50, blue: 0.20)
        case .silver: return Color(red: 0.72, green: 0.75, blue: 0.79)
        case .gold: return Color(red: 0.95, green: 0.77, blue: 0.22)
        case .legendary: return Color(red: 0.66, green: 0.42, blue: 0.96)
        }
    }

    static func classificationColor(_ classification: StreetClassification) -> Color {
        switch classification {
        case .motorway, .trunk: return Color(red: 0.93, green: 0.45, blue: 0.40)
        case .primary, .secondary: return Color(red: 0.95, green: 0.70, blue: 0.35)
        case .tertiary, .residential, .living: return accent
        case .service, .track: return Color(white: 0.6)
        case .pedestrian, .path: return Color(red: 0.55, green: 0.80, blue: 0.95)
        }
    }
}

/// A rounded panel used for every card on the stats and detail screens.
struct Card<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var symbolName: String?
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let symbolName {
                Image(systemName: symbolName)
                    .font(.caption)
                    .foregroundStyle(tint)
            }
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Circular progress used for level and tile completion.
struct ProgressRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 8
    var tint: Color = Theme.accent

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: fraction)
        }
    }
}

struct LinearProgress: View {
    let fraction: Double
    var tint: Color = Theme.accent

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.18))
                Capsule()
                    .fill(tint)
                    .frame(width: geometry.size.width * max(0, min(1, fraction)))
                    .animation(.easeOut(duration: 0.3), value: fraction)
            }
        }
        .frame(height: 6)
    }
}

struct EmptyStateView: View {
    let symbolName: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 42))
                .foregroundStyle(Theme.accent.opacity(0.7))
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}
