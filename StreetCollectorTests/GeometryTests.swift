import CoreLocation
import XCTest
@testable import StreetCollector

final class GeoMathTests: XCTestCase {

    func testDistanceMatchesCoreLocation() {
        let a = Coordinate(latitude: 51.5074, longitude: -0.1278)
        let b = Coordinate(latitude: 51.5174, longitude: -0.1178)
        let expected = a.location.distance(from: b.location)
        XCTAssertEqual(GeoMath.distance(a, b), expected, accuracy: 2)
    }

    func testBearingDueEast() {
        let a = Coordinate(latitude: 0, longitude: 0)
        let b = Coordinate(latitude: 0, longitude: 1)
        XCTAssertEqual(GeoMath.bearing(from: a, to: b), 90, accuracy: 0.5)
    }

    func testUndirectedAngleDeltaTreatsReverseAsSame() {
        XCTAssertEqual(GeoMath.undirectedAngleDelta(10, 190), 0, accuracy: 0.001)
        XCTAssertEqual(GeoMath.undirectedAngleDelta(0, 90), 90, accuracy: 0.001)
    }

    func testProjectionOntoMidpoint() {
        let a = Coordinate(latitude: 51.50, longitude: -0.10)
        let b = Coordinate(latitude: 51.50, longitude: -0.09)
        // A point directly north of the midpoint should project to t = 0.5.
        let midLon = (a.longitude + b.longitude) / 2
        let point = Coordinate(latitude: 51.5002, longitude: midLon)
        let result = GeoMath.project(point: point, onto: a, b)
        XCTAssertEqual(result.t, 0.5, accuracy: 0.02)
        XCTAssertEqual(result.distance, 22, accuracy: 4)
    }

    func testProjectionClampsBeyondEndpoints() {
        let a = Coordinate(latitude: 0, longitude: 0)
        let b = Coordinate(latitude: 0, longitude: 0.001)
        let beyond = Coordinate(latitude: 0, longitude: 0.01)
        XCTAssertEqual(GeoMath.project(point: beyond, onto: a, b).t, 1.0, accuracy: 0.0001)
    }
}

final class IntervalSetTests: XCTestCase {

    func testInsertAndMerge() {
        var set = IntervalSet()
        set.insert(from: 0.1, to: 0.3)
        set.insert(from: 0.5, to: 0.7)
        XCTAssertEqual(set.intervals.count, 2)
        XCTAssertEqual(set.coveredFraction, 0.4, accuracy: 0.0001)

        // Bridging interval collapses the two into one.
        set.insert(from: 0.25, to: 0.55)
        XCTAssertEqual(set.intervals.count, 1)
        XCTAssertEqual(set.coveredFraction, 0.6, accuracy: 0.0001)
    }

    func testInsertClampsToUnitRange() {
        var set = IntervalSet()
        set.insert(from: -0.5, to: 1.5)
        XCTAssertEqual(set.coveredFraction, 1.0, accuracy: 0.0001)
    }

    func testReversedBoundsAreNormalised() {
        var set = IntervalSet()
        set.insert(from: 0.8, to: 0.2)
        XCTAssertEqual(set.coveredFraction, 0.6, accuracy: 0.0001)
    }

    func testSliversAreIgnored() {
        var set = IntervalSet()
        set.insert(from: 0.5, to: 0.50001)
        XCTAssertTrue(set.isEmpty)
    }

    func testRepeatedIdenticalInsertsDoNotAccumulate() {
        var set = IntervalSet()
        for _ in 0..<50 { set.insert(from: 0.2, to: 0.4) }
        XCTAssertEqual(set.intervals.count, 1)
        XCTAssertEqual(set.coveredFraction, 0.2, accuracy: 0.0001)
    }
}
