import Foundation

/// How much of one segment the player has covered, and when.
struct SegmentCoverage: Codable, Hashable {
    let segmentID: String
    var intervals: IntervalSet
    var firstSeen: Date
    var lastSeen: Date
    /// Number of separate trips that touched this segment.
    var visitCount: Int

    /// A segment counts as collected once you've covered most of it. The
    /// threshold is deliberately below 1.0: GPS drops out under bridges and at
    /// junction approaches, and demanding 100% would make long streets feel
    /// broken.
    static let completionThreshold: Double = 0.7

    var fraction: Double { intervals.coveredFraction }
    var isComplete: Bool { fraction >= Self.completionThreshold }

    init(segmentID: String, date: Date) {
        self.segmentID = segmentID
        self.intervals = IntervalSet()
        self.firstSeen = date
        self.lastSeen = date
        self.visitCount = 0
    }
}

/// What a single location update did to the world, handed to the game engine.
struct CoverageDelta {
    let segment: StreetSegment
    /// Metres of this segment newly covered by this update.
    let newMetres: Double
    /// True if this update pushed the segment past the completion threshold.
    let completedNow: Bool
    /// True if this is the first time the segment has ever been touched.
    let firstTouch: Bool
    let fractionAfter: Double
}
