import MapKit
import SwiftUI

struct TripsScreen: View {

    @EnvironmentObject private var trips: TripStore

    var body: some View {
        List {
            ForEach(trips.trips) { trip in
                ZStack {
                    // The chevron a NavigationLink draws would sit on top of a
                    // card with its own trailing content, so the link is hidden
                    // behind the row instead.
                    NavigationLink { TripDetailScreen(trip: trip) } label: { EmptyView() }
                        .opacity(0)
                    GlassPanel(tint: Theme.accent) {
                        TripRow(trip: trip)
                    }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
            .onDelete { offsets in
                for index in offsets {
                    trips.delete(trips.trips[index])
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .cityBackground()
        .navigationTitle("Trips")
        .overlay {
            if trips.trips.isEmpty {
                EmptyStateView(
                    symbolName: "figure.walk.motion",
                    title: "No trips yet",
                    message: "Hit start on the map and go for a wander."
                )
            }
        }
    }
}

struct TripDetailScreen: View {

    let trip: Trip

    @EnvironmentObject private var data: StreetDataStore
    @State private var shareItem: ShareItem?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                TripMapView(track: trip.track)
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                            .strokeBorder(Theme.accent.opacity(0.25), lineWidth: 1)
                    }
                    .shadow(color: Theme.accent.opacity(0.2), radius: 16, y: 6)

                HStack(spacing: 12) {
                    StatTile(value: Format.distance(trip.distanceMetres), label: "Distance", symbolName: "arrow.forward")
                    StatTile(value: Format.distance(trip.newStreetMetres), label: "New streets", symbolName: "sparkles", tint: Theme.partial)
                }
                HStack(spacing: 12) {
                    StatTile(value: Format.duration(trip.duration), label: "Duration", symbolName: "clock")
                    StatTile(value: "+\(Format.xp(trip.xpEarned))", label: "XP earned", symbolName: "star.fill", tint: .yellow)
                }
                HStack(spacing: 12) {
                    StatTile(value: Format.percent(trip.noveltyRatio), label: "Fresh ground", symbolName: "percent", tint: Theme.hot)
                    StatTile(value: Format.speed(trip.averageSpeed), label: "Average speed", symbolName: trip.mode.symbolName, tint: .purple)
                }

                if !trip.completedSegmentIDs.isEmpty {
                    Card(title: "Collected on this trip", symbol: "checkmark.seal.fill") {
                        ForEach(trip.completedSegmentIDs.prefix(40), id: \.self) { id in
                            HStack(spacing: 9) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(Theme.font(11, .bold))
                                    .foregroundStyle(Theme.collected)
                                Text(data.segment(id: id)?.displayName ?? "Street no longer in map data")
                                    .font(Theme.font(13, .medium))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        }
                        if trip.completedSegmentIDs.count > 40 {
                            Text("and \(trip.completedSegmentIDs.count - 40) more")
                                .font(Theme.caption)
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }
            }
            .padding(16)
        }
        .cityBackground()
        .navigationTitle(trip.mode.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    guard let gpx = ExportService.gpx(for: trip),
                          let url = ExportService.write(gpx, named: "trip-\(trip.id.uuidString).gpx") else { return }
                    shareItem = ShareItem(url: url)
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

/// Static map showing one trip's track.
struct TripMapView: UIViewRepresentable {

    let track: [Coordinate]

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isUserInteractionEnabled = true
        map.pointOfInterestFilter = .excludingAll
        map.overrideUserInterfaceStyle = .dark
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
        configuration.emphasisStyle = .muted
        map.preferredConfiguration = configuration
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)
        guard track.count > 1 else { return }
        let coordinates = track.map(\.clCoordinate)
        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        map.addOverlay(polyline)
        map.setVisibleMapRect(
            polyline.boundingMapRect,
            edgePadding: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24),
            animated: false
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor(Theme.accent)
            renderer.lineWidth = 5
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }
    }
}
