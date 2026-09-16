import MapKit
import SwiftUI

/// `MKMapView` wrapper. SwiftUI's `Map` can't host a custom `MKOverlayRenderer`,
/// and the whole visual identity of this app is one.
struct MapContainerView: UIViewRepresentable {

    let snapshot: CoverageSnapshot
    let style: MapStyleOption
    let showFog: Bool
    /// Drives the pulsing halo on the player dot.
    let isCollecting: Bool
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
        context.coordinator.setCollecting(isCollecting)

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

        func setCollecting(_ collecting: Bool) {
            guard let mapView,
                  let view = mapView.view(for: mapView.userLocation) as? PlayerAnnotationView else { return }
            view.setPulsing(collecting)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is MKUserLocation else { return nil }
            let view = PlayerAnnotationView(annotation: annotation, reuseIdentifier: "player")
            view.setPulsing(parent.isCollecting)
            return view
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

/// The player dot: a mint core with a halo that breathes while a trip is
/// running. MapKit's default blue dot is fine; it just isn't this app.
final class PlayerAnnotationView: MKAnnotationView {

    private let halo = CAShapeLayer()
    private let core = CAShapeLayer()
    private static let pulseKey = "collecting.pulse"

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 26, height: 26)
        // Keep it under the callout and off the hit-testing path; it is
        // decoration, not a target.
        isEnabled = false

        let mint = UIColor(red: 0.176, green: 0.878, blue: 0.647, alpha: 1)

        halo.path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 26, height: 26)).cgPath
        halo.fillColor = mint.withAlphaComponent(0.25).cgColor
        halo.position = .zero
        layer.addSublayer(halo)

        core.path = UIBezierPath(ovalIn: CGRect(x: 7, y: 7, width: 12, height: 12)).cgPath
        core.fillColor = mint.cgColor
        core.strokeColor = UIColor.white.withAlphaComponent(0.9).cgColor
        core.lineWidth = 2.5
        core.shadowColor = mint.cgColor
        core.shadowOpacity = 0.9
        core.shadowRadius = 6
        core.shadowOffset = .zero
        layer.addSublayer(core)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setPulsing(_ pulsing: Bool) {
        guard pulsing else {
            halo.removeAnimation(forKey: Self.pulseKey)
            halo.opacity = 0.35
            halo.transform = CATransform3DIdentity
            return
        }
        guard halo.animation(forKey: Self.pulseKey) == nil else { return }

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.8
        scale.toValue = 2.4

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.55
        fade.toValue = 0.0

        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 1.8
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        halo.add(group, forKey: Self.pulseKey)
    }
}
