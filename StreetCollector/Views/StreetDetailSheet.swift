import MapKit
import SwiftUI

/// Tapping a street on the map opens this: how much of it you own, and when you
/// last went down it.
struct StreetDetailSheet: View {

    let segment: StreetSegment

    @EnvironmentObject private var coverage: CoverageStore
    @EnvironmentObject private var data: StreetDataStore
    @Environment(\.dismiss) private var dismiss

    private var entry: SegmentCoverage? { coverage.coverage(for: segment.id) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    GlassPanel(tint: ringTint, glow: entry?.isComplete == true) {
                        HStack(spacing: 18) {
                            ZStack {
                                ProgressRing(fraction: entry?.fraction ?? 0, lineWidth: 8, tint: ringTint)
                                Text(Format.percent(entry?.fraction ?? 0))
                                    .font(Theme.numeric(15, .heavy))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 78, height: 78)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(statusText)
                                    .font(Theme.headline)
                                    .foregroundStyle(ringTint)
                                Text("\(Format.distance((entry?.fraction ?? 0) * segment.length)) of \(Format.distance(segment.length))")
                                    .font(Theme.numeric(13, .semibold))
                                    .foregroundStyle(.white.opacity(0.6))
                                if let entry {
                                    Text("Last seen \(Format.relative(entry.lastSeen))")
                                        .font(Theme.caption)
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                            }
                        }
                    }

                    Card(title: "Details", symbol: "info.circle.fill") {
                        detailRow("Type", segment.classification.displayName)
                        detailRow("Length", Format.distance(segment.length))
                        detailRow("Direction", segment.isOneWay ? "One way" : "Two way")
                        detailRow("XP multiplier", String(format: "%.1fx", segment.classification.scoreMultiplier))
                        if let entry {
                            detailRow("First collected", entry.firstSeen.formatted(date: .abbreviated, time: .shortened))
                            detailRow("Visits", "\(max(1, entry.visitCount))")
                        }
                        if !segment.classification.countsTowardCompletion {
                            Text("Collectible, but doesn't count toward city completion.")
                                .font(Theme.caption)
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }

                    Button {
                        data.refresh(tile: segment.tile)
                        dismiss()
                    } label: {
                        Label("Street data looks wrong — refresh", systemImage: "arrow.clockwise")
                            .font(Theme.font(13, .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .padding(.top, 4)
                }
                .padding(16)
            }
            .cityBackground()
            .navigationTitle("Street")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(segment.displayName)
                .font(Theme.display)
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(2)
            Text(segment.classification.displayName.uppercased())
                .font(Theme.micro)
                .tracking(1.4)
                .foregroundStyle(Theme.classificationColor(segment.classification))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Theme.classificationColor(segment.classification).opacity(0.14),
                    in: Capsule()
                )
        }
    }

    private var ringTint: Color {
        guard let entry else { return Theme.uncollected }
        return entry.isComplete ? Theme.collected : Theme.partial
    }

    private var statusText: String {
        guard let entry else { return "Not collected" }
        return entry.isComplete ? "Collected" : "Partly collected"
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.body)
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(Theme.numeric(14, .semibold))
                .foregroundStyle(.white)
        }
    }
}

/// "What's near me that I haven't finished." The single most useful screen once
/// the easy streets are gone.
struct SuggestionsSheet: View {

    @EnvironmentObject private var engine: CollectionEngine
    @EnvironmentObject private var location: LocationService
    @Environment(\.dismiss) private var dismiss

    private var suggestions: [CollectionEngine.Suggestion] {
        guard let current = location.latestLocation else { return [] }
        return engine.suggestions(near: Coordinate(current.coordinate), limit: 25)
    }

    var body: some View {
        NavigationStack {
            Group {
                if suggestions.isEmpty {
                    EmptyStateView(
                        symbolName: "checkmark.seal.fill",
                        title: "Nothing left nearby",
                        message: "Every street within a kilometre is collected, or street data hasn't loaded yet. Go further out."
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(suggestions) { suggestion in
                                GlassPanel(tint: suggestion.fraction > 0 ? Theme.partial : Theme.uncollected) {
                                    HStack(spacing: 13) {
                                        Image(systemName: suggestion.fraction > 0 ? "circle.lefthalf.filled" : "circle.dashed")
                                            .font(Theme.font(17, .bold))
                                            .foregroundStyle(suggestion.fraction > 0 ? Theme.partial : Theme.uncollected)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(suggestion.segment.displayName)
                                                .font(Theme.font(14, .bold))
                                                .foregroundStyle(.white)
                                                .lineLimit(1)
                                            Text("\(Format.distance(suggestion.distance)) away · \(Format.distance(suggestion.segment.length)) long")
                                                .font(Theme.numeric(11, .medium))
                                                .foregroundStyle(.white.opacity(0.45))
                                        }

                                        Spacer(minLength: 0)

                                        if suggestion.fraction > 0 {
                                            Text(Format.percent(suggestion.fraction))
                                                .font(Theme.numeric(13, .heavy))
                                                .foregroundStyle(Theme.partial)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .cityBackground()
            .navigationTitle("Collect next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
