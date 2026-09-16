import Foundation

/// Scoring, levelling, streaks and achievement checks.
@MainActor
final class GameEngine: ObservableObject {

    @Published private(set) var profile = PlayerProfile()
    /// Transient, for the HUD's floating "+120 XP" popups.
    @Published private(set) var recentEvents: [ScoreEvent] = []
    @Published private(set) var pendingUnlocks: [Achievement] = []

    private let store: FileStore
    private static let fileName = "profile.json"
    private var saveTask: Task<Void, Never>?

    /// Base XP per metre of genuinely new street. A 200 m residential street is
    /// worth ~28 XP plus the completion bonus.
    private static let xpPerNewMetre: Double = 0.1
    /// Flat bonus for finishing a segment end to end.
    private static let completionBonus: Double = 40

    struct ScoreEvent: Identifiable {
        let id = UUID()
        let title: String
        let xp: Int
        let symbolName: String
        let date: Date
    }

    init(store: FileStore = .shared) {
        self.store = store
        if let saved = store.load(PlayerProfile.self, from: Self.fileName) {
            profile = saved
        }
    }

    // MARK: - Scoring

    /// Scores one coverage delta and returns the XP awarded.
    @discardableResult
    func award(for delta: CoverageDelta, mode: TravelMode, at date: Date) -> Int {
        var xp = delta.newMetres * Self.xpPerNewMetre * delta.segment.classification.scoreMultiplier

        if delta.completedNow {
            xp += Self.completionBonus * delta.segment.classification.scoreMultiplier
        }
        // Walking a street is slower and more deliberate than driving it.
        if mode == .walking {
            xp *= 1.25
        }
        // Late-night collecting is its own small reward.
        if Calendar.current.component(.hour, from: date) < 5 {
            xp *= 1.15
        }

        let awarded = Int(xp.rounded())
        guard awarded > 0 else { return 0 }

        profile.xp += awarded
        profile.totalNewStreetMetres += delta.newMetres
        if delta.completedNow {
            profile.segmentsCompleted += 1
            pushEvent(
                ScoreEvent(
                    title: delta.segment.displayName,
                    xp: awarded,
                    symbolName: "checkmark.circle.fill",
                    date: date
                )
            )
        }

        updateStreak(for: date)
        scheduleSave()
        return awarded
    }

    func addDistance(_ metres: Double) {
        guard metres > 0 else { return }
        profile.totalDistanceMetres += metres
        scheduleSave()
    }

    func setHomeTile(_ tile: TileKey) {
        guard profile.homeTile == nil else { return }
        profile.homeTile = tile
        scheduleSave()
    }

    // MARK: - Streaks

    private func updateStreak(for date: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)

        guard let last = profile.lastCollectionDay else {
            profile.currentStreakDays = 1
            profile.longestStreakDays = max(1, profile.longestStreakDays)
            profile.lastCollectionDay = today
            return
        }

        let lastDay = calendar.startOfDay(for: last)
        guard today != lastDay else { return }

        let days = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
        profile.currentStreakDays = days == 1 ? profile.currentStreakDays + 1 : 1
        profile.longestStreakDays = max(profile.longestStreakDays, profile.currentStreakDays)
        profile.lastCollectionDay = today
    }

    /// Streaks decay in real time, not just when you collect something, so the
    /// HUD shouldn't claim a 12-day streak you broke last Tuesday.
    func refreshStreak(now: Date = Date()) {
        guard let last = profile.lastCollectionDay else { return }
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: last),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        if days > 1 && profile.currentStreakDays != 0 {
            profile.currentStreakDays = 0
            scheduleSave()
        }
    }

    // MARK: - Achievements

    /// Recomputes every achievement from current state. Cheap enough to run
    /// after each trip, and it means new achievements credit past play.
    @discardableResult
    func evaluateAchievements(
        coverage: CoverageStore,
        data: StreetDataStore,
        trips: [Trip],
        bestTileCompletion: Double
    ) -> [Achievement] {
        var unlocked: [Achievement] = []

        for achievement in Achievement.all {
            guard !profile.unlockedAchievementIDs.contains(achievement.id) else { continue }
            let value = progressValue(
                for: achievement,
                coverage: coverage,
                data: data,
                trips: trips,
                bestTileCompletion: bestTileCompletion
            )
            if value >= achievement.target {
                profile.unlockedAchievementIDs.insert(achievement.id)
                profile.xp += achievement.tier.xpReward
                unlocked.append(achievement)
                pushEvent(
                    ScoreEvent(
                        title: achievement.title,
                        xp: achievement.tier.xpReward,
                        symbolName: achievement.symbolName,
                        date: Date()
                    )
                )
            }
        }

        if !unlocked.isEmpty {
            pendingUnlocks.append(contentsOf: unlocked)
            scheduleSave()
        }
        return unlocked
    }

    func progressList(
        coverage: CoverageStore,
        data: StreetDataStore,
        trips: [Trip],
        bestTileCompletion: Double
    ) -> [AchievementProgress] {
        Achievement.all.map { achievement in
            AchievementProgress(
                achievement: achievement,
                value: progressValue(
                    for: achievement,
                    coverage: coverage,
                    data: data,
                    trips: trips,
                    bestTileCompletion: bestTileCompletion
                ),
                isUnlocked: profile.unlockedAchievementIDs.contains(achievement.id)
            )
        }
        .sorted { lhs, rhs in
            if lhs.isUnlocked != rhs.isUnlocked { return !lhs.isUnlocked }
            return lhs.fraction > rhs.fraction
        }
    }

    private func progressValue(
        for achievement: Achievement,
        coverage: CoverageStore,
        data: StreetDataStore,
        trips: [Trip],
        bestTileCompletion: Double
    ) -> Double {
        switch achievement.kind {
        case .segmentsCompleted:
            return Double(coverage.completedCount)
        case .newStreetKilometres:
            return profile.totalNewStreetMetres / 1_000
        case .streakDays:
            return Double(profile.currentStreakDays)
        case .tileCompletion:
            return bestTileCompletion
        case .singleTripNewKm:
            return (trips.map(\.newStreetMetres).max() ?? 0) / 1_000
        case .distinctNamedStreets:
            return Double(coverage.distinctNamedStreetCount(in: data))
        case .nightSegments:
            return Double(coverage.nightCollectedCount)
        case .walkingKilometres:
            return trips.filter { $0.mode == .walking }
                .reduce(0) { $0 + $1.newStreetMetres } / 1_000
        }
    }

    func consumePendingUnlocks() -> [Achievement] {
        let unlocks = pendingUnlocks
        pendingUnlocks.removeAll()
        return unlocks
    }

    // MARK: - Lifecycle

    func reset() {
        profile = PlayerProfile()
        recentEvents.removeAll()
        pendingUnlocks.removeAll()
        store.delete(Self.fileName)
    }

    private func pushEvent(_ event: ScoreEvent) {
        recentEvents.append(event)
        if recentEvents.count > 8 {
            recentEvents.removeFirst(recentEvents.count - 8)
        }
    }

    func expireEvents(olderThan interval: TimeInterval = 4) {
        let cutoff = Date().addingTimeInterval(-interval)
        recentEvents.removeAll { $0.date < cutoff }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    func flush() {
        store.save(profile, to: Self.fileName)
    }
}
