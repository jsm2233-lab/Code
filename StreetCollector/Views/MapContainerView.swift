import MapKit
import SwiftUI

/// `MKMapView` wrapper. SwiftUI's `Map` can't host a custom `MKOverlayRenderer`,
/// and the whole visual identity of this app is one.
struct MapContainerView: UIViewRepresentable {

    let snapshot: CoverageSnapshot
    let style: MapStyleOption
    let showFog: Bool
    @Binding var trackingMode: MKUserTrackingMode
    /// Reported after the user pans or zooms, debounced by the coordinator.
    let onRegionChange: (MKCoordinateRegion) -> Void
    /// Fired when the user taps a street, with the tapped coordinate.
    let onTap: (Coordinate) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = true
        map.showsScale = true
        map.pointOfInterestFilter = .excludingAll
        map.userTrackingMode = trackingMode
        map.addOverlay(context.coordinator.fogOverlay, level: .aboveRoads)
        map.addOverlay(context.coordinator.coverageOverlay, level: .aboveRoads)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)
        context.coordinator.mapView = map

        apply(style: style, to: map)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.coverageRenderer?.update(snapshot)
        context.coordinator.fogRenderer?.update(showFog ? snapshot : .empty)
        context.coordinator.setFogHidden(!showFog)

        if map.userTrackingMode != trackingMode {
            map.setUserTrackingMode(trackingMode, animated: true)
        }
        if context.coordinator.appliedStyle != style {
            apply(style: style, to: map)
            context.coordinator.appliedStyle = style
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private func apply(style: MapStyleOption, to map: MKMapView) {
        switch style {
        case .standard:
            map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
        case .muted:
            let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
            configuration.emphasisStyle = .muted
            map.preferredConfiguration = configuration
        case .satellite:
            map.preferredConfiguration = MKHybridMapConfiguration()
        case .dark:
            let configuration = MKStandardMapConfiguration(elevationStyle: .flat)
            configuration.emphasisStyle = .muted
            map.preferredConfiguration = configuration
            map.overrideUserInterfaceStyle = .dark
        }
        if style != .dark {
            map.overrideUserInterfaceStyle = .unspecified
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {

        var parent: MapContainerView
        weak var mapView: MKMapView?
        let coverageOverlay = CoverageOverlay()
        let fogOverlay = FogOverlay()
        var coverageRenderer: CoverageOverlayRenderer?
        var fogRenderer: FogOverlayRenderer?
        var appliedStyle: MapStyleOption
        private var regionWorkItem: DispatchWorkItem?

        init(parent: MapContainerView) {
            self.parent = parent
            self.appliedStyle = parent.style
        }

        func setFogHidden(_ hidden: Bool) {
            fogRenderer?.alpha = hidden ? 0 : 1
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if overlay === coverageOverlay {
                let renderer = coverageRenderer ?? CoverageOverlayRenderer(overlay: overlay)
                coverageRenderer = renderer
                renderer.update(parent.snapshot)
                return renderer
            }
            if overlay === fogOverlay {
                let renderer = fogRenderer ?? FogOverlayRenderer(overlay: overlay)
                fogRenderer = renderer
                renderer.update(parent.showFog ? parent.snapshot : .empty)
                renderer.alpha = parent.showFog ? 1 : 0
                return renderer
            }
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor(red: 0.36, green: 0.74, blue: 1.0, alpha: 0.8)
                renderer.lineWidth = 4
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        /// Region changes fire continuously during a pan; rebuilding the
        /// snapshot on each one would stutter. Coalesce to the last one.
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            regionWorkItem?.cancel()
            let region = mapView.region
            let item = DispatchWorkItem { [weak self] in
                self?.parent.onRegionChange(region)
            }
            regionWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
        }

        func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
            if parent.trackingMode != mode {
                parent.trackingMode = mode
            }
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let mapView else { return }
            let point = recognizer.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            parent.onTap(Coordinate(coordinate))
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
