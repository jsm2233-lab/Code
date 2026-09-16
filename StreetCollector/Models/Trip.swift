import Foundation

/// One continuous recording session.
struct Trip: Codable, Identifiable, Hashable {
    let id: UUID
    var startedAt: Date
    var endedAt: Date?
    var distanceMetres: Double
    var newStreetMetres: Double
    var newSegmentIDs: [String]
    var completedSegmentIDs: [String]
    var xpEarned: Int
    var mode: TravelMode
    /// Decimated track for drawing the trip back on a map.
    var track: [Coordinate]

    var duration: TimeInterval {
        (endedAt ?? Date()).timeIntervalSince(startedAt)
    }

    var isActive: Bool { endedAt == nil }

    var averageSpeed: Double {
        duration > 1 ? distanceMetres / duration : 0
    }

    /// Share of the trip spent on streets you'd never been down before.
    var noveltyRatio: Double {
        distanceMetres > 1 ? min(1, newStreetMetres / distanceMetres) : 0
    }

    init(id: UUID = UUID(), startedAt: Date = Date(), mode: TravelMode = .unknown) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = nil
        self.distanceMetres = 0
        self.newStreetMetres = 0
        self.newSegmentIDs = []
        self.completedSegmentIDs = []
        self.xpEarned = 0
        self.mode = mode
        self.track = []
    }
}

enum TravelMode: String, Codable, CaseIterable {
    case walking
    case cycling
    case driving
    case unknown

    /// Inferred from speed alone. Deliberately crude — it only affects flavour
    /// text and the walking-specific achievements, not scoring.
    static func inferred(fromSpeed metresPerSecond: Double) -> TravelMode {
        switch metresPerSecond {
        case ..<0: return .unknown
        case ..<2.2: return .walking
        case ..<7.0: return .cycling
        default: return .driving
        }
    }

    var symbolName: String {
        switch self {
        case .walking: return "figure.walk"
        case .cycling: return "bicycle"
        case .driving: return "car.fill"
        case .unknown: return "location.fill"
        }
    }

    var displayName: String {
        switch self {
        case .walking: return "Walk"
        case .cycling: return "Ride"
        case .driving: return "Drive"
        case .unknown: return "Trip"
        }
    }
}
