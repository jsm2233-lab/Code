import Foundation

/// A normalised set of non-overlapping intervals in 0...1.
///
/// Used to track which fraction of a street segment has actually been driven or
/// walked. Intervals are kept sorted and merged, so `coveredFraction` is just a
/// sum and equality is meaningful.
struct IntervalSet: Codable, Hashable {

    /// Sub-metre slivers are noise; anything shorter than this fraction of a
    /// segment gets absorbed into its neighbour rather than stored.
    private static let epsilon = 1e-4

    private(set) var intervals: [Interval]

    struct Interval: Codable, Hashable {
        var lower: Double
        var upper: Double

        var length: Double { max(0, upper - lower) }
    }

    init(intervals: [Interval] = []) {
        self.intervals = intervals
    }

    var isEmpty: Bool { intervals.isEmpty }

    /// Total fraction of the segment covered, 0...1.
    var coveredFraction: Double {
        min(1, intervals.reduce(0) { $0 + $1.length })
    }

    /// Adds `[lower, upper]`, merging into any intervals it touches.
    mutating func insert(from lower: Double, to upper: Double) {
        var low = max(0, min(1, min(lower, upper)))
        var high = max(0, min(1, max(lower, upper)))
        guard high - low > Self.epsilon else { return }

        var merged: [Interval] = []
        var inserted = false

        for interval in intervals {
            if interval.upper < low - Self.epsilon {
                merged.append(interval)
            } else if interval.lower > high + Self.epsilon {
                if !inserted {
                    merged.append(Interval(lower: low, upper: high))
                    inserted = true
                }
                merged.append(interval)
            } else {
                low = min(low, interval.lower)
                high = max(high, interval.upper)
            }
        }

        if !inserted {
            merged.append(Interval(lower: low, upper: high))
        }

        intervals = merged.sorted { $0.lower < $1.lower }
    }

    mutating func formUnion(_ other: IntervalSet) {
        for interval in other.intervals {
            insert(from: interval.lower, to: interval.upper)
        }
    }

    func contains(_ t: Double) -> Bool {
        intervals.contains { t >= $0.lower - Self.epsilon && t <= $0.upper + Self.epsilon }
    }
}
