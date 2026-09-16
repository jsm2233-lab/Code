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
    var coordinate: CLLocationCoordinate2D { MKMapPoint(x: MKMapRect.world.midX, y: MKMapRect.world.midY).coordinate }
    var boundingMapRect: MKMapRect { MKMapRect.world }
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

    /// Signal colours, matching the SwiftUI palette exactly. Duplicated here
    /// because `CGContext` wants `CGColor` and the renderer runs off the main
    /// actor, where the SwiftUI `Theme` is not reachable.
    private enum Ink {
        static let collected = UIColor(red: 0.176, green: 0.878, blue: 0.647, alpha: 1)
        static let partial = UIColor(red: 1.000, green: 0.737, blue: 0.239, alpha: 1)
        static let hot = UIColor(red: 0.357, green: 0.784, blue: 1.000, alpha: 1)
        static let uncollected = UIColor(red: 0.420, green: 0.478, blue: 0.549, alpha: 1)
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
            // Uncollected streets are barely there — a suggestion of a grid
            // waiting to be lit, not a second map competing with the first.
            context.setStrokeColor(Ink.uncollected.withAlphaComponent(0.28).cgColor)
            context.setLineWidth(baseWidth * 0.55)
            for drawable in current.drawables where drawable.coveredRuns.isEmpty {
                guard intersects(drawable.points, mapRect) else { continue }
                stroke(drawable.points, in: context)
            }
        }

        // Three passes per lit street: a wide haze, a mid glow, then a bright
        // core. Layering cheap strokes fakes a neon bloom convincingly and
        // costs a fraction of a real blur.
        let passes: [(width: CGFloat, alpha: CGFloat)] = [
            (baseWidth * 3.6, 0.13),
            (baseWidth * 1.9, 0.30),
            (baseWidth, 1.0),
        ]

        for drawable in current.drawables where !drawable.coveredRuns.isEmpty {
            guard intersects(drawable.points, mapRect) else { continue }

            let colour: UIColor
            if drawable.isHot {
                colour = Ink.hot
            } else if drawable.isComplete {
                colour = Ink.collected
            } else {
                colour = Ink.partial
            }

            for pass in passes {
                context.setStrokeColor(colour.withAlphaComponent(pass.alpha).cgColor)
                context.setLineWidth(pass.width)
                for run in drawable.coveredRuns { stroke(run, in: context) }
            }

            // Finished streets get a white-hot centre line, so a fully
            // collected street is unmistakable from a nearly-collected one.
            if drawable.isComplete {
                context.setStrokeColor(UIColor.white.withAlphaComponent(0.55).cgColor)
                context.setLineWidth(max(0.6, baseWidth * 0.3))
                for run in drawable.coveredRuns { stroke(run, in: context) }
            }
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
    var coordinate: CLLocationCoordinate2D { MKMapPoint(x: MKMapRect.world.midX, y: MKMapRect.world.midY).coordinate }
    var boundingMapRect: MKMapRect { MKMapRect.world }
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

        context.setFillColor(UIColor(red: 0.039, green: 0.055, blue: 0.078, alpha: 0.72).cgColor)
        context.fill(rect(for: mapRect))

        // Clearing is a destination-out stroke, so the fog is cut away rather
        // than painted over. Stacking a wide faint pass under a narrow opaque
        // one gives the corridor a soft edge instead of a hard slot.
        context.setBlendMode(.destinationOut)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let passes: [(width: CGFloat, alpha: CGFloat)] = [
            (max(44, 62 / zoomScale), 0.35),
            (max(26, 38 / zoomScale), 0.55),
            (max(15, 22 / zoomScale), 1.0),
        ]

        for pass in passes {
            context.setStrokeColor(UIColor.black.withAlphaComponent(pass.alpha).cgColor)
            context.setLineWidth(pass.width)
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
        }

        context.setBlendMode(.normal)
    }
}
