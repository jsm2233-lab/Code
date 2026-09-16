import CoreLocation
import Foundation

/// Snaps raw GPS fixes onto street segments.
///
/// This is the heart of the app. A naive "nearest polyline" match produces a
/// mess on dual carriageways, at junctions and beside parallel service roads,
/// so matching is scored on three things: perpendicular distance, agreement
/// between the fix's course and the road's bearing, and stickiness toward the
/// segment we matched last. Stickiness is what stops the match flickering
/// between a road and the cycle path running alongside it.
struct MapMatcher {

    struct Configuration {
        /// Fixes worse than this are thrown away outright.
        var maxHorizontalAccuracy: Double = 40
        /// Search radius floor; the real radius also scales with the fix's own
        /// reported accuracy.
        var baseSearchRadius: Double = 25
        /// Beyond this score a candidate is rejected and the fix goes unmatched.
        var maxAcceptableScore: Double = 60
        /// Metres of score subtracted for staying on the previously matched
        /// segment or one of its neighbours.
        var stickinessBonus: Double = 18
        /// Heading disagreement is converted to metres of penalty at this rate.
        var headingPenaltyPerDegree: Double = 0.7
        /// A course is only trusted above this speed; below it the reported
        /// course is mostly noise.
        var minimumSpeedForHeading: Double = 1.5
        /// Don't bridge coverage across a gap longer than this.
        var maxBridgeInterval: TimeInterval = 25
        /// Don't bridge coverage across a jump longer than this.
        var maxBridgeDistance: Double = 250

        static let `default` = Configuration()
    }

    struct Match {
        let segment: StreetSegment
        /// Position along the segment, 0...1.
        let t: Double
        let perpendicularDistance: Double
        let score: Double
        let timestamp: Date
    }

    /// The result of feeding one fix in: which segment intervals to mark, and
    /// whether the fix was usable at all.
    struct Result {
        var match: Match?
        /// Segment id -> newly traversed interval, ready for the coverage store.
        var traversal: (segment: StreetSegment, lower: Double, upper: Double)?
        var rejectedReason: RejectionReason?
    }

    enum RejectionReason {
        case poorAccuracy
        case noCandidates
        case noConfidentMatch
    }

    var configuration: Configuration
    private let index: SpatialIndex
    private var previous: Match?

    init(index: SpatialIndex, configuration: Configuration = .default) {
        self.index = index
        self.configuration = configuration
    }

    mutating func reset() {
        previous = nil
    }

    mutating func process(_ location: CLLocation) -> Result {
        guard location.horizontalAccuracy > 0,
              location.horizontalAccuracy <= configuration.maxHorizontalAccuracy else {
            return Result(match: nil, traversal: nil, rejectedReason: .poorAccuracy)
        }

        let point = Coordinate(location.coordinate)
        let radius = max(configuration.baseSearchRadius, location.horizontalAccuracy * 1.5)
        let candidates = index.candidates(near: point, radius: radius)
        guard !candidates.isEmpty else {
            previous = nil
            return Result(match: nil, traversal: nil, rejectedReason: .noCandidates)
        }

        let heading: Double? = location.course >= 0
            && location.speed >= configuration.minimumSpeedForHeading ? location.course : nil

        var best: Match?
        for segment in candidates {
            guard let scored = score(segment: segment, point: point, heading: heading, timestamp: location.timestamp) else {
                continue
            }
            if best == nil || scored.score < best!.score {
                best = scored
            }
        }

        guard let match = best, match.score <= configuration.maxAcceptableScore else {
            previous = nil
            return Result(match: nil, traversal: nil, rejectedReason: .noConfidentMatch)
        }

        let traversal = traversalInterval(to: match, from: previous, accuracy: location.horizontalAccuracy)
        previous = match
        return Result(match: match, traversal: traversal, rejectedReason: nil)
    }

    private func score(
        segment: StreetSegment,
        point: Coordinate,
        heading: Double?,
        timestamp: Date
    ) -> Match? {
        guard segment.points.count > 1 else { return nil }

        var bestDistance = Double.greatestFiniteMagnitude
        var bestT = 0.0
        var travelled = 0.0
        var bestLocalBearing = 0.0

        for i in 1..<segment.points.count {
            let a = segment.points[i - 1]
            let b = segment.points[i]
            let step = GeoMath.distance(a, b)
            let projection = GeoMath.project(point: point, onto: a, b)
            if projection.distance < bestDistance {
                bestDistance = projection.distance
                bestT = segment.length > 0 ? (travelled + projection.t * step) / segment.length : 0
                bestLocalBearing = GeoMath.bearing(from: a, to: b)
            }
            travelled += step
        }

        var total = bestDistance

        if let heading {
            // One-way streets can be penalised directionally; two-way streets
            // are equally valid in either direction.
            let delta = segment.isOneWay
                ? GeoMath.angleDelta(heading, bestLocalBearing)
                : GeoMath.undirectedAngleDelta(heading, bestLocalBearing)
            total += delta * configuration.headingPenaltyPerDegree
        }

        if let previous, previous.segment.id == segment.id {
            total -= configuration.stickinessBonus
        } else if let previous, sharesEndpoint(previous.segment, segment) {
            // A segment we could plausibly have turned onto gets a smaller
            // bonus, so junctions hand off cleanly instead of snapping back.
            total -= configuration.stickinessBonus * 0.5
        }

        return Match(
            segment: segment,
            t: max(0, min(1, bestT)),
            perpendicularDistance: bestDistance,
            score: total,
            timestamp: timestamp
        )
    }

    private func sharesEndpoint(_ a: StreetSegment, _ b: StreetSegment) -> Bool {
        guard let aStart = a.points.first, let aEnd = a.points.last,
              let bStart = b.points.first, let bEnd = b.points.last else { return false }
        let tolerance = 12.0
        return GeoMath.distance(aStart, bStart) < tolerance
            || GeoMath.distance(aStart, bEnd) < tolerance
            || GeoMath.distance(aEnd, bStart) < tolerance
            || GeoMath.distance(aEnd, bEnd) < tolerance
    }

    /// Works out what stretch of road this fix proves we covered.
    ///
    /// Two fixes on the same segment mean everything between them was
    /// traversed. A single fix only proves we were within GPS error of one
    /// point, so it marks a small window instead.
    private func traversalInterval(
        to match: Match,
        from previous: Match?,
        accuracy: Double
    ) -> (segment: StreetSegment, lower: Double, upper: Double)? {
        let segment = match.segment
        guard segment.length > 1 else { return nil }

        if let previous, previous.segment.id == segment.id {
            let gap = match.timestamp.timeIntervalSince(previous.timestamp)
            let jump = abs(match.t - previous.t) * segment.length
            if gap <= configuration.maxBridgeInterval && jump <= configuration.maxBridgeDistance {
                return (segment, min(previous.t, match.t), max(previous.t, match.t))
            }
        }

        let window = max(6, accuracy * 0.5) / segment.length
        return (segment, match.t - window, match.t + window)
    }
}
