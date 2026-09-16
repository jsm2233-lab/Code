import CoreLocation
import Foundation

/// Planar geometry helpers used by the map matcher.
///
/// Everything works in a local east-north-up metre frame anchored on a
/// reference latitude. Over the few-hundred-metre distances the matcher cares
/// about, the error from ignoring earth curvature is far below GPS noise.
enum GeoMath {

    static let earthRadius: Double = 6_371_008.8

    /// Metres per degree of latitude. Constant enough for our purposes.
    static let metresPerDegreeLat: Double = .pi * earthRadius / 180.0

    /// Metres per degree of longitude at a given latitude.
    static func metresPerDegreeLon(atLatitude latitude: Double) -> Double {
        metresPerDegreeLat * cos(latitude * .pi / 180.0)
    }

    /// Great-circle distance in metres.
    static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    /// Initial bearing from `a` to `b`, in degrees clockwise from north.
    static func bearing(from a: Coordinate, to b: Coordinate) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi).truncatingRemainder(dividingBy: 360)
    }

    /// Smallest absolute difference between two bearings, in degrees (0...180).
    static func angleDelta(_ a: Double, _ b: Double) -> Double {
        var d = abs(a - b).truncatingRemainder(dividingBy: 360)
        if d > 180 { d = 360 - d }
        return d
    }

    /// Same as `angleDelta` but treats a heading and its reverse as equal,
    /// because a two-way street is the same street in either direction.
    static func undirectedAngleDelta(_ a: Double, _ b: Double) -> Double {
        let d = angleDelta(a, b)
        return min(d, 180 - d)
    }

    /// Projects `point` onto the segment `a`-`b`.
    ///
    /// Returns the perpendicular distance in metres and the position along the
    /// segment as a fraction in 0...1, clamped to the endpoints.
    static func project(
        point: Coordinate,
        onto a: Coordinate,
        _ b: Coordinate
    ) -> (distance: Double, t: Double) {
        let mLat = metresPerDegreeLat
        let mLon = metresPerDegreeLon(atLatitude: a.latitude)

        let ax = 0.0, ay = 0.0
        let bx = (b.longitude - a.longitude) * mLon
        let by = (b.latitude - a.latitude) * mLat
        let px = (point.longitude - a.longitude) * mLon
        let py = (point.latitude - a.latitude) * mLat

        let dx = bx - ax, dy = by - ay
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 1e-9 else {
            return (sqrt(px * px + py * py), 0)
        }

        let t = max(0, min(1, (px * dx + py * dy) / lengthSquared))
        let cx = t * dx, cy = t * dy
        let distance = sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy))
        return (distance, t)
    }

    /// Linear interpolation between two coordinates.
    static func interpolate(_ a: Coordinate, _ b: Coordinate, _ t: Double) -> Coordinate {
        Coordinate(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t
        )
    }

    /// Total length of a polyline in metres.
    static func polylineLength(_ points: [Coordinate]) -> Double {
        guard points.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<points.count {
            total += distance(points[i - 1], points[i])
        }
        return total
    }
}
