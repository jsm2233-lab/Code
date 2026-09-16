import MapKit
import SwiftUI

struct TripsScreen: View {

    @EnvironmentObject private var trips: TripStore

    var body: some View {
        List {
            ForEach(trips.trips) { trip in
                NavigationLink {
                    TripDetailScreen(trip: trip)
                } label: {
                    TripRow(trip: trip)
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    trips.delete(trips.trips[index])
                }
            }
        }
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
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

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
                    Card(title: "Collected on this trip") {
                        ForEach(trip.completedSegmentIDs.prefix(40), id: \.self) { id in
                            HStack {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(Theme.collected)
                                    .font(.caption)
                                Text(data.segment(id: id)?.displayName ?? "Street no longer in map data")
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Spacer()
                            }
                        }
                        if trip.completedSegmentIDs.count > 40 {
                            Text("and \(trip.completedSegmentIDs.count - 40) more")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle(trip.mode.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    guard let gpx = ExportService.gpx(for: trip),
                          let url = ExportService.write(gpx, named: "trip-\(trip.id.uuidString).gpx") else { return }
                    shareItem = ShareItem(url: url)
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

/// Static map showing one trip's track.
struct TripMapView: UIViewRepresentable {

    let track: [Coordinate]

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isUserInteractionEnabled = true
        map.pointOfInterestFilter = .excludingAll
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
            return renderer
        }
    }
}
