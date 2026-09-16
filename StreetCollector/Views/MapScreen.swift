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
    @State private var pulse = false

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
                isCollecting: engine.isRunning,
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
        .onAppear {
            centreOnUserIfPossible()
            pulse = true
        }
        .onChange(of: coverage.revision) { _, _ in scheduleRebuild() }
        .onChange(of: data.segmentCount) { _, _ in scheduleRebuild() }
        .onChange(of: settings.showUncollectedStreets) { _, _ in scheduleRebuild() }
        .onChange(of: location.latestLocation?.coordinate.latitude) { _, _ in
            centreOnUserIfPossible()
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 14) {
            Button {
                showSuggestions = true
            } label: {
                Image(systemName: "scope")
            }
            .buttonStyle(GlassButtonStyle(tint: Theme.partial))
            .accessibilityLabel("Nearby streets to collect")

            Spacer(minLength: 0)

            Button(action: toggleTrip) {
                HStack(spacing: 9) {
                    Image(systemName: engine.isRunning ? "stop.fill" : "play.fill")
                    Text(engine.isRunning ? "End trip" : "Start collecting")
                }
            }
            .buttonStyle(
                NeonButtonStyle(
                    gradient: engine.isRunning ? Theme.dangerGradient : Theme.primaryGradient,
                    glowColor: engine.isRunning ? Theme.magenta : Theme.accent
                )
            )
            .overlay(alignment: .top) {
                // A soft ring that breathes while collecting, echoing the
                // player dot on the map.
                if engine.isRunning {
                    Capsule()
                        .strokeBorder(Theme.magenta.opacity(0.5), lineWidth: 2)
                        .scaleEffect(pulse ? 1.12 : 1)
                        .opacity(pulse ? 0 : 0.8)
                        .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulse)
                        .allowsHitTesting(false)
                }
            }

            Spacer(minLength: 0)

            Button {
                trackingMode = trackingMode == .follow ? .followWithHeading : .follow
            } label: {
                Image(systemName: trackingMode == .followWithHeading ? "location.north.line.fill" : "location.fill")
            }
            .buttonStyle(GlassButtonStyle(tint: Theme.hot))
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
///
/// They stack from the bottom right and fly in from the edge, which keeps them
/// clear of the HUD and out of the way of the thumb.
private struct ScoreEventOverlay: View {

    @EnvironmentObject private var game: GameEngine
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                ForEach(game.recentEvents) { event in
                    HStack(spacing: 9) {
                        Image(systemName: event.symbolName)
                            .font(Theme.font(13, .bold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 26, height: 26)
                            .background(Theme.primaryGradient, in: Circle())

                        Text(event.title)
                            .font(Theme.font(13, .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text("+\(event.xp)")
                            .font(Theme.numeric(13, .heavy))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.leading, 6)
                    .padding(.trailing, 14)
                    .padding(.vertical, 6)
                    .background(Theme.surface.opacity(0.92), in: Capsule())
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
                    .shadow(color: Theme.accent.opacity(0.25), radius: 12, y: 4)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.8)),
                        removal: .opacity
                    ))
                }
            }
            .padding(.trailing, 16)
            .padding(.bottom, 100)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .allowsHitTesting(false)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: game.recentEvents.count)
        .onReceive(timer) { _ in
            game.expireEvents()
        }
    }
}
