import Foundation

/// Persistent history of finished trips.
@MainActor
final class TripStore: ObservableObject {

    @Published private(set) var trips: [Trip] = []

    private let store: FileStore
    private static let fileName = "trips.json"

    init(store: FileStore = .shared) {
        self.store = store
        trips = store.load([Trip].self, from: Self.fileName) ?? []
    }

    func append(_ trip: Trip) {
        trips.insert(trip, at: 0)
        flush()
    }

    func delete(_ trip: Trip) {
        trips.removeAll { $0.id == trip.id }
        flush()
    }

    func reset() {
        trips.removeAll()
        store.delete(Self.fileName)
    }

    // MARK: - Aggregates

    var totalDistance: Double { trips.reduce(0) { $0 + $1.distanceMetres } }
    var totalNewStreetMetres: Double { trips.reduce(0) { $0 + $1.newStreetMetres } }

    /// New-street metres per day for the last `days` days, oldest first. Drives
    /// the activity chart on the stats screen.
    func dailyNewMetres(days: Int = 30, now: Date = Date()) -> [(date: Date, metres: Double)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var buckets: [Date: Double] = [:]
        for trip in trips {
            let day = calendar.startOfDay(for: trip.startedAt)
            guard let diff = calendar.dateComponents([.day], from: day, to: today).day,
                  diff >= 0, diff < days else { continue }
            buckets[day, default: 0] += trip.newStreetMetres
        }
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (day, buckets[day] ?? 0)
        }
    }

    func trips(on day: Date) -> [Trip] {
        let calendar = Calendar.current
        return trips.filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
    }

    private func flush() {
        store.save(trips, to: Self.fileName)
    }
}
