import SwiftUI

/// The visual language: neon-on-asphalt, rounded, arcade-adjacent.
///
/// The app is a game about a city at night, so the palette is a dark base with
/// a small set of saturated signal colours that only ever mean one thing:
/// mint is collected, amber is in progress, cyan is happening right now.
enum Theme {

    // MARK: - Palette

    static let ink = Color(hex: 0x0A0E14)
    static let surface = Color(hex: 0x141C26)
    static let surfaceRaised = Color(hex: 0x1C2734)

    static let accent = Color(hex: 0x2DE0A5)        // collected
    static let partial = Color(hex: 0xFFBC3D)       // in progress
    static let hot = Color(hex: 0x5BC8FF)           // live, this trip
    static let magenta = Color(hex: 0xFF5DA2)       // celebration
    static let violet = Color(hex: 0xA86BF5)        // legendary
    static let uncollected = Color(hex: 0x6B7A8C)

    static let collected = accent

    // MARK: - Gradients

    /// Primary action gradient. Mint into cyan, like a lit street seen at speed.
    static let primaryGradient = LinearGradient(
        colors: [Color(hex: 0x2DE0A5), Color(hex: 0x36B8FF)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let streakGradient = LinearGradient(
        colors: [Color(hex: 0xFFBC3D), Color(hex: 0xFF5DA2)],
        startPoint: .top,
        endPoint: .bottom
    )

    static let legendaryGradient = LinearGradient(
        colors: [Color(hex: 0xA86BF5), Color(hex: 0xFF5DA2)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let dangerGradient = LinearGradient(
        colors: [Color(hex: 0xFF6B6B), Color(hex: 0xFF3D71)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Backdrop for full-screen surfaces: a faint glow from the top, as if the
    /// city were lighting the screen.
    static let backdrop = LinearGradient(
        colors: [Color(hex: 0x16222F), Color(hex: 0x0A0E14)],
        startPoint: .top,
        endPoint: .bottom
    )

    static func gradient(for tier: Achievement.Tier) -> LinearGradient {
        switch tier {
        case .bronze:
            return LinearGradient(colors: [Color(hex: 0xD98C4A), Color(hex: 0x9C5A24)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .silver:
            return LinearGradient(colors: [Color(hex: 0xD6DEE8), Color(hex: 0x8C9AAB)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .gold:
            return LinearGradient(colors: [Color(hex: 0xFFD75E), Color(hex: 0xF0921E)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .legendary:
            return legendaryGradient
        }
    }

    static func tierColor(_ tier: Achievement.Tier) -> Color {
        switch tier {
        case .bronze: return Color(hex: 0xD98C4A)
        case .silver: return Color(hex: 0xC3CDD9)
        case .gold: return Color(hex: 0xFFD75E)
        case .legendary: return violet
        }
    }

    static func classificationColor(_ classification: StreetClassification) -> Color {
        switch classification {
        case .motorway, .trunk: return Color(hex: 0xFF8A6B)
        case .primary, .secondary: return Color(hex: 0xFFBC3D)
        case .tertiary, .residential, .living: return accent
        case .service, .track: return uncollected
        case .pedestrian, .path: return hot
        }
    }

    // MARK: - Type

    /// Everything is rounded. It is the single cheapest decision that stops the
    /// app reading as a spreadsheet.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let display = font(34, .heavy)
    static let title = font(24, .bold)
    static let headline = font(17, .bold)
    static let body = font(15, .medium)
    static let caption = font(12, .medium)
    static let micro = font(10, .bold)

    /// Numbers that change constantly (XP, distance) get tabular figures so the
    /// HUD doesn't jitter.
    static func numeric(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    // MARK: - Geometry

    static let cornerRadius: CGFloat = 20
    static let tightRadius: CGFloat = 14
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Chrome

/// A glass panel with a lit top edge. Used for every card and the HUD, so the
/// whole app looks like one object.
struct GlassPanel<Content: View>: View {
    var tint: Color = Theme.accent
    var glow: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Theme.surface.opacity(0.88))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [tint.opacity(glow ? 0.55 : 0.22), .white.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: glow ? tint.opacity(0.28) : .black.opacity(0.35), radius: glow ? 18 : 12, y: 6)
    }
}

/// Section card. Same panel, with an optional eyebrow heading.
struct Card<Content: View>: View {
    var title: String? = nil
    var symbol: String? = nil
    var tint: Color = Theme.accent
    @ViewBuilder var content: Content

    var body: some View {
        GlassPanel(tint: tint) {
            VStack(alignment: .leading, spacing: 14) {
                if let title {
                    HStack(spacing: 6) {
                        if let symbol {
                            Image(systemName: symbol).font(Theme.micro)
                        }
                        Text(title.uppercased())
                            .font(Theme.micro)
                            .tracking(1.2)
                    }
                    .foregroundStyle(tint.opacity(0.9))
                }
                content
            }
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var symbolName: String?
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let symbolName {
                Image(systemName: symbolName)
                    .font(Theme.font(13, .bold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            Text(value)
                .font(Theme.numeric(22, .heavy))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.55)
                .lineLimit(1)
            Text(label.uppercased())
                .font(Theme.micro)
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: Theme.tightRadius, style: .continuous)
                .fill(Theme.surfaceRaised.opacity(0.9))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.tightRadius, style: .continuous)
                .strokeBorder(tint.opacity(0.18), lineWidth: 1)
        }
    }
}

/// Circular progress with a glow at the leading edge, so it reads as charging
/// rather than as a pie chart.
struct ProgressRing: View {
    let fraction: Double
    var lineWidth: CGFloat = 8
    var tint: Color = Theme.accent
    var gradient: LinearGradient? = nil

    private var clamped: Double { max(0.001, min(1, fraction)) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    gradient ?? LinearGradient(colors: [tint, tint], startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.7), radius: lineWidth * 0.8)
                .animation(.spring(response: 0.6, dampingFraction: 0.75), value: clamped)
        }
    }
}

struct LinearProgress: View {
    let fraction: Double
    var tint: Color = Theme.accent
    var gradient: LinearGradient? = nil
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.08))
                Capsule()
                    .fill(gradient ?? LinearGradient(colors: [tint, tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geometry.size.width * max(0, min(1, fraction))))
                    .shadow(color: tint.opacity(0.6), radius: 5)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: fraction)
            }
        }
        .frame(height: height)
    }
}

/// The big capsule buttons. Gradient fill, springy press, optional pulse.
struct NeonButtonStyle: ButtonStyle {
    var gradient: LinearGradient = Theme.primaryGradient
    var glowColor: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(16, .bold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 22)
            .padding(.vertical, 15)
            .background(gradient, in: Capsule())
            .shadow(color: glowColor.opacity(configuration.isPressed ? 0.25 : 0.5), radius: configuration.isPressed ? 6 : 16, y: 4)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Circular glass button used for the map's secondary controls.
struct GlassButtonStyle: ButtonStyle {
    var tint: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(17, .bold))
            .foregroundStyle(tint)
            .frame(width: 50, height: 50)
            .background(Theme.surface.opacity(0.85), in: Circle())
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// A slow sweep of light across a surface. Used on locked-but-close badges and
/// on the level bar, to suggest something is nearly ready.
struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.22), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 0.6)
                    .offset(x: phase * geometry.size.width * 1.6)
                    .blendMode(.plusLighter)
                }
                .allowsHitTesting(false)
            }
            .mask(content)
            .onAppear {
                withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmering() -> some View { modifier(Shimmer()) }

    /// Standard full-screen background for non-map screens.
    func cityBackground() -> some View {
        background {
            ZStack {
                Theme.backdrop.ignoresSafeArea()
                // A faint aurora so large empty screens aren't flat black.
                RadialGradient(
                    colors: [Theme.accent.opacity(0.12), .clear],
                    center: .topTrailing,
                    startRadius: 10,
                    endRadius: 420
                )
                .ignoresSafeArea()
            }
        }
    }
}

struct EmptyStateView: View {
    let symbolName: String
    let title: String
    let message: String
    var tint: Color = Theme.accent

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 96, height: 96)
                    .blur(radius: 6)
                Image(systemName: symbolName)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
            }
            Text(title)
                .font(Theme.title)
                .foregroundStyle(.white)
            Text(message)
                .font(Theme.body)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .padding(36)
        .frame(maxWidth: .infinity)
    }
}
