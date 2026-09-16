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

                    Card {
                        HStack(spacing: 16) {
                            ZStack {
                                ProgressRing(fraction: entry?.fraction ?? 0, lineWidth: 9, tint: ringTint)
                                Text(Format.percent(entry?.fraction ?? 0))
                                    .font(.caption.weight(.bold))
                                    .monospacedDigit()
                            }
                            .frame(width: 74, height: 74)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(statusText).font(.headline)
                                Text("\(Format.distance((entry?.fraction ?? 0) * segment.length)) of \(Format.distance(segment.length))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                if let entry {
                                    Text("Last seen \(Format.relative(entry.lastSeen))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Card(title: "Details") {
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
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        data.refresh(tile: segment.tile)
                        dismiss()
                    } label: {
                        Label("Street data looks wrong — refresh", systemImage: "arrow.clockwise")
                            .font(.footnote)
                    }
                    .padding(.top, 4)
                }
                .padding(16)
            }
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
        VStack(alignment: .leading, spacing: 4) {
            Text(segment.displayName)
                .font(.title2.weight(.bold))
            Text(segment.classification.displayName)
                .font(.subheadline)
                .foregroundStyle(Theme.classificationColor(segment.classification))
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
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.subheadline)
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
                    List(suggestions) { suggestion in
                        HStack(spacing: 12) {
                            Image(systemName: suggestion.fraction > 0 ? "circle.lefthalf.filled" : "circle")
                                .foregroundStyle(suggestion.fraction > 0 ? Theme.partial : Theme.uncollected)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(suggestion.segment.displayName)
                                    .lineLimit(1)
                                Text("\(Format.distance(suggestion.distance)) away · \(Format.distance(suggestion.segment.length)) long")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if suggestion.fraction > 0 {
                                Text(Format.percent(suggestion.fraction))
                                    .font(.caption.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.partial)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
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
