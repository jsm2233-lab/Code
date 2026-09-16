import SwiftUI

/// The always-visible status strip: level, streak, what you're on right now.
///
/// This sits over a live map, so it has to be readable at a glance in sunlight
/// and never take more vertical space than it has earned. It grows only while a
/// trip is running.
struct HUDView: View {

    @EnvironmentObject private var engine: CollectionEngine
    @EnvironmentObject private var game: GameEngine
    @EnvironmentObject private var location: LocationService

    var body: some View {
        GlassPanel(tint: engine.isRunning ? Theme.hot : Theme.accent, glow: engine.isRunning) {
            VStack(spacing: 12) {
                topRow

                if engine.isRunning {
                    Divider().overlay(.white.opacity(0.08))
                    activeTripStrip
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else if !location.hasAnyPermission {
                    permissionPrompt
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: engine.isRunning)
    }

    // MARK: - Level

    private var topRow: some View {
        HStack(spacing: 14) {
            levelBadge

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(game.profile.levelTitle)
                        .font(Theme.headline)
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                    Text("\(Format.xp(game.profile.xpIntoLevel))/\(Format.xp(game.profile.xpForNextLevel))")
                        .font(Theme.numeric(11, .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                }
                LinearProgress(fraction: game.profile.levelProgress, gradient: Theme.primaryGradient, height: 7)
            }

            if game.profile.currentStreakDays > 0 {
                streakBadge
            }
        }
    }

    private var levelBadge: some View {
        ZStack {
            ProgressRing(fraction: game.profile.levelProgress, lineWidth: 4, gradient: Theme.primaryGradient)
            Text("\(game.profile.level)")
                .font(Theme.numeric(19, .heavy))
                .foregroundStyle(.white)
        }
        .frame(width: 46, height: 46)
    }

    private var streakBadge: some View {
        VStack(spacing: 1) {
            Image(systemName: "flame.fill")
                .font(Theme.font(14, .bold))
                .foregroundStyle(Theme.streakGradient)
            Text("\(game.profile.currentStreakDays)")
                .font(Theme.numeric(12, .heavy))
                .foregroundStyle(.white)
        }
        .frame(width: 38, height: 42)
        .background(Theme.partial.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Theme.partial.opacity(0.3), lineWidth: 1)
        }
    }

    // MARK: - Live trip

    private var activeTripStrip: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                liveStat(
                    value: Format.distance(engine.activeTrip?.distanceMetres ?? 0),
                    label: "travelled",
                    tint: .white
                )
                divider
                liveStat(
                    value: Format.distance(engine.activeTrip?.newStreetMetres ?? 0),
                    label: "new",
                    tint: Theme.partial
                )
                divider
                liveStat(
                    value: "\(engine.activeTrip?.completedSegmentIDs.count ?? 0)",
                    label: "collected",
                    tint: Theme.accent
                )
                divider
                liveStat(
                    value: "+\(Format.xp(engine.activeTrip?.xpEarned ?? 0))",
                    label: "xp",
                    tint: Theme.hot
                )
            }

            HStack(spacing: 7) {
                statusDot
                Text(engine.currentSegment?.displayName ?? engine.lastMatchQuality.label)
                    .font(Theme.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                    .contentTransition(.opacity)
                Spacer(minLength: 0)
            }
        }
    }

    private func liveStat(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Theme.numeric(15, .heavy))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(Theme.font(8, .bold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(width: 1, height: 22)
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColour)
            .frame(width: 7, height: 7)
            .shadow(color: statusColour, radius: 4)
            .opacity(engine.lastMatchQuality == .good ? 1 : 0.6)
    }

    private var statusColour: Color {
        switch engine.lastMatchQuality {
        case .good: return Theme.accent
        case .weak: return Theme.partial
        case .offRoad: return Theme.uncollected
        case .unknown: return Theme.hot
        }
    }

    private var permissionPrompt: some View {
        Button {
            location.requestWhenInUse()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "location.slash.fill")
                Text("Allow location to start collecting")
            }
            .font(Theme.font(13, .bold))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Theme.primaryGradient, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
