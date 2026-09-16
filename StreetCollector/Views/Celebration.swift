import SwiftUI

/// Full-screen moment for a level-up or a badge unlock.
///
/// It is deliberately short and always dismissible by tapping anywhere: this
/// fires while people are driving or walking, so it must never be something you
/// have to deal with.
struct CelebrationOverlay: View {

    @EnvironmentObject private var game: GameEngine
    @State private var appeared = false

    var body: some View {
        ZStack {
            if let celebration = game.celebration {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .transition(.opacity)

                ConfettiView(tint: tint(for: celebration))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                card(for: celebration)
                    .padding(.horizontal, 36)
                    .scaleEffect(appeared ? 1 : 0.7)
                    .opacity(appeared ? 1 : 0)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: game.celebration)
        .onTapGesture { dismiss() }
        .onChange(of: game.celebration) { _, celebration in
            guard celebration != nil else {
                appeared = false
                return
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { appeared = true }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            // Auto-dismiss: the map is the point, not this.
            Task {
                try? await Task.sleep(nanoseconds: 4_500_000_000)
                dismiss()
            }
        }
    }

    private func dismiss() {
        appeared = false
        game.dismissCelebration()
    }

    private func tint(for celebration: GameEngine.Celebration) -> Color {
        switch celebration {
        case .levelUp: return Theme.accent
        case .badge(_, _, _, _, let tier): return Theme.tierColor(tier)
        }
    }

    private func gradient(for celebration: GameEngine.Celebration) -> LinearGradient {
        switch celebration {
        case .levelUp: return Theme.primaryGradient
        case .badge(_, _, _, _, let tier): return Theme.gradient(for: tier)
        }
    }

    @ViewBuilder
    private func card(for celebration: GameEngine.Celebration) -> some View {
        let accent = tint(for: celebration)

        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.22))
                    .frame(width: 130, height: 130)
                    .blur(radius: 14)
                Circle()
                    .fill(gradient(for: celebration))
                    .frame(width: 96, height: 96)
                    .shadow(color: accent.opacity(0.6), radius: 24)

                switch celebration {
                case .levelUp(let level, _):
                    Text("\(level)")
                        .font(Theme.numeric(44, .heavy))
                        .foregroundStyle(Theme.ink)
                case .badge(_, _, _, let symbol, _):
                    Image(systemName: symbol)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                }
            }
            .rotationEffect(.degrees(appeared ? 0 : -25))

            VStack(spacing: 8) {
                Text(headline(for: celebration).uppercased())
                    .font(Theme.micro)
                    .tracking(2)
                    .foregroundStyle(accent)

                Text(title(for: celebration))
                    .font(Theme.display)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                if let detail = detail(for: celebration) {
                    Text(detail)
                        .font(Theme.body)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
            }

            Text("Tap to carry on")
                .font(Theme.caption)
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(28)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Theme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(accent.opacity(0.4), lineWidth: 1)
                }
        }
        .shadow(color: accent.opacity(0.3), radius: 30)
    }

    private func headline(for celebration: GameEngine.Celebration) -> String {
        switch celebration {
        case .levelUp: return "Level up"
        case .badge(_, _, _, _, let tier): return "\(tier.displayName) badge"
        }
    }

    private func title(for celebration: GameEngine.Celebration) -> String {
        switch celebration {
        case .levelUp(_, let title): return title
        case .badge(_, let title, _, _, _): return title
        }
    }

    private func detail(for celebration: GameEngine.Celebration) -> String? {
        switch celebration {
        case .levelUp(let level, _): return "You've reached level \(level)."
        case .badge(_, _, let detail, _, _): return detail
        }
    }
}

/// Canvas-drawn confetti.
///
/// One `Canvas` inside a `TimelineView` draws every particle, rather than a
/// few hundred SwiftUI views — the difference between smooth and a slideshow on
/// an older phone.
struct ConfettiView: View {

    var tint: Color = Theme.accent
    var count: Int = 90

    private struct Particle {
        let x: Double           // 0...1 across the width
        let delay: Double
        let duration: Double
        let drift: Double
        let spin: Double
        let size: Double
        let hue: Int
    }

    private let particles: [Particle]
    private let palette: [Color] = [Theme.accent, Theme.hot, Theme.partial, Theme.magenta, Theme.violet]

    init(tint: Color = Theme.accent, count: Int = 90) {
        self.tint = tint
        self.count = count
        var generator = SystemRandomNumberGenerator()
        particles = (0..<count).map { _ in
            Particle(
                x: Double.random(in: 0...1, using: &generator),
                delay: Double.random(in: 0...0.9, using: &generator),
                duration: Double.random(in: 1.9...3.4, using: &generator),
                drift: Double.random(in: -80...80, using: &generator),
                spin: Double.random(in: -5...5, using: &generator),
                size: Double.random(in: 5...11, using: &generator),
                hue: Int.random(in: 0...4, using: &generator)
            )
        }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate

                for particle in particles {
                    let elapsed = now.truncatingRemainder(dividingBy: 6) - particle.delay
                    guard elapsed > 0, elapsed < particle.duration else { continue }

                    let progress = elapsed / particle.duration
                    let y = -30 + progress * (size.height + 60)
                    let x = particle.x * size.width + sin(progress * .pi * 2) * particle.drift
                    // Fade out over the last third so they don't pile up at the
                    // bottom edge.
                    let opacity = progress > 0.66 ? (1 - progress) * 3 : 1

                    var rectangle = Path(
                        roundedRect: CGRect(
                            x: -particle.size / 2,
                            y: -particle.size / 2,
                            width: particle.size,
                            height: particle.size * 1.6
                        ),
                        cornerRadius: 1.5
                    )
                    rectangle = rectangle.applying(
                        CGAffineTransform(rotationAngle: progress * particle.spin * .pi)
                    )
                    rectangle = rectangle.applying(CGAffineTransform(translationX: x, y: y))

                    context.fill(
                        rectangle,
                        with: .color(palette[particle.hue].opacity(opacity))
                    )
                }
            }
        }
    }
}
