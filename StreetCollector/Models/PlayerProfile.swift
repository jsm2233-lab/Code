import Foundation

/// Everything persistent about the player that isn't coverage itself.
struct PlayerProfile: Codable {
    var xp: Int
    var totalDistanceMetres: Double
    var totalNewStreetMetres: Double
    var segmentsCompleted: Int
    var currentStreakDays: Int
    var longestStreakDays: Int
    /// Day-granularity date of the last day that added a new street.
    var lastCollectionDay: Date?
    var unlockedAchievementIDs: Set<String>
    var homeTile: TileKey?

    init() {
        xp = 0
        totalDistanceMetres = 0
        totalNewStreetMetres = 0
        segmentsCompleted = 0
        currentStreakDays = 0
        longestStreakDays = 0
        lastCollectionDay = nil
        unlockedAchievementIDs = []
        homeTile = nil
    }

    var level: Int { Level.level(forXP: xp) }
    var levelTitle: String { Level.title(for: level) }
    var xpIntoLevel: Int { xp - Level.xpRequired(for: level) }
    var xpForNextLevel: Int { Level.xpRequired(for: level + 1) - Level.xpRequired(for: level) }
    var levelProgress: Double {
        let span = xpForNextLevel
        return span > 0 ? Double(xpIntoLevel) / Double(span) : 1
    }
}

/// Level curve. Quadratic, so early levels come fast and later ones take a
/// genuine amount of exploring.
enum Level {
    static let maxLevel = 60

    static func xpRequired(for level: Int) -> Int {
        guard level > 1 else { return 0 }
        let n = Double(level - 1)
        return Int(120 * n * n + 380 * n)
    }

    static func level(forXP xp: Int) -> Int {
        var level = 1
        while level < maxLevel && xp >= xpRequired(for: level + 1) {
            level += 1
        }
        return level
    }

    static func title(for level: Int) -> String {
        switch level {
        case ..<5: return "Lost Tourist"
        case ..<10: return "Wanderer"
        case ..<16: return "Pathfinder"
        case ..<23: return "Street Sweeper"
        case ..<31: return "Cartographer"
        case ..<40: return "District Warden"
        case ..<50: return "City Runner"
        case ..<60: return "Grid Master"
        default: return "Every Street"
        }
    }
}
