import Foundation
import os

/// The player's collection: which parts of which segments have been travelled.
@MainActor
final class CoverageStore: ObservableObject {

    /// Bumped whenever coverage changes, so map overlays can invalidate without
    /// diffing tens of thousands of segments.
    @Published private(set) var revision: Int = 0
    @Published private(set) var completedCount: Int = 0
    @Published private(set) var touchedCount: Int = 0

    private var coverage: [String: SegmentCoverage] = [:]
    private let store: FileStore
    private let logger = Logger(subsystem: "com.example.StreetCollector", category: "Coverage")
    private var saveTask: Task<Void, Never>?
    private static let fileName = "coverage.json"

    init(store: FileStore = .shared) {
        self.store = store
        load()
    }

    // MARK: - Reads

    func coverage(for segmentID: String) -> SegmentCoverage? {
        coverage[segmentID]
    }

    func fraction(for segmentID: String) -> Double {
        coverage[segmentID]?.fraction ?? 0
    }

    func isComplete(_ segmentID: String) -> Bool {
        coverage[segmentID]?.isComplete ?? false
    }

    var all: [SegmentCoverage] { Array(coverage.values) }

    var completedSegmentIDs: Set<String> {
        Set(coverage.values.filter(\.isComplete).map(\.segmentID))
    }

    // MARK: - Writes

    /// Records a traversal and reports what changed, so the game engine can
    /// award XP without recomputing anything.
    func record(
        segment: StreetSegment,
        from lower: Double,
        to upper: Double,
        at date: Date
    ) -> CoverageDelta? {
        var entry = coverage[segment.id] ?? SegmentCoverage(segmentID: segment.id, date: date)
        let firstTouch = coverage[segment.id] == nil
        let fractionBefore = entry.fraction
        let wasComplete = entry.isComplete

        entry.intervals.insert(from: lower, to: upper)
        entry.lastSeen = date
        if firstTouch {
            entry.firstSeen = date
            entry.visitCount = 1
        }

        let fractionAfter = entry.fraction
        let gained = fractionAfter - fractionBefore
        guard gained > 0 || firstTouch else { return nil }

        coverage[segment.id] = entry
        revision += 1
        recountIfNeeded(firstTouch: firstTouch, becameComplete: !wasComplete && entry.isComplete)
        scheduleSave()

        return CoverageDelta(
            segment: segment,
            newMetres: gained * segment.length,
            completedNow: !wasComplete && entry.isComplete,
            firstTouch: firstTouch,
            fractionAfter: fractionAfter
        )
    }

    /// Marks a new visit to segments already collected, for visit counts.
    func noteRevisit(segmentID: String, at date: Date) {
        guard var entry = coverage[segmentID] else { return }
        entry.visitCount += 1
        entry.lastSeen = date
        coverage[segmentID] = entry
        scheduleSave()
    }

    // MARK: - Statistics

    /// Completion of a tile, counting only classes that count toward the
    /// headline percentage.
    func completion(ofTile tile: TileKey, in data: StreetDataStore) -> TileCompletion {
        let segments = data.segments(inTile: tile).filter { $0.classification.countsTowardCompletion }
        guard !segments.isEmpty else {
            return TileCompletion(tile: tile, total: 0, completed: 0, metresTotal: 0, metresCovered: 0)
        }
        var completed = 0
        var metresTotal = 0.0
        var metresCovered = 0.0
        for segment in segments {
            metresTotal += segment.length
            if let entry = coverage[segment.id] {
                metresCovered += entry.fraction * segment.length
                if entry.isComplete { completed += 1 }
            }
        }
        return TileCompletion(
            tile: tile,
            total: segments.count,
            completed: completed,
            metresTotal: metresTotal,
            metresCovered: metresCovered
        )
    }

    /// Collected streets grouped by name, newest first. This is the "collection
    /// book" view — one row per real-world street, not per OSM fragment.
    func collectedStreets(in data: StreetDataStore) -> [CollectedStreet] {
        var grouped: [String: CollectedStreet] = [:]
        for entry in coverage.values {
            guard let segment = data.segment(id: entry.segmentID) else { continue }
            let key = segment.name ?? "unnamed-\(segment.id)"
            var street = grouped[key] ?? CollectedStreet(
                name: segment.displayName,
                classification: segment.classification,
                segmentCount: 0,
                completedSegmentCount: 0,
                metresTotal: 0,
                metresCovered: 0,
                firstSeen: entry.firstSeen,
                lastSeen: entry.lastSeen
            )
            street.segmentCount += 1
            if entry.isComplete { street.completedSegmentCount += 1 }
            street.metresTotal += segment.length
            street.metresCovered += entry.fraction * segment.length
            street.firstSeen = min(street.firstSeen, entry.firstSeen)
            street.lastSeen = max(street.lastSeen, entry.lastSeen)
            grouped[key] = street
        }
        return grouped.values.sorted { $0.lastSeen > $1.lastSeen }
    }

    /// Distinct real-world street names fully collected. Counting segments
    /// would reward long streets twice, so this counts names.
    func distinctNamedStreetCount(in data: StreetDataStore) -> Int {
        var names = Set<String>()
        for entry in coverage.values where entry.isComplete {
            guard let name = data.segment(id: entry.segmentID)?.name else { continue }
            names.insert(name)
        }
        return names.count
    }

    /// Segments first collected between midnight and 5am.
    var nightCollectedCount: Int {
        let calendar = Calendar.current
        return coverage.values.filter { entry in
            guard entry.isComplete else { return false }
            let hour = calendar.component(.hour, from: entry.firstSeen)
            return hour < 5
        }.count
    }

    // MARK: - Lifecycle

    func reset() {
        coverage.removeAll()
        completedCount = 0
        touchedCount = 0
        revision += 1
        store.delete(Self.fileName)
    }

    private func recountIfNeeded(firstTouch: Bool, becameComplete: Bool) {
        if firstTouch { touchedCount += 1 }
        if becameComplete { completedCount += 1 }
    }

    private func load() {
        guard let saved = store.load([SegmentCoverage].self, from: Self.fileName) else { return }
        coverage = Dictionary(uniqueKeysWithValues: saved.map { ($0.segmentID, $0) })
        touchedCount = coverage.count
        completedCount = coverage.values.filter(\.isComplete).count
        logger.info("Loaded coverage for \(self.coverage.count, privacy: .public) segments")
    }

    /// Coverage changes on every location update; writing each time would burn
    /// battery for nothing. Debounce, and flush explicitly on backgrounding.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    func flush() {
        store.save(Array(coverage.values), to: Self.fileName)
    }
}

struct TileCompletion: Identifiable {
    let tile: TileKey
    let total: Int
    let completed: Int
    let metresTotal: Double
    let metresCovered: Double

    var id: String { tile.description }
    var fraction: Double { metresTotal > 0 ? metresCovered / metresTotal : 0 }
    var percent: Double { fraction * 100 }
}

struct CollectedStreet: Identifiable, Hashable {
    let name: String
    let classification: StreetClassification
    var segmentCount: Int
    var completedSegmentCount: Int
    var metresTotal: Double
    var metresCovered: Double
    var firstSeen: Date
    var lastSeen: Date

    var id: String { name }
    var fraction: Double { metresTotal > 0 ? metresCovered / metresTotal : 0 }
    var isFullyCollected: Bool { completedSegmentCount == segmentCount }
}
