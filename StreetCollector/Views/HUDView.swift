import SwiftUI

/// The always-visible status strip: level, streak, what you're on right now.
struct HUDView: View {

    @EnvironmentObject private var engine: CollectionEngine
    @EnvironmentObject private var game: GameEngine
    @EnvironmentObject private var coverage: CoverageStore
    @EnvironmentObject private var location: LocationService

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                levelBadge

                VStack(alignment: .leading, spacing: 3) {
                    Text(game.profile.levelTitle)
                        .font(.subheadline.weight(.semibold))
                    LinearProgress(fraction: game.profile.levelProgress)
                    Text("\(Format.xp(game.profile.xpIntoLevel)) / \(Format.xp(game.profile.xpForNextLevel)) XP")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                if game.profile.currentStreakDays > 0 {
                    VStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(.orange)
                        Text("\(game.profile.currentStreakDays)")
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                    }
                }
            }

            if engine.isRunning {
                activeTripStrip
            } else if !location.hasAnyPermission {
                permissionPrompt
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var levelBadge: some View {
        ZStack {
            ProgressRing(fraction: game.profile.levelProgress, lineWidth: 5)
            Text("\(game.profile.level)")
                .font(.headline.weight(.heavy))
                .monospacedDigit()
        }
        .frame(width: 44, height: 44)
    }

    private var activeTripStrip: some View {
        HStack(spacing: 14) {
            Label(Format.distance(engine.activeTrip?.distanceMetres ?? 0), systemImage: "arrow.forward")
            Label(Format.distance(engine.activeTrip?.newStreetMetres ?? 0), systemImage: "sparkles")
            Label("\(engine.activeTrip?.completedSegmentIDs.count ?? 0)", systemImage: "checkmark.seal")
            Spacer()
            statusDot
        }
        .font(.caption.weight(.medium))
        .monospacedDigit()
        .lineLimit(1)
        .overlay(alignment: .bottomLeading) {
            if let segment = engine.currentSegment {
                Text(segment.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .offset(y: 14)
            }
        }
        .padding(.bottom, engine.currentSegment != nil ? 14 : 0)
    }

    private var statusDot: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColour)
                .frame(width: 7, height: 7)
            Text(engine.lastMatchQuality.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var statusColour: Color {
        switch engine.lastMatchQuality {
        case .good: return Theme.accent
        case .weak: return .orange
        case .offRoad: return .gray
        case .unknown: return .blue
        }
    }

    private var permissionPrompt: some View {
        Button {
            location.requestWhenInUse()
        } label: {
            Label("Allow location to start collecting", systemImage: "location.slash")
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Theme.accent.opacity(0.18), in: Capsule())
        }
    }
}
