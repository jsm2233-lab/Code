import CoreLocation
import XCTest
@testable import StreetCollector

final class MapMatcherTests: XCTestCase {

    /// An east-west street and a parallel one 25 m to the north, which is the
    /// case that breaks naive nearest-polyline matching.
    private func makeIndex() -> SpatialIndex {
        let index = SpatialIndex()
        index.insert(street(id: "main", lat: 51.5000, name: "Main Street"))
        index.insert(street(id: "parallel", lat: 51.50022, name: "Back Lane"))
        return index
    }

    private func street(id: String, lat: Double, name: String) -> StreetSegment {
        let points = [
            Coordinate(latitude: lat, longitude: -0.1000),
            Coordinate(latitude: lat, longitude: -0.0970),
        ]
        return StreetSegment(
            id: id,
            name: name,
            classification: .residential,
            points: points,
            length: GeoMath.polylineLength(points),
            isOneWay: false,
            tile: TileKey(containing: points[0])
        )
    }

    private func fix(
        lat: Double,
        lon: Double,
        course: Double = 90,
        speed: Double = 8,
        accuracy: Double = 8,
        at time: TimeInterval = 0
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: 5,
            course: course,
            speed: speed,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000 + time)
        )
    }

    func testMatchesNearestStreet() {
        var matcher = MapMatcher(index: makeIndex())
        let result = matcher.process(fix(lat: 51.50001, lon: -0.0990))
        XCTAssertEqual(result.match?.segment.id, "main")
        XCTAssertNil(result.rejectedReason)
    }

    func testRejectsPoorAccuracy() {
        var matcher = MapMatcher(index: makeIndex())
        let result = matcher.process(fix(lat: 51.50001, lon: -0.0990, accuracy: 120))
        XCTAssertNil(result.match)
        XCTAssertEqual(result.rejectedReason, .poorAccuracy)
    }

    func testStickinessKeepsMatchOnSameStreet() {
        var matcher = MapMatcher(index: makeIndex())
        _ = matcher.process(fix(lat: 51.50000, lon: -0.0995, at: 0))
        // Drifts almost exactly between the two streets. Without stickiness this
        // is a coin flip; with it, we stay on the street we were already on.
        let result = matcher.process(fix(lat: 51.50011, lon: -0.0990, at: 2))
        XCTAssertEqual(result.match?.segment.id, "main")
    }

    func testConsecutiveFixesBridgeTheStretchBetweenThem() {
        var matcher = MapMatcher(index: makeIndex())
        _ = matcher.process(fix(lat: 51.50000, lon: -0.0998, at: 0))
        let result = matcher.process(fix(lat: 51.50000, lon: -0.0980, at: 5))

        let traversal = try? XCTUnwrap(result.traversal)
        XCTAssertNotNil(traversal)
        // Roughly a tenth to nine tenths of the way along, covered in one go.
        XCTAssertGreaterThan((traversal?.upper ?? 0) - (traversal?.lower ?? 0), 0.4)
    }

    func testLongGapIsNotBridged() {
        var matcher = MapMatcher(index: makeIndex())
        _ = matcher.process(fix(lat: 51.50000, lon: -0.0998, at: 0))
        // Five minutes later: we have no idea whether the stretch between was
        // actually travelled, so only a small window around the fix is marked.
        let result = matcher.process(fix(lat: 51.50000, lon: -0.0980, at: 300))
        let span = (result.traversal?.upper ?? 0) - (result.traversal?.lower ?? 0)
        XCTAssertLessThan(span, 0.2)
    }

    func testNoCandidatesWhenFarFromAnyStreet() {
        var matcher = MapMatcher(index: makeIndex())
        let result = matcher.process(fix(lat: 51.6000, lon: -0.2000))
        XCTAssertEqual(result.rejectedReason, .noCandidates)
    }

    func testHeadingPenaltyRejectsPerpendicularTravel() {
        var matcher = MapMatcher(index: makeIndex())
        // Travelling due north, fast, right next to an east-west street: the
        // heading penalty should push the score past the acceptance threshold.
        let result = matcher.process(fix(lat: 51.50008, lon: -0.0990, course: 0, speed: 15))
        XCTAssertNil(result.match)
    }
}

final class SpatialIndexTests: XCTestCase {

    func testCandidateLookupAndTileRemoval() {
        let index = SpatialIndex()
        let points = [
            Coordinate(latitude: 51.5, longitude: -0.1),
            Coordinate(latitude: 51.5, longitude: -0.099),
        ]
        let tile = TileKey(containing: points[0])
        index.insert(
            StreetSegment(
                id: "a",
                name: "A Road",
                classification: .residential,
                points: points,
                length: GeoMath.polylineLength(points),
                isOneWay: false,
                tile: tile
            )
        )

        XCTAssertEqual(index.candidates(near: points[0], radius: 30).count, 1)
        XCTAssertTrue(index.candidates(near: Coordinate(latitude: 52, longitude: 0), radius: 30).isEmpty)

        index.removeSegments(inTile: tile)
        XCTAssertEqual(index.count, 0)
        XCTAssertTrue(index.candidates(near: points[0], radius: 30).isEmpty)
    }
}
