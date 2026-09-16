import Foundation
import MapKit

/// One stretch of road, as imported from OpenStreetMap.
///
/// An OSM way is split at every intersection during import, so a segment is
/// always intersection-to-intersection. That matters for scoring: "collected
/// Baker Street" should mean you actually drove the whole thing, not that you
/// clipped one end of a 4 km way.
struct StreetSegment: Codable, Identifiable, Hashable {

    let id: String
    let name: String?
    let classification: StreetClassification
    let points: [Coordinate]
    /// Length in metres, precomputed at import.
    let length: Double
    let isOneWay: Bool
    /// Tile this segment was imported with; used for cache eviction.
    let tile: TileKey

    var displayName: String {
        name ?? classification.unnamedLabel
    }

    /// Bearing of the segment as a whole, used as a cheap direction gate.
    var overallBearing: Double {
        guard let first = points.first, let last = points.last else { return 0 }
        return GeoMath.bearing(from: first, to: last)
    }

    var boundingBox: BoundingBox {
        BoundingBox(points: points)
    }

    func coordinate(atFraction t: Double) -> Coordinate {
        guard points.count > 1 else { return points.first ?? Coordinate(latitude: 0, longitude: 0) }
        let target = max(0, min(1, t)) * length
        var travelled = 0.0
        for i in 1..<points.count {
            let step = GeoMath.distance(points[i - 1], points[i])
            if travelled + step >= target {
                let local = step > 0 ? (target - travelled) / step : 0
                return GeoMath.interpolate(points[i - 1], points[i], local)
            }
            travelled += step
        }
        return points[points.count - 1]
    }

    /// The sub-polyline covering `from...to` in segment fractions, for drawing
    /// partial progress on the map.
    func polyline(from lower: Double, to upper: Double) -> [Coordinate] {
        guard points.count > 1, upper > lower else { return [] }
        let startDistance = max(0, min(1, lower)) * length
        let endDistance = max(0, min(1, upper)) * length

        var result: [Coordinate] = [coordinate(atFraction: lower)]
        var travelled = 0.0
        for i in 1..<points.count {
            let step = GeoMath.distance(points[i - 1], points[i])
            let vertexDistance = travelled + step
            if vertexDistance > startDistance && vertexDistance < endDistance {
                result.append(points[i])
            }
            travelled = vertexDistance
            if travelled >= endDistance { break }
        }
        result.append(coordinate(atFraction: upper))
        return result
    }
}

/// OSM highway classes, collapsed into the handful that change how we score or
/// draw a street.
enum StreetClassification: String, Codable, CaseIterable {
    case motorway
    case trunk
    case primary
    case secondary
    case tertiary
    case residential
    case living
    case service
    case pedestrian
    case track
    case path

    init?(osmHighway: String) {
        switch osmHighway {
        case "motorway", "motorway_link": self = .motorway
        case "trunk", "trunk_link": self = .trunk
        case "primary", "primary_link": self = .primary
        case "secondary", "secondary_link": self = .secondary
        case "tertiary", "tertiary_link": self = .tertiary
        case "residential", "unclassified": self = .residential
        case "living_street": self = .living
        case "service": self = .service
        case "pedestrian", "footway", "steps": self = .pedestrian
        case "track": self = .track
        case "path", "cycleway", "bridleway": self = .path
        default: return nil
        }
    }

    var unnamedLabel: String {
        switch self {
        case .motorway: return "Unnamed motorway"
        case .trunk: return "Unnamed trunk road"
        case .primary, .secondary, .tertiary: return "Unnamed road"
        case .residential, .living: return "Unnamed street"
        case .service: return "Service road"
        case .pedestrian: return "Footpath"
        case .track: return "Track"
        case .path: return "Path"
        }
    }

    /// Multiplier on the XP earned per metre. Backstreets are worth more than
    /// motorway because the whole point is exploring the fiddly bits.
    var scoreMultiplier: Double {
        switch self {
        case .motorway, .trunk: return 0.5
        case .primary: return 0.8
        case .secondary, .tertiary: return 1.0
        case .residential, .living: return 1.4
        case .service: return 0.7
        case .pedestrian, .path: return 1.2
        case .track: return 1.0
        }
    }

    /// Whether this class counts toward the headline "streets collected" score.
    /// Service roads and footpaths are collectible but don't dilute the
    /// city-completion percentage.
    var countsTowardCompletion: Bool {
        switch self {
        case .service, .pedestrian, .path, .track: return false
        default: return true
        }
    }

    var displayName: String {
        switch self {
        case .motorway: return "Motorway"
        case .trunk: return "Trunk road"
        case .primary: return "Primary road"
        case .secondary: return "Secondary road"
        case .tertiary: return "Tertiary road"
        case .residential: return "Residential street"
        case .living: return "Living street"
        case .service: return "Service road"
        case .pedestrian: return "Pedestrian way"
        case .track: return "Track"
        case .path: return "Path"
        }
    }
}

struct BoundingBox: Codable, Hashable {
    var minLatitude: Double
    var minLongitude: Double
    var maxLatitude: Double
    var maxLongitude: Double

    init(points: [Coordinate]) {
        minLatitude = points.map(\.latitude).min() ?? 0
        maxLatitude = points.map(\.latitude).max() ?? 0
        minLongitude = points.map(\.longitude).min() ?? 0
        maxLongitude = points.map(\.longitude).max() ?? 0
    }

    func expanded(byMetres metres: Double) -> BoundingBox {
        var box = self
        let dLat = metres / GeoMath.metresPerDegreeLat
        let dLon = metres / max(1, GeoMath.metresPerDegreeLon(atLatitude: minLatitude))
        box.minLatitude -= dLat
        box.maxLatitude += dLat
        box.minLongitude -= dLon
        box.maxLongitude += dLon
        return box
    }

    func contains(_ coordinate: Coordinate) -> Bool {
        coordinate.latitude >= minLatitude && coordinate.latitude <= maxLatitude
            && coordinate.longitude >= minLongitude && coordinate.longitude <= maxLongitude
    }
}
