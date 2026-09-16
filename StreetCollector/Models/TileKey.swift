import Foundation
import MapKit

/// Street data is fetched, cached and expired a tile at a time.
///
/// Tiles are a fixed 0.02° grid — roughly 2.2 km north-south, and less
/// east-west the further you get from the equator. Small enough that a single
/// Overpass query returns quickly, big enough that a normal commute doesn't
/// thrash the network.
struct TileKey: Codable, Hashable, CustomStringConvertible {

    static let size: Double = 0.02

    let x: Int   // longitude index
    let y: Int   // latitude index

    init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    init(containing coordinate: Coordinate) {
        self.x = Int(floor(coordinate.longitude / Self.size))
        self.y = Int(floor(coordinate.latitude / Self.size))
    }

    var description: String { "\(x)_\(y)" }

    var south: Double { Double(y) * Self.size }
    var west: Double { Double(x) * Self.size }
    var north: Double { south + Self.size }
    var east: Double { west + Self.size }

    var center: Coordinate {
        Coordinate(latitude: south + Self.size / 2, longitude: west + Self.size / 2)
    }

    /// The 3x3 block centred on this tile. Prefetching the ring means the user
    /// rarely crosses into an unloaded tile at speed.
    var neighbourhood: [TileKey] {
        var keys: [TileKey] = []
        for dx in -1...1 {
            for dy in -1...1 {
                keys.append(TileKey(x: x + dx, y: y + dy))
            }
        }
        return keys
    }

    /// Tiles intersecting a map region, capped so a zoomed-out map doesn't try
    /// to fetch a continent.
    static func tiles(covering region: MKCoordinateRegion, limit: Int = 64) -> [TileKey] {
        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2

        let x0 = Int(floor(minLon / size)), x1 = Int(floor(maxLon / size))
        let y0 = Int(floor(minLat / size)), y1 = Int(floor(maxLat / size))

        guard (x1 - x0 + 1) * (y1 - y0 + 1) <= limit else { return [] }

        var keys: [TileKey] = []
        for x in x0...x1 {
            for y in y0...y1 {
                keys.append(TileKey(x: x, y: y))
            }
        }
        return keys
    }
}
