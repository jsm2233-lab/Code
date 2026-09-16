import CoreLocation
import Foundation
import os

/// Ties the pieces together: location in, matched streets and score out.
///
/// Everything else in `Services` is deliberately independent — this is the only
/// object that knows about all of them, which keeps the matcher and the stores
/// testable on their own.
@MainActor
final class CollectionEngine: ObservableObject {

    @Published private(set) var activeTrip: Trip?
    @Published private(set) var currentSegment: StreetSegment?
    @Published private(set) var lastMatchQuality: MatchQuality = .unknown
    @Published private(set) var isRunning = false
    /// Segment ids touched in this session, so the map can highlight them hot.
    @Published private(set) var sessionSegmentIDs: Set<String> = []

    enum MatchQuality {
        case unknown
        case good
        case weak
        case offRoad

        var label: String {
            switch self {
            case .unknown: return "Waiting for GPS"
            case .good: return "Collecting"
            case .weak: return "Weak signal"
            case .offRoad: return "No street here"
            }
        }
    }

    let location: LocationService
    let data: StreetDataStore
    let coverage: CoverageStore
    let game: GameEngine
    let trips: TripStore
    let notifications: NotificationService

    private var matcher: MapMatcher
    private let logger = Logger(subsystem: "com.example.StreetCollector", category: "Engine")
    private var lastTrackPoint: CLLocation?
    private var lastTileCheck: Coordinate?
    private var speedSamples: [Double] = []

    /// Track points are only appended when the user has moved this far, so a
    /// two-hour drive doesn't serialise 7,000 coordinates.
    private let trackPointSpacing: Double = 20

    init(
        location: LocationService,
        data: StreetDataStore,
        coverage: CoverageStore,
        game: GameEngine,
        trips: TripStore,
        notifications: NotificationService
    ) {
        self.location = location
        self.data = data
        self.coverage = coverage
        self.game = game
        self.trips = trips
        self.notifications = notifications
        self.matcher = MapMatcher(index: data.index)

        self.location.onLocation = { [weak self] location in
            self?.handle(location)
        }
    }

    // MARK: - Trip control

    func startTrip() {
        guard activeTrip == nil else { return }
        matcher.reset()
        lastTrackPoint = nil
        speedSamples.removeAll()
        sessionSegmentIDs.removeAll()
        activeTrip = Trip()
        isRunning = true
        location.stopMonitoringSignificantChanges()
        location.startTracking()
        logger.info("Trip started")
    }

    func endTrip() {
        guard var trip = activeTrip else { return }
        trip.endedAt = Date()
        trip.mode = inferredMode()
        activeTrip = nil
        isRunning = false
        currentSegment = nil
        location.stopTracking()
        location.startMonitoringSignificantChanges()

        // A trip that collected nothing is noise in the history.
        if trip.distanceMetres > 50 {
            trips.append(trip)
        }

        coverage.flush()
        game.flush()

        let best = bestTileCompletionPercent()
        let unlocked = game.evaluateAchievements(
            coverage: coverage,
            data: data,
            trips: trips.trips,
            bestTileCompletion: best
        )
        for achievement in unlocked {
            notifications.postAchievement(achievement)
        }
        if trip.newStreetMetres > 0 {
            notifications.postTripSummary(trip)
        }
        logger.info("Trip ended: \(Int(trip.distanceMetres), privacy: .public) m, \(Int(trip.newStreetMetres), privacy: .public) m new")
    }

    func toggleTrip() {
        activeTrip == nil ? startTrip() : endTrip()
    }

    // MARK: - The hot path

    private func handle(_ fix: CLLocation) {
        let point = Coordinate(fix.coordinate)

        // Keep the street graph loaded ahead of the user. Only re-check after
        // moving a few hundred metres; this runs on every fix.
        if lastTileCheck == nil || GeoMath.distance(lastTileCheck!, point) > 300 {
            lastTileCheck = point
            data.ensureLoaded(around: point)
            game.setHomeTile(TileKey(containing: point))
        }

        guard activeTrip != nil else { return }

        accumulateDistance(to: fix)
        appendTrackPoint(fix)
        if fix.speed >= 0 { speedSamples.append(fix.speed) }

        let result = matcher.process(fix)

        switch result.rejectedReason {
        case .poorAccuracy:
            lastMatchQuality = .weak
        case .noCandidates, .noConfidentMatch:
            lastMatchQuality = .offRoad
            currentSegment = nil
        case nil:
            lastMatchQuality = .good
        }

        guard let traversal = result.traversal else { return }
        currentSegment = traversal.segment

        let wasNew = coverage.coverage(for: traversal.segment.id) == nil
        guard let delta = coverage.record(
            segment: traversal.segment,
            from: traversal.lower,
            to: traversal.upper,
            at: fix.timestamp
        ) else { return }

        sessionSegmentIDs.insert(traversal.segment.id)

        let mode = TravelMode.inferred(fromSpeed: fix.speed)
        let xp = game.award(for: delta, mode: mode, at: fix.timestamp)

        activeTrip?.newStreetMetres += delta.newMetres
        activeTrip?.xpEarned += xp
        if wasNew {
            activeTrip?.newSegmentIDs.append(traversal.segment.id)
        }
        if delta.completedNow {
            activeTrip?.completedSegmentIDs.append(traversal.segment.id)
            notifications.postStreetCollected(traversal.segment, xp: xp)
        }
    }

    private func accumulateDistance(to fix: CLLocation) {
        defer { lastTrackPoint = lastTrackPoint ?? fix }
        guard let previous = lastTrackPoint else { return }
        let step = fix.distance(from: previous)
        // Reject teleports: a fix that implies an impossible speed is a bad fix,
        // not a fast car.
        let interval = max(0.5, fix.timestamp.timeIntervalSince(previous.timestamp))
        guard step < 500, step / interval < 70 else { return }
        activeTrip?.distanceMetres += step
        game.addDistance(step)
    }

    private func appendTrackPoint(_ fix: CLLocation) {
        let point = Coordinate(fix.coordinate)
        if let last = activeTrip?.track.last,
           GeoMath.distance(last, point) < trackPointSpacing {
            return
        }
        activeTrip?.track.append(point)
        lastTrackPoint = fix
    }

    private func inferredMode() -> TravelMode {
        guard !speedSamples.isEmpty else { return .unknown }
        let sorted = speedSamples.sorted()
        // Median, not mean: traffic lights and stops drag a mean toward walking.
        let median = sorted[sorted.count / 2]
        return TravelMode.inferred(fromSpeed: median)
    }

    // MARK: - Stats helpers

    func bestTileCompletionPercent() -> Double {
        data.loadedTiles
            .map { coverage.completion(ofTile: $0, in: data).percent }
            .max() ?? 0
    }

    func homeTileCompletion() -> TileCompletion? {
        guard let tile = game.profile.homeTile else { return nil }
        return coverage.completion(ofTile: tile, in: data)
    }

    /// Nearby streets you haven't finished, closest first. This is the app's
    /// "what should I do next" list.
    func suggestions(near coordinate: Coordinate, limit: Int = 10) -> [Suggestion] {
        let candidates = data.index.candidates(near: coordinate, radius: 1_200)
        return candidates
            .filter { $0.classification.countsTowardCompletion }
            .compactMap { segment -> Suggestion? in
                let fraction = coverage.fraction(for: segment.id)
                guard fraction < SegmentCoverage.completionThreshold else { return nil }
                let mid = segment.coordinate(atFraction: 0.5)
                return Suggestion(
                    segment: segment,
                    distance: GeoMath.distance(coordinate, mid),
                    fraction: fraction
                )
            }
            .sorted { $0.distance < $1.distance }
            .prefix(limit)
            .map { $0 }
    }

    struct Suggestion: Identifiable {
        let segment: StreetSegment
        let distance: Double
        let fraction: Double

        var id: String { segment.id }
    }

    func resetEverything() {
        endTrip()
        coverage.reset()
        game.reset()
        trips.reset()
        sessionSegmentIDs.removeAll()
    }
}
