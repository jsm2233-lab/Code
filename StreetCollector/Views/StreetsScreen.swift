import SwiftUI

/// The collection book: every street you've been down, grouped by name.
struct StreetsScreen: View {

    @EnvironmentObject private var coverage: CoverageStore
    @EnvironmentObject private var data: StreetDataStore

    @State private var search = ""
    @State private var filter = Filter.all
    @State private var sort = SortOrder.recent

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case complete = "Collected"
        case partial = "In progress"

        var id: String { rawValue }
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case recent = "Recent"
        case name = "Name"
        case length = "Longest"

        var id: String { rawValue }
    }

    private var streets: [CollectedStreet] {
        var result = coverage.collectedStreets(in: data)

        switch filter {
        case .all: break
        case .complete: result = result.filter(\.isFullyCollected)
        case .partial: result = result.filter { !$0.isFullyCollected }
        }

        if !search.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(search) }
        }

        switch sort {
        case .recent: result.sort { $0.lastSeen > $1.lastSeen }
        case .name: result.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .length: result.sort { $0.metresCovered > $1.metresCovered }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Group {
                if coverage.touchedCount == 0 {
                    EmptyStateView(
                        symbolName: "map",
                        title: "Nothing collected yet",
                        message: "Start a trip on the map and every street you go down lands here."
                    )
                } else {
                    List {
                        Section {
                            summaryRow
                        }
                        Section("\(streets.count) streets") {
                            ForEach(streets) { street in
                                row(for: street)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Collection")
            .searchable(text: $search, prompt: "Search streets")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Filter", selection: $filter) {
                            ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Picker("Sort", selection: $sort) {
                            ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 12) {
            StatTile(
                value: "\(coverage.completedCount)",
                label: "Collected",
                symbolName: "checkmark.seal.fill"
            )
            StatTile(
                value: "\(coverage.touchedCount - coverage.completedCount)",
                label: "In progress",
                symbolName: "circle.lefthalf.filled",
                tint: Theme.partial
            )
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    private func row(for street: CollectedStreet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: street.isFullyCollected ? "checkmark.seal.fill" : "circle.lefthalf.filled")
                    .foregroundStyle(street.isFullyCollected ? Theme.collected : Theme.partial)
                Text(street.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                Text(Format.percent(street.fraction))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            LinearProgress(
                fraction: street.fraction,
                tint: street.isFullyCollected ? Theme.collected : Theme.partial
            )
            HStack {
                Text(street.classification.displayName)
                Text("·")
                Text(Format.distance(street.metresCovered))
                Spacer()
                Text(Format.relative(street.lastSeen))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
