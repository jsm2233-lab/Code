import SwiftUI

/// The badge case. Unlocked badges are lit and gradient-filled; locked ones are
/// desaturated with their progress showing, and the nearly-finished ones
/// shimmer so you can see what's within reach.
struct AchievementsScreen: View {

    @EnvironmentObject private var game: GameEngine
    @EnvironmentObject private var coverage: CoverageStore
    @EnvironmentObject private var data: StreetDataStore
    @EnvironmentObject private var trips: TripStore
    @EnvironmentObject private var engine: CollectionEngine

    @State private var progress: [AchievementProgress] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    header

                    ForEach(Achievement.Tier.allCases.reversed(), id: \.rawValue) { tier in
                        let items = progress.filter { $0.achievement.tier == tier }
                        if !items.isEmpty {
                            tierHeading(tier, items: items)
                            ForEach(items) { item in
                                row(for: item)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .cityBackground()
            .navigationTitle("Badges")
            .task { refresh() }
            .onChange(of: coverage.completedCount) { _, _ in refresh() }
            .onChange(of: trips.trips.count) { _, _ in refresh() }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        let unlocked = progress.filter(\.isUnlocked).count
        let fraction = progress.isEmpty ? 0 : Double(unlocked) / Double(progress.count)

        return GlassPanel(tint: Theme.violet, glow: unlocked > 0) {
            HStack(spacing: 18) {
                ZStack {
                    ProgressRing(fraction: fraction, lineWidth: 7, tint: Theme.violet, gradient: Theme.legendaryGradient)
                    VStack(spacing: -2) {
                        Text("\(unlocked)")
                            .font(Theme.numeric(24, .heavy))
                            .foregroundStyle(.white)
                        Text("of \(progress.count)")
                            .font(Theme.font(9, .bold))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .frame(width: 76, height: 76)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Badge case")
                        .font(Theme.title)
                        .foregroundStyle(.white)
                    Text("Each one pays a lump of XP the moment it unlocks. Progress counts everything you've already collected.")
                        .font(Theme.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func tierHeading(_ tier: Achievement.Tier, items: [AchievementProgress]) -> some View {
        HStack(spacing: 8) {
            Text(tier.displayName.uppercased())
                .font(Theme.micro)
                .tracking(2)
                .foregroundStyle(Theme.tierColor(tier))
            Rectangle()
                .fill(Theme.tierColor(tier).opacity(0.25))
                .frame(height: 1)
            Text("\(items.filter(\.isUnlocked).count)/\(items.count)")
                .font(Theme.numeric(11, .bold))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.top, 10)
    }

    private func row(for item: AchievementProgress) -> some View {
        let tint = Theme.tierColor(item.achievement.tier)
        // Anything past three quarters gets a shimmer: it's the "you're nearly
        // there" nudge, and it would be noise on everything.
        let nearlyThere = !item.isUnlocked && item.fraction >= 0.75

        return GlassPanel(tint: tint, glow: item.isUnlocked) {
            HStack(alignment: .top, spacing: 14) {
                medal(for: item, tint: tint)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.achievement.title)
                            .font(Theme.font(15, .bold))
                            .foregroundStyle(item.isUnlocked ? .white : .white.opacity(0.75))
                        Spacer(minLength: 6)
                        Text("+\(Format.xp(item.achievement.tier.xpReward))")
                            .font(Theme.numeric(11, .heavy))
                            .foregroundStyle(item.isUnlocked ? tint : .white.opacity(0.3))
                    }

                    Text(item.achievement.detail)
                        .font(Theme.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)

                    if item.isUnlocked {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.seal.fill")
                            Text("Unlocked")
                        }
                        .font(Theme.font(11, .bold))
                        .foregroundStyle(tint)
                    } else {
                        VStack(alignment: .leading, spacing: 5) {
                            LinearProgress(fraction: item.fraction, tint: tint, height: 6)
                            Text(progressLabel(for: item))
                                .font(Theme.numeric(10, .semibold))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }
            }
        }
        .modifier(ConditionalShimmer(active: nearlyThere))
    }

    private func medal(for item: AchievementProgress, tint: Color) -> some View {
        ZStack {
            Circle()
                .fill(item.isUnlocked ? AnyShapeStyle(Theme.gradient(for: item.achievement.tier)) : AnyShapeStyle(Color.white.opacity(0.06)))
                .frame(width: 50, height: 50)
                .shadow(color: item.isUnlocked ? tint.opacity(0.5) : .clear, radius: 12)

            Image(systemName: item.achievement.symbolName)
                .font(Theme.font(19, .bold))
                .foregroundStyle(item.isUnlocked ? Theme.ink : .white.opacity(0.28))

            if !item.isUnlocked {
                Circle()
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                    .frame(width: 50, height: 50)
            }
        }
    }

    private func progressLabel(for item: AchievementProgress) -> String {
        let value = item.value
        let target = item.achievement.target
        switch item.achievement.kind {
        case .newStreetKilometres, .singleTripNewKm, .walkingKilometres:
            return String(format: "%.1f / %.0f km", value, target)
        case .tileCompletion:
            return String(format: "%.0f%% / %.0f%% of an area", value, target)
        case .streakDays:
            return "\(Int(value)) / \(Int(target)) days"
        default:
            return "\(Int(value)) / \(Int(target))"
        }
    }

    private func refresh() {
        progress = game.progressList(
            coverage: coverage,
            data: data,
            trips: trips.trips,
            bestTileCompletion: engine.bestTileCompletionPercent()
        )
    }
}

/// Applies the shimmer only when a badge is close, without branching the view
/// tree (which would reset its identity and restart animations).
private struct ConditionalShimmer: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.shimmering()
        } else {
            content
        }
    }
}
