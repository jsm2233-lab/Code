import XCTest
@testable import StreetCollector

final class LevelTests: XCTestCase {

    func testLevelCurveIsMonotonic() {
        var previous = -1
        for level in 1...Level.maxLevel {
            let required = Level.xpRequired(for: level)
            XCTAssertGreaterThan(required, previous)
            previous = required
        }
    }

    func testLevelForXP() {
        XCTAssertEqual(Level.level(forXP: 0), 1)
        XCTAssertEqual(Level.level(forXP: Level.xpRequired(for: 5)), 5)
        XCTAssertEqual(Level.level(forXP: Level.xpRequired(for: 5) - 1), 4)
    }

    func testLevelIsCapped() {
        XCTAssertEqual(Level.level(forXP: 100_000_000), Level.maxLevel)
    }
}

final class TravelModeTests: XCTestCase {

    func testInference() {
        XCTAssertEqual(TravelMode.inferred(fromSpeed: 1.2), .walking)
        XCTAssertEqual(TravelMode.inferred(fromSpeed: 5.0), .cycling)
        XCTAssertEqual(TravelMode.inferred(fromSpeed: 20.0), .driving)
        XCTAssertEqual(TravelMode.inferred(fromSpeed: -1), .unknown)
    }
}

final class OverpassParsingTests: XCTestCase {

    /// Two ways sharing a middle node must split into three intersection-to-
    /// intersection segments, not two whole ways.
    func testWaySplittingAtSharedNodes() {
        let elements = [
            OverpassElement(
                id: 1,
                nodes: [100, 101, 102],
                geometry: [
                    .init(lat: 51.5000, lon: -0.1000),
                    .init(lat: 51.5000, lon: -0.0990),
                    .init(lat: 51.5000, lon: -0.0980),
                ],
                tags: ["highway": "residential", "name": "Main Street"]
            ),
            OverpassElement(
                id: 2,
                nodes: [200, 101, 201],
                geometry: [
                    .init(lat: 51.4990, lon: -0.0990),
                    .init(lat: 51.5000, lon: -0.0990),
                    .init(lat: 51.5010, lon: -0.0990),
                ],
                tags: ["highway": "residential", "name": "Cross Road"]
            ),
        ]

        let tile = TileKey(containing: Coordinate(latitude: 51.5, longitude: -0.1))
        let segments = OverpassClient.segments(from: elements, tile: tile)

        XCTAssertEqual(segments.filter { $0.name == "Main Street" }.count, 2)
        XCTAssertEqual(segments.filter { $0.name == "Cross Road" }.count, 2)
        XCTAssertTrue(segments.allSatisfy { $0.length > 5 })
    }

    func testUnsupportedHighwayTypesAreDropped() {
        let elements = [
            OverpassElement(
                id: 3,
                nodes: [1, 2],
                geometry: [
                    .init(lat: 51.5, lon: -0.1),
                    .init(lat: 51.5, lon: -0.099),
                ],
                tags: ["highway": "proposed"]
            )
        ]
        let tile = TileKey(containing: Coordinate(latitude: 51.5, longitude: -0.1))
        XCTAssertTrue(OverpassClient.segments(from: elements, tile: tile).isEmpty)
    }
}

final class SegmentGeometryTests: XCTestCase {

    private func makeSegment() -> StreetSegment {
        let points = [
            Coordinate(latitude: 51.5, longitude: -0.100),
            Coordinate(latitude: 51.5, longitude: -0.098),
            Coordinate(latitude: 51.5, longitude: -0.096),
        ]
        return StreetSegment(
            id: "s",
            name: "Test Street",
            classification: .residential,
            points: points,
            length: GeoMath.polylineLength(points),
            isOneWay: false,
            tile: TileKey(containing: points[0])
        )
    }

    func testCoordinateAtFraction() {
        let segment = makeSegment()
        let mid = segment.coordinate(atFraction: 0.5)
        XCTAssertEqual(mid.longitude, -0.098, accuracy: 0.0002)
    }

    func testPartialPolylineStaysWithinBounds() {
        let segment = makeSegment()
        let partial = segment.polyline(from: 0.25, to: 0.75)
        XCTAssertGreaterThanOrEqual(partial.count, 2)
        XCTAssertGreaterThan(partial.first!.longitude, -0.100)
        XCTAssertLessThan(partial.last!.longitude, -0.096)
    }
}

final class TileKeyTests: XCTestCase {

    func testTileContainment() {
        let tile = TileKey(containing: Coordinate(latitude: 51.507, longitude: -0.128))
        XCTAssertTrue(tile.south <= 51.507 && tile.north > 51.507)
        XCTAssertTrue(tile.west <= -0.128 && tile.east > -0.128)
    }

    func testNeighbourhoodIsNineTiles() {
        XCTAssertEqual(TileKey(x: 0, y: 0).neighbourhood.count, 9)
    }
}
