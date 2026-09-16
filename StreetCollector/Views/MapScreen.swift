import CoreLocation
import MapKit
import SwiftUI

struct MapScreen: View {

    @EnvironmentObject private var engine: CollectionEngine
    @EnvironmentObject private var coverage: CoverageStore
    @EnvironmentObject private var data: StreetDataStore
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var settings: AppSettings

    @State private var snapshot: CoverageSnapshot = .empty
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278),
        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )
    @State private var trackingMode: MKUserTrackingMode = .follow
    @State private var selectedSegment: StreetSegment?
    @State private var showSuggestions = false
    @State private var rebuildTask: Task<Void, Never>?

    /// Above this many segments on screen, uncollected streets stop being drawn.
    /// Past this zoom level they're a grey smear anyway, and the redraw cost is
    /// what makes a map feel cheap.
    private let uncollectedDrawLimit = 4_000

    var body: some View {
        ZStack(alignment: .top) {
            MapContainerView(
                snapshot: snapshot,
                style: settings.mapStyle,
                showFog: settings.fogOfWar,
                trackingMode: $trackingMode,
                onRegionChange: handleRegionChange,
                onTap: handleTap
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HUDView()
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                Spacer()
            }

            VStack {
                Spacer()
                controls
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            ScoreEventOverlay()
        }
        .sheet(item: $selectedSegment) { segment in
            StreetDetailSheet(segment: segment)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showSuggestions) {
            SuggestionsSheet()
                .presentationDetents([.medium, .large])
        }
        .onAppear(perform: centreOnUserIfPossible)
        .onChange(of: coverage.revision) { _, _ in scheduleRebuild() }
        .onChange(of: data.segmentCount) { _, _ in scheduleRebuild() }
        .onChange(of: settings.showUncollectedStreets) { _, _ in scheduleRebuild() }
        .onChange(of: location.latestLocation?.coordinate.latitude) { _, _ in
            centreOnUserIfPossible()
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                showSuggestions = true
            } label: {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.title3)
                    .frame(width: 48, height: 48)
                    .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel("Nearby streets to collect")

            Spacer()

            Button(action: toggleTrip) {
                HStack(spacing: 8) {
                    Image(systemName: engine.isRunning ? "stop.fill" : "play.fill")
                    Text(engine.isRunning ? "End trip" : "Start collecting")
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(engine.isRunning ? Color.red.opacity(0.9) : Theme.accent, in: Capsule())
                .foregroundStyle(.white)
            }

            Spacer()

            Button {
                trackingMode = trackingMode == .follow ? .followWithHeading : .follow
            } label: {
                Image(systemName: trackingMode == .followWithHeading ? "location.north.line.fill" : "location.fill")
                    .font(.title3)
                    .frame(width: 48, height: 48)
                    .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel("Recentre")
        }
    }

    private func toggleTrip() {
        if !location.hasAnyPermission {
            location.requestWhenInUse()
            return
        }
        if settings.hapticsOnCollect {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        engine.toggleTrip()
    }

    // MARK: - Snapshot plumbing

    private func handleRegionChange(_ newRegion: MKCoordinateRegion) {
        region = newRegion
        data.ensureLoaded(for: newRegion)
        scheduleRebuild()
    }

    /// Rebuilds are debounced and coalesced: coverage changes on every fix, and
    /// each rebuild walks every visible segment.
    private func scheduleRebuild() {
        rebuildTask?.cancel()
        rebuildTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            rebuildSnapshot()
        }
    }

    private func rebuildSnapshot() {
        let visible = data.segments(in: region)
        let showUncollected = settings.showUncollectedStreets && visible.count <= uncollectedDrawLimit
        snapshot = CoverageSnapshot.build(
            segments: visible,
            coverage: coverage,
            hotSegmentIDs: engine.sessionSegmentIDs,
            showUncollected: showUncollected
        )
    }

    private func handleTap(_ coordinate: Coordinate) {
        let candidates = data.index.candidates(near: coordinate, radius: 40)
        let nearest = candidates.min { lhs, rhs in
            distance(from: coordinate, to: lhs) < distance(from: coordinate, to: rhs)
        }
        guard let nearest, distance(from: coordinate, to: nearest) < 40 else { return }
        selectedSegment = nearest
    }

    private func distance(from coordinate: Coordinate, to segment: StreetSegment) -> Double {
        var best = Double.greatestFiniteMagnitude
        guard segment.points.count > 1 else { return best }
        for i in 1..<segment.points.count {
            best = min(best, GeoMath.project(point: coordinate, onto: segment.points[i - 1], segment.points[i]).distance)
        }
        return best
    }

    private func centreOnUserIfPossible() {
        guard let current = location.latestLocation else {
            location.requestOneShotLocation()
            return
        }
        if region.center.latitude == 51.5074 && region.center.longitude == -0.1278 {
            region = MKCoordinateRegion(
                center: current.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
            data.ensureLoaded(for: region)
            scheduleRebuild()
        }
    }
}

/// Floating "+XP" toasts for things collected in the last few seconds.
private struct ScoreEventOverlay: View {

    @EnvironmentObject private var game: GameEngine
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(game.recentEvents) { event in
                    HStack(spacing: 8) {
                        Image(systemName: event.symbolName)
                            .foregroundStyle(Theme.accent)
                        Text(event.title)
                            .lineLimit(1)
                        Text("+\(event.xp)")
                            .fontWeight(.bold)
                            .monospacedDigit()
                    }
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.trailing, 16)
            .padding(.bottom, 92)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .allowsHitTesting(false)
        .animation(.spring(duration: 0.35), value: game.recentEvents.count)
        .onReceive(timer) { _ in
            game.expireEvents()
        }
    }
}
