import Foundation

/// A uniform-grid index over street segments.
///
/// The matcher runs on every location update, and a city's worth of segments is
/// tens of thousands of polylines, so a linear scan is out. A grid is enough:
/// query radii are always small (tens of metres) and segments are short, so the
/// candidate set per query is a handful.
final class SpatialIndex {

    /// ~0.0025° is roughly 275 m north-south. Comfortably larger than the
    /// longest segment we expect after splitting at intersections, which keeps
    /// the per-segment cell list short.
    private static let cellSize: Double = 0.0025

    private var cells: [Cell: [String]] = [:]
    private var segments: [String: StreetSegment] = [:]

    private struct Cell: Hashable {
        let x: Int
        let y: Int
    }

    var count: Int { segments.count }

    var allSegments: [StreetSegment] { Array(segments.values) }

    func segment(id: String) -> StreetSegment? { segments[id] }

    func insert(_ segment: StreetSegment) {
        guard segments[segment.id] == nil else { return }
        segments[segment.id] = segment
        for cell in cells(for: segment.boundingBox) {
            cells[cell, default: []].append(segment.id)
        }
    }

    func insert(contentsOf newSegments: [StreetSegment]) {
        for segment in newSegments { insert(segment) }
    }

    func removeSegments(inTile tile: TileKey) {
        let doomed = segments.values.filter { $0.tile == tile }
        guard !doomed.isEmpty else { return }
        let doomedIDs = Set(doomed.map(\.id))
        for segment in doomed {
            segments.removeValue(forKey: segment.id)
        }
        for cell in Set(doomed.flatMap { cells(for: $0.boundingBox) }) {
            cells[cell] = cells[cell]?.filter { !doomedIDs.contains($0) }
            if cells[cell]?.isEmpty == true { cells.removeValue(forKey: cell) }
        }
    }

    func removeAll() {
        cells.removeAll()
        segments.removeAll()
    }

    /// Every segment whose bounding box comes within `radius` metres of `point`.
    func candidates(near point: Coordinate, radius: Double) -> [StreetSegment] {
        let dLat = radius / GeoMath.metresPerDegreeLat
        let dLon = radius / max(1, GeoMath.metresPerDegreeLon(atLatitude: point.latitude))

        let x0 = Int(floor((point.longitude - dLon) / Self.cellSize))
        let x1 = Int(floor((point.longitude + dLon) / Self.cellSize))
        let y0 = Int(floor((point.latitude - dLat) / Self.cellSize))
        let y1 = Int(floor((point.latitude + dLat) / Self.cellSize))

        var seen = Set<String>()
        var result: [StreetSegment] = []
        for x in x0...x1 {
            for y in y0...y1 {
                guard let ids = cells[Cell(x: x, y: y)] else { continue }
                for id in ids where !seen.contains(id) {
                    seen.insert(id)
                    guard let segment = segments[id] else { continue }
                    if segment.boundingBox.expanded(byMetres: radius).contains(point) {
                        result.append(segment)
                    }
                }
            }
        }
        return result
    }

    func segments(inTile tile: TileKey) -> [StreetSegment] {
        segments.values.filter { $0.tile == tile }
    }

    private func cells(for box: BoundingBox) -> [Cell] {
        let x0 = Int(floor(box.minLongitude / Self.cellSize))
        let x1 = Int(floor(box.maxLongitude / Self.cellSize))
        let y0 = Int(floor(box.minLatitude / Self.cellSize))
        let y1 = Int(floor(box.maxLatitude / Self.cellSize))
        var result: [Cell] = []
        for x in x0...x1 {
            for y in y0...y1 {
                result.append(Cell(x: x, y: y))
            }
        }
        return result
    }
}
