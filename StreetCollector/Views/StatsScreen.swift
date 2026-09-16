import Charts
import SwiftUI

struct StatsScreen: View {

    @EnvironmentObject private var engine: CollectionEngine
    @EnvironmentObject private var game: GameEngine
    @EnvironmentObject private var coverage: CoverageStore
    @EnvironmentObject private var data: StreetDataStore
    @EnvironmentObject private var trips: TripStore

    @State private var shareItem: ShareItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    levelCard
                    tileGrid
                    activityChart
                    totals
                    tripsCard
                }
                .padding(16)
            }
            .navigationTitle("Stats")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Export collected streets (GeoJSON)") { export(completedOnly: true) }
                        Button("Export all coverage (GeoJSON)") { export(completedOnly: false) }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.url])
            }
        }
    }

    // MARK: - Cards

    private var levelCard: some View {
        Card {
            HStack(spacing: 16) {
                ZStack {
                    ProgressRing(fraction: game.profile.levelProgress, lineWidth: 10)
                    VStack(spacing: 0) {
                        Text("\(game.profile.level)")
                            .font(.title.weight(.heavy))
                            .monospacedDigit()
                        Text("LEVEL")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 86, height: 86)

                VStack(alignment: .leading, spacing: 6) {
                    Text(game.profile.levelTitle)
                        .font(.title3.weight(.bold))
                    Text("\(Format.xp(game.profile.xp)) XP total")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    HStack(spacing: 10) {
                        Label("\(game.profile.currentStreakDays)d streak", systemImage: "flame.fill")
                        Label("\(game.profile.longestStreakDays)d best", systemImage: "trophy.fill")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Per-tile completion. Tiles are the closest thing the app has to
    /// neighbourhoods without dragging in an admin-boundary dataset.
    private var tileGrid: some View {
        let completions = data.loadedTiles
            .map { coverage.completion(ofTile: $0, in: data) }
            .filter { $0.total > 0 }
            .sorted { $0.fraction > $1.fraction }
            .prefix(12)

        return Card(title: "Areas") {
            if completions.isEmpty {
                Text("Move around to load street data for your area.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(Array(completions)) { completion in
                        VStack(spacing: 6) {
                            ZStack {
                                ProgressRing(fraction: completion.fraction, lineWidth: 5)
                                Text("\(Int(completion.percent))")
                                    .font(.caption2.weight(.bold))
                                    .monospacedDigit()
                            }
                            .frame(width: 46, height: 46)
                            Text("\(completion.completed)/\(completion.total)")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    private var activityChart: some View {
        let daily = trips.dailyNewMetres(days: 30)
        return Card(title: "New streets, last 30 days") {
            if daily.allSatisfy({ $0.metres == 0 }) {
                Text("No trips yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(daily, id: \.date) { entry in
                        BarMark(
                            x: .value("Day", entry.date, unit: .day),
                            y: .value("New km", entry.metres / 1_000)
                        )
                        .foregroundStyle(Theme.accent.gradient)
                        .cornerRadius(2)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7))
                }
                .frame(height: 160)
            }
        }
    }

    private var totals: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatTile(
                    value: "\(coverage.completedCount)",
                    label: "Streets collected",
                    symbolName: "checkmark.seal.fill"
                )
                StatTile(
                    value: Format.distance(game.profile.totalNewStreetMetres),
                    label: "New street distance",
                    symbolName: "sparkles",
                    tint: Theme.partial
                )
            }
            HStack(spacing: 12) {
                StatTile(
                    value: Format.distance(game.profile.totalDistanceMetres),
                    label: "Total travelled",
                    symbolName: "arrow.forward",
                    tint: Theme.hot
                )
                StatTile(
                    value: "\(trips.trips.count)",
                    label: "Trips",
                    symbolName: "figure.walk.motion",
                    tint: .purple
                )
            }
        }
    }

    private var tripsCard: some View {
        Card(title: "Recent trips") {
            if trips.trips.isEmpty {
                Text("Your finished trips show up here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(trips.trips.prefix(5)) { trip in
                        NavigationLink {
                            TripDetailScreen(trip: trip)
                        } label: {
                            TripRow(trip: trip)
                        }
                        .buttonStyle(.plain)
                        if trip.id != trips.trips.prefix(5).last?.id {
                            Divider().padding(.vertical, 8)
                        }
                    }
                    if trips.trips.count > 5 {
                        NavigationLink("See all \(trips.trips.count) trips") {
                            TripsScreen()
                        }
                        .font(.footnote)
                        .padding(.top, 12)
                    }
                }
            }
        }
    }

    private func export(completedOnly: Bool) {
        guard let data = ExportService.geoJSON(
            coverage: coverage,
            data: self.data,
            completedOnly: completedOnly
        ) else { return }
        guard let url = ExportService.write(data, named: "street-collection.geojson") else { return }
        shareItem = ShareItem(url: url)
    }
}

struct TripRow: View {
    let trip: Trip

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: trip.mode.symbolName)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(trip.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline.weight(.medium))
                Text("\(Format.distance(trip.distanceMetres)) · \(Format.distance(trip.newStreetMetres)) new · \(trip.completedSegmentIDs.count) collected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("+\(Format.xp(trip.xpEarned))")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.accent)
        }
    }
}

/// Wrapper so a URL can drive `.sheet(item:)` without adding a retroactive
/// `Identifiable` conformance to a Foundation type.
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
