import SwiftUI

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
                    ForEach(progress) { item in
                        row(for: item)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Badges")
            .task { refresh() }
            .onChange(of: coverage.completedCount) { _, _ in refresh() }
            .onChange(of: trips.trips.count) { _, _ in refresh() }
        }
    }

    private var header: some View {
        let unlocked = progress.filter(\.isUnlocked).count
        return Card {
            HStack(spacing: 16) {
                ZStack {
                    ProgressRing(
                        fraction: progress.isEmpty ? 0 : Double(unlocked) / Double(progress.count),
                        lineWidth: 9
                    )
                    Text("\(unlocked)")
                        .font(.title3.weight(.heavy))
                        .monospacedDigit()
                }
                .frame(width: 70, height: 70)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(unlocked) of \(progress.count) unlocked")
                        .font(.headline)
                    Text("Badges award bonus XP the moment they unlock.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func row(for item: AchievementProgress) -> some View {
        let tint = Theme.tierColor(item.achievement.tier)
        return Card {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(item.isUnlocked ? 0.22 : 0.08))
                    Image(systemName: item.achievement.symbolName)
                        .font(.title3)
                        .foregroundStyle(item.isUnlocked ? tint : Color.secondary.opacity(0.5))
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(item.achievement.title)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(item.achievement.tier.displayName.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(tint)
                    }
                    Text(item.achievement.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if item.isUnlocked {
                        Label("Unlocked · +\(Format.xp(item.achievement.tier.xpReward)) XP", systemImage: "checkmark.circle.fill")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(tint)
                    } else {
                        LinearProgress(fraction: item.fraction, tint: tint)
                        Text(progressLabel(for: item))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .opacity(item.isUnlocked ? 1 : 0.92)
    }

    private func progressLabel(for item: AchievementProgress) -> String {
        let value = item.value
        let target = item.achievement.target
        switch item.achievement.kind {
        case .newStreetKilometres, .singleTripNewKm, .walkingKilometres:
            return String(format: "%.1f / %.0f km", value, target)
        case .tileCompletion:
            return String(format: "%.0f%% / %.0f%%", value, target)
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
