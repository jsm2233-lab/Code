import MapKit
import UIKit

/// An immutable, thread-safe picture of what to draw.
///
/// `MKOverlayRenderer.draw` runs on MapKit's own background threads, so it
/// cannot touch the `@MainActor` stores. Instead the main actor builds one of
/// these whenever coverage or the visible region changes, and the renderer only
/// ever reads it.
struct CoverageSnapshot {

    struct Drawable {
        let points: [MKMapPoint]
        /// Covered stretches as sub-polylines, already resolved.
        let coveredRuns: [[MKMapPoint]]
        let classification: StreetClassification
        let isComplete: Bool
        let isHot: Bool
    }

    let drawables: [Drawable]
    let showUncollected: Bool

    static let empty = CoverageSnapshot(drawables: [], showUncollected: true)

    @MainActor
    static func build(
        segments: [StreetSegment],
        coverage: CoverageStore,
        hotSegmentIDs: Set<String>,
        showUncollected: Bool
    ) -> CoverageSnapshot {
        var drawables: [Drawable] = []
        drawables.reserveCapacity(segments.count)

        for segment in segments {
            let entry = coverage.coverage(for: segment.id)
            if entry == nil && !showUncollected { continue }

            let runs: [[MKMapPoint]] = (entry?.intervals.intervals ?? []).compactMap { interval in
                let points = segment.polyline(from: interval.lower, to: interval.upper)
                guard points.count > 1 else { return nil }
                return points.map { MKMapPoint($0.clCoordinate) }
            }

            drawables.append(
                Drawable(
                    points: segment.points.map { MKMapPoint($0.clCoordinate) },
                    coveredRuns: runs,
                    classification: segment.classification,
                    isComplete: entry?.isComplete ?? false,
                    isHot: hotSegmentIDs.contains(segment.id)
                )
            )
        }

        return CoverageSnapshot(drawables: drawables, showUncollected: showUncollected)
    }
}

/// World-spanning overlay; the renderer clips to whatever tile it's asked for.
///
/// One overlay for the whole collection beats one `MKPolyline` per segment:
/// tens of thousands of overlay objects makes MapKit crawl, while a single
/// renderer draws only what's on screen.
final class CoverageOverlay: NSObject, MKOverlay {
    var coordinate: CLLocationCoordinate2D { MKMapPoint(x: MKMapRectWorld.midX, y: MKMapRectWorld.midY).coordinate }
    var boundingMapRect: MKMapRect { MKMapRectWorld }
}

final class CoverageOverlayRenderer: MKOverlayRenderer {

    private let lock = NSLock()
    private var snapshot: CoverageSnapshot = .empty

    func update(_ newSnapshot: CoverageSnapshot) {
        lock.lock()
        snapshot = newSnapshot
        lock.unlock()
        setNeedsDisplay()
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        lock.lock()
        let current = snapshot
        lock.unlock()

        // Line widths are specified in points and scaled into map space, so
        // streets stay a sensible thickness at every zoom level.
        let scale = 1 / zoomScale
        let baseWidth = max(2.0, 3.5 * scale)

        context.setLineCap(.round)
        context.setLineJoin(.round)

        if current.showUncollected {
            context.setStrokeColor(UIColor(white: 0.55, alpha: 0.35).cgColor)
            context.setLineWidth(baseWidth * 0.7)
            for drawable in current.drawables where drawable.coveredRuns.isEmpty {
                guard intersects(drawable.points, mapRect) else { continue }
                stroke(drawable.points, in: context)
            }
        }

        for drawable in current.drawables where !drawable.coveredRuns.isEmpty {
            guard intersects(drawable.points, mapRect) else { continue }

            let colour: UIColor
            if drawable.isHot {
                colour = UIColor(red: 0.36, green: 0.74, blue: 1.0, alpha: 0.95)
            } else if drawable.isComplete {
                colour = UIColor(red: 0.16, green: 0.83, blue: 0.62, alpha: 0.95)
            } else {
                colour = UIColor(red: 0.99, green: 0.74, blue: 0.24, alpha: 0.9)
            }

            // A soft wide pass under a crisp narrow one reads as a glow without
            // the cost of a real blur.
            context.setStrokeColor(colour.withAlphaComponent(0.25).cgColor)
            context.setLineWidth(baseWidth * 2.4)
            for run in drawable.coveredRuns { stroke(run, in: context) }

            context.setStrokeColor(colour.cgColor)
            context.setLineWidth(baseWidth)
            for run in drawable.coveredRuns { stroke(run, in: context) }
        }
    }

    private func stroke(_ points: [MKMapPoint], in context: CGContext) {
        guard points.count > 1 else { return }
        context.beginPath()
        context.move(to: point(for: points[0]))
        for i in 1..<points.count {
            context.addLine(to: point(for: points[i]))
        }
        context.strokePath()
    }

    private func intersects(_ points: [MKMapPoint], _ rect: MKMapRect) -> Bool {
        guard let first = points.first else { return false }
        var box = MKMapRect(origin: first, size: MKMapSize(width: 0, height: 0))
        for point in points.dropFirst() {
            box = box.union(MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0)))
        }
        return box.intersects(rect)
    }
}

/// Darkens everything you haven't been down, and punches holes along the
/// streets you have. This is the "collection" made visible: a black city that
/// lights up street by street.
final class FogOverlay: NSObject, MKOverlay {
    var coordinate: CLLocationCoordinate2D { MKMapPoint(x: MKMapRectWorld.midX, y: MKMapRectWorld.midY).coordinate }
    var boundingMapRect: MKMapRect { MKMapRectWorld }
}

final class FogOverlayRenderer: MKOverlayRenderer {

    private let lock = NSLock()
    private var snapshot: CoverageSnapshot = .empty

    func update(_ newSnapshot: CoverageSnapshot) {
        lock.lock()
        snapshot = newSnapshot
        lock.unlock()
        setNeedsDisplay()
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        lock.lock()
        let current = snapshot
        lock.unlock()

        context.setFillColor(UIColor(white: 0.04, alpha: 0.55).cgColor)
        context.fill(rect(for: mapRect))

        // Clearing is a destination-out stroke, so the fog is cut away rather
        // than painted over. Needs a transparency layer or it would punch a
        // hole through the map tiles underneath.
        context.setBlendMode(.destinationOut)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(UIColor.black.cgColor)
        context.setLineWidth(max(18, 26 / zoomScale))

        for drawable in current.drawables {
            for run in drawable.coveredRuns where run.count > 1 {
                context.beginPath()
                context.move(to: point(for: run[0]))
                for i in 1..<run.count {
                    context.addLine(to: point(for: run[i]))
                }
                context.strokePath()
            }
        }

        context.setBlendMode(.normal)
    }
}
