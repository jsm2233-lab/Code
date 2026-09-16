import Foundation

/// A single unlockable. Progress is computed on demand from the stores rather
/// than stored, so adding an achievement retroactively credits existing play.
struct Achievement: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let symbolName: String
    let tier: Tier
    /// Target value in whatever unit `progress` reports.
    let target: Double
    let kind: Kind

    enum Tier: Int, Comparable, CaseIterable {
        case bronze, silver, gold, legendary

        static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }

        var displayName: String {
            switch self {
            case .bronze: return "Bronze"
            case .silver: return "Silver"
            case .gold: return "Gold"
            case .legendary: return "Legendary"
            }
        }

        var xpReward: Int {
            switch self {
            case .bronze: return 250
            case .silver: return 750
            case .gold: return 2_000
            case .legendary: return 6_000
            }
        }
    }

    enum Kind {
        case segmentsCompleted
        case newStreetKilometres
        case streakDays
        case tileCompletion       // percent of any single tile
        case singleTripNewKm
        case distinctNamedStreets
        case nightSegments
        case walkingKilometres
    }

    static let all: [Achievement] = [
        Achievement(id: "first.street", title: "First Blood", detail: "Collect your first street.", symbolName: "flag.fill", tier: .bronze, target: 1, kind: .segmentsCompleted),
        Achievement(id: "streets.25", title: "Getting Somewhere", detail: "Collect 25 streets.", symbolName: "map.fill", tier: .bronze, target: 25, kind: .segmentsCompleted),
        Achievement(id: "streets.100", title: "Local Knowledge", detail: "Collect 100 streets.", symbolName: "building.2.fill", tier: .silver, target: 100, kind: .segmentsCompleted),
        Achievement(id: "streets.500", title: "The Knowledge", detail: "Collect 500 streets.", symbolName: "brain.head.profile", tier: .gold, target: 500, kind: .segmentsCompleted),
        Achievement(id: "streets.2000", title: "Street Sovereign", detail: "Collect 2,000 streets.", symbolName: "crown.fill", tier: .legendary, target: 2_000, kind: .segmentsCompleted),

        Achievement(id: "newkm.10", title: "Ten Fresh", detail: "Cover 10 km of streets you'd never been down.", symbolName: "sparkles", tier: .bronze, target: 10, kind: .newStreetKilometres),
        Achievement(id: "newkm.100", title: "Century of the New", detail: "Cover 100 km of new streets.", symbolName: "road.lanes", tier: .silver, target: 100, kind: .newStreetKilometres),
        Achievement(id: "newkm.1000", title: "Four Figures", detail: "Cover 1,000 km of new streets.", symbolName: "globe.europe.africa.fill", tier: .gold, target: 1_000, kind: .newStreetKilometres),

        Achievement(id: "streak.3", title: "Warming Up", detail: "Collect something new three days running.", symbolName: "flame", tier: .bronze, target: 3, kind: .streakDays),
        Achievement(id: "streak.14", title: "Fortnight", detail: "Fourteen-day collecting streak.", symbolName: "flame.fill", tier: .silver, target: 14, kind: .streakDays),
        Achievement(id: "streak.60", title: "Obsessive", detail: "Sixty-day collecting streak.", symbolName: "flame.circle.fill", tier: .legendary, target: 60, kind: .streakDays),

        Achievement(id: "tile.50", title: "Half a Neighbourhood", detail: "Reach 50% coverage in any one tile.", symbolName: "square.grid.2x2", tier: .silver, target: 50, kind: .tileCompletion),
        Achievement(id: "tile.100", title: "Clean Sweep", detail: "Fully clear a tile. Every single street.", symbolName: "checkmark.seal.fill", tier: .legendary, target: 100, kind: .tileCompletion),

        Achievement(id: "trip.newkm.5", title: "Deliberate Detour", detail: "Cover 5 km of new streets in one trip.", symbolName: "arrow.triangle.branch", tier: .bronze, target: 5, kind: .singleTripNewKm),
        Achievement(id: "trip.newkm.25", title: "Expedition", detail: "Cover 25 km of new streets in one trip.", symbolName: "figure.hiking", tier: .gold, target: 25, kind: .singleTripNewKm),

        Achievement(id: "named.250", title: "Name Dropper", detail: "Collect 250 distinctly named streets.", symbolName: "textformat.abc", tier: .silver, target: 250, kind: .distinctNamedStreets),

        Achievement(id: "night.50", title: "Night Shift", detail: "Collect 50 streets between midnight and 5am.", symbolName: "moon.stars.fill", tier: .gold, target: 50, kind: .nightSegments),

        Achievement(id: "walk.50", title: "On Foot", detail: "Collect 50 km of streets walking.", symbolName: "figure.walk.motion", tier: .silver, target: 50, kind: .walkingKilometres),
    ]

    static func byID(_ id: String) -> Achievement? {
        all.first { $0.id == id }
    }
}

/// An achievement plus where the player currently is against it.
struct AchievementProgress: Identifiable {
    let achievement: Achievement
    let value: Double
    let isUnlocked: Bool

    var id: String { achievement.id }
    var fraction: Double {
        achievement.target > 0 ? min(1, value / achievement.target) : 0
    }
}
