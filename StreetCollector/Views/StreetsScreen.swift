import SwiftUI

/// The collection book: every street you've been down, grouped by name.
///
/// Built from a `ScrollView` of cards rather than a `List`, because a plain
/// inset-grouped list is the one thing guaranteed to make a game look like a
/// settings screen.
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

        var symbol: String {
            switch self {
            case .all: return "square.stack.3d.up.fill"
            case .complete: return "checkmark.seal.fill"
            case .partial: return "circle.lefthalf.filled"
            }
        }
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
                        title: "The city is dark",
                        message: "Start a trip on the map. Every street you go down lands here, and stays."
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12, pinnedViews: [.sectionHeaders]) {
                            header
                            filterBar

                            ForEach(streets) { street in
                                row(for: street)
                            }

                            if streets.isEmpty {
                                Text("Nothing matches.")
                                    .font(Theme.body)
                                    .foregroundStyle(.white.opacity(0.4))
                                    .padding(.top, 40)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .cityBackground()
            .navigationTitle("Collection")
            .searchable(text: $search, prompt: "Search streets")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle.fill")
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 12) {
            StatTile(
                value: "\(coverage.completedCount)",
                label: "Collected",
                symbolName: "checkmark.seal.fill"
            )
            StatTile(
                value: "\(max(0, coverage.touchedCount - coverage.completedCount))",
                label: "In progress",
                symbolName: "circle.lefthalf.filled",
                tint: Theme.partial
            )
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(Filter.allCases) { option in
                let selected = filter == option
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { filter = option }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: option.symbol)
                            .font(Theme.font(10, .bold))
                        Text(option.rawValue)
                            .font(Theme.font(13, .semibold))
                    }
                    .foregroundStyle(selected ? Theme.ink : .white.opacity(0.6))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background {
                        if selected {
                            Capsule().fill(Theme.primaryGradient)
                        } else {
                            Capsule().fill(.white.opacity(0.06))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func row(for street: CollectedStreet) -> some View {
        let tint = street.isFullyCollected ? Theme.collected : Theme.partial

        return GlassPanel(tint: tint) {
            HStack(spacing: 14) {
                ZStack {
                    ProgressRing(fraction: street.fraction, lineWidth: 4, tint: tint)
                    Image(systemName: street.isFullyCollected ? "checkmark" : "figure.walk")
                        .font(Theme.font(13, .bold))
                        .foregroundStyle(tint)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 5) {
                    Text(street.name)
                        .font(Theme.font(15, .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(street.classification.displayName)
                            .font(Theme.font(10, .bold))
                            .foregroundStyle(Theme.classificationColor(street.classification))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Theme.classificationColor(street.classification).opacity(0.14),
                                in: Capsule()
                            )
                        Text(Format.distance(street.metresCovered))
                            .font(Theme.numeric(11, .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(Format.percent(street.fraction))
                        .font(Theme.numeric(15, .heavy))
                        .foregroundStyle(tint)
                    Text(Format.relative(street.lastSeen))
                        .font(Theme.font(10, .medium))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
        }
    }
}
