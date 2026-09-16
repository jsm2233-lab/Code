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
            .cityBackground()
            .navigationTitle("Stats")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Export collected streets (GeoJSON)") { export(completedOnly: true) }
                        Button("Export all coverage (GeoJSON)") { export(completedOnly: false) }
                    } label: {
                        Image(systemName: "square.and.arrow.up.circle.fill")
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.url])
            }
        }
    }

    // MARK: - Cards

    /// Hero card. The level ring is the single biggest thing on the screen
    /// because levelling is the spine the rest of the scoring hangs off.
    private var levelCard: some View {
        GlassPanel(tint: Theme.accent, glow: true) {
            VStack(spacing: 18) {
                HStack(spacing: 20) {
                    ZStack {
                        ProgressRing(fraction: game.profile.levelProgress, lineWidth: 9, gradient: Theme.primaryGradient)
                        VStack(spacing: -4) {
                            Text("\(game.profile.level)")
                                .font(Theme.numeric(36, .heavy))
                                .foregroundStyle(.white)
                            Text("LEVEL")
                                .font(Theme.font(8, .heavy))
                                .tracking(2)
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    .frame(width: 96, height: 96)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(game.profile.levelTitle)
                            .font(Theme.title)
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)

                        Text("\(Format.xp(game.profile.xp)) XP")
                            .font(Theme.numeric(14, .bold))
                            .foregroundStyle(Theme.accent)

                        LinearProgress(fraction: game.profile.levelProgress, gradient: Theme.primaryGradient, height: 7)
                            .shimmering()

                        Text("\(Format.xp(max(0, game.profile.xpForNextLevel - game.profile.xpIntoLevel))) XP to level \(game.profile.level + 1)")
                            .font(Theme.font(10, .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }

                HStack(spacing: 10) {
                    streakChip(
                        value: "\(game.profile.currentStreakDays)",
                        label: "day streak",
                        symbol: "flame.fill",
                        gradient: Theme.streakGradient
                    )
                    streakChip(
                        value: "\(game.profile.longestStreakDays)",
                        label: "best ever",
                        symbol: "trophy.fill",
                        gradient: Theme.gradient(for: .gold)
                    )
                }
            }
        }
    }

    private func streakChip(value: String, label: String, symbol: String, gradient: LinearGradient) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(Theme.font(13, .bold))
                .foregroundStyle(gradient)
            Text(value)
                .font(Theme.numeric(16, .heavy))
                .foregroundStyle(.white)
            Text(label.uppercased())
                .font(Theme.font(9, .bold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.4))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Per-tile completion. Tiles are the closest thing the app has to
    /// neighbourhoods without dragging in an admin-boundary dataset.
    private var tileGrid: some View {
        let completions = data.loadedTiles
            .map { coverage.completion(ofTile: $0, in: data) }
            .filter { $0.total > 0 }
            .sorted { $0.fraction > $1.fraction }
            .prefix(12)

        return Card(title: "Areas", symbol: "square.grid.2x2.fill") {
            if completions.isEmpty {
                Text("Move around to load street data for your area.")
                    .font(Theme.body)
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(Array(completions)) { completion in
                        VStack(spacing: 6) {
                            ZStack {
                                ProgressRing(
                                    fraction: completion.fraction,
                                    lineWidth: 5,
                                    tint: completion.fraction >= 1 ? Theme.violet : Theme.accent,
                                    gradient: completion.fraction >= 1 ? Theme.legendaryGradient : Theme.primaryGradient
                                )
                                Text("\(Int(completion.percent))")
                                    .font(Theme.numeric(12, .heavy))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 48, height: 48)
                            Text("\(completion.completed)/\(completion.total)")
                                .font(Theme.numeric(9, .semibold))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }
            }
        }
    }

    private var activityChart: some View {
        let daily = trips.dailyNewMetres(days: 30)
        return Card(title: "New streets, last 30 days", symbol: "chart.bar.fill", tint: Theme.hot) {
            if daily.allSatisfy({ $0.metres == 0 }) {
                Text("No trips yet.")
                    .font(Theme.body)
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                Chart {
                    ForEach(daily, id: \.date) { entry in
                        BarMark(
                            x: .value("Day", entry.date, unit: .day),
                            y: .value("New km", entry.metres / 1_000)
                        )
                        .foregroundStyle(Theme.primaryGradient)
                        .cornerRadius(3)
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
        Card(title: "Recent trips", symbol: "figure.walk.motion", tint: Theme.partial) {
            if trips.trips.isEmpty {
                Text("Your finished trips show up here.")
                    .font(Theme.body)
                    .foregroundStyle(.white.opacity(0.5))
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
                            Divider()
                                .overlay(.white.opacity(0.06))
                                .padding(.vertical, 10)
                        }
                    }
                    if trips.trips.count > 5 {
                        NavigationLink {
                            TripsScreen()
                        } label: {
                            HStack(spacing: 4) {
                                Text("See all \(trips.trips.count) trips")
                                Image(systemName: "chevron.right")
                                    .font(Theme.font(10, .bold))
                            }
                            .font(Theme.font(13, .bold))
                            .foregroundStyle(Theme.accent)
                        }
                        .padding(.top, 14)
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
        HStack(spacing: 13) {
            Image(systemName: trip.mode.symbolName)
                .font(Theme.font(15, .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 36, height: 36)
                .background(Theme.primaryGradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(trip.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(Theme.font(14, .bold))
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    Label(Format.distance(trip.distanceMetres), systemImage: "arrow.forward")
                    Label(Format.distance(trip.newStreetMetres), systemImage: "sparkles")
                    Label("\(trip.completedSegmentIDs.count)", systemImage: "checkmark.seal.fill")
                }
                .font(Theme.numeric(10, .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .labelStyle(.titleAndIcon)
            }

            Spacer(minLength: 0)

            Text("+\(Format.xp(trip.xpEarned))")
                .font(Theme.numeric(13, .heavy))
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
