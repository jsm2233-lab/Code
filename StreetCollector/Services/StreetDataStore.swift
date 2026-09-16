import Foundation
import MapKit
import os

/// Owns the in-memory street graph and its on-disk tile cache.
@MainActor
final class StreetDataStore: ObservableObject {

    /// Tiles older than this are refetched. Streets change slowly; a fortnight
    /// is a reasonable compromise between freshness and not re-downloading a
    /// city every week.
    private static let tileMaxAge: TimeInterval = 14 * 24 * 3600

    @Published private(set) var loadedTiles: Set<TileKey> = []
    @Published private(set) var loadingTiles: Set<TileKey> = []
    @Published private(set) var lastError: String?
    @Published private(set) var segmentCount: Int = 0

    let index = SpatialIndex()

    private let client: OverpassClient
    private let store: FileStore
    private let logger = Logger(subsystem: "com.example.StreetCollector", category: "StreetData")
    private var tileFetchedAt: [TileKey: Date] = [:]
    private var failedAttempts: [TileKey: Int] = [:]
    private var inFlight: [TileKey: Task<Void, Never>] = [:]

    private static let manifestName = "tile_manifest.json"

    init(client: OverpassClient = OverpassClient(), store: FileStore = .shared) {
        self.client = client
        self.store = store
        loadManifest()
    }

    // MARK: - Loading

    /// Makes sure the tile containing `coordinate` and its immediate ring are
    /// available. Called as the user moves.
    func ensureLoaded(around coordinate: Coordinate) {
        let centre = TileKey(containing: coordinate)
        load(tiles: centre.neighbourhood)
    }

    /// Loads whatever the visible map region needs, ignoring zoomed-out regions
    /// that would ask for hundreds of tiles.
    func ensureLoaded(for region: MKCoordinateRegion) {
        load(tiles: TileKey.tiles(covering: region, limit: 25))
    }

    func load(tiles: [TileKey]) {
        for tile in tiles {
            guard !loadedTiles.contains(tile), inFlight[tile] == nil else { continue }
            // Back off exponentially on tiles that keep failing, so a genuinely
            // empty or unreachable tile doesn't retry on every location update.
            let attempts = failedAttempts[tile] ?? 0
            guard attempts < 5 else { continue }

            inFlight[tile] = Task { [weak self] in
                await self?.loadTile(tile)
            }
        }
    }

    private func loadTile(_ tile: TileKey) async {
        defer { inFlight[tile] = nil }

        loadingTiles.insert(tile)
        defer { loadingTiles.remove(tile) }

        if let cached = cachedSegments(for: tile), isFresh(tile) {
            index.insert(contentsOf: cached)
            loadedTiles.insert(tile)
            segmentCount = index.count
            return
        }

        do {
            let segments = try await client.fetchSegments(for: tile)
            store.save(segments, to: cacheName(for: tile))
            tileFetchedAt[tile] = Date()
            failedAttempts[tile] = 0
            index.removeSegments(inTile: tile)
            index.insert(contentsOf: segments)
            loadedTiles.insert(tile)
            segmentCount = index.count
            saveManifest()
            lastError = nil
            logger.info("Loaded tile \(tile.description, privacy: .public) with \(segments.count) segments")
        } catch {
            failedAttempts[tile, default: 0] += 1
            // Stale cache beats no map. If the network is gone, use whatever we
            // downloaded last time rather than showing an empty city.
            if let cached = cachedSegments(for: tile) {
                index.insert(contentsOf: cached)
                loadedTiles.insert(tile)
                segmentCount = index.count
            } else {
                lastError = error.localizedDescription
            }
            logger.error("Tile \(tile.description, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Forces a refetch of one tile, e.g. when the user reports a missing street.
    func refresh(tile: TileKey) {
        tileFetchedAt[tile] = nil
        failedAttempts[tile] = 0
        loadedTiles.remove(tile)
        index.removeSegments(inTile: tile)
        store.delete(cacheName(for: tile))
        load(tiles: [tile])
    }

    func segments(inTile tile: TileKey) -> [StreetSegment] {
        index.segments(inTile: tile)
    }

    func segment(id: String) -> StreetSegment? {
        index.segment(id: id)
    }

    /// Every loaded segment intersecting a region, for drawing.
    func segments(in region: MKCoordinateRegion) -> [StreetSegment] {
        let box = BoundingBox(points: [
            Coordinate(
                latitude: region.center.latitude - region.span.latitudeDelta / 2,
                longitude: region.center.longitude - region.span.longitudeDelta / 2
            ),
            Coordinate(
                latitude: region.center.latitude + region.span.latitudeDelta / 2,
                longitude: region.center.longitude + region.span.longitudeDelta / 2
            ),
        ])
        return index.allSegments.filter { segment in
            let segmentBox = segment.boundingBox
            return segmentBox.maxLatitude >= box.minLatitude
                && segmentBox.minLatitude <= box.maxLatitude
                && segmentBox.maxLongitude >= box.minLongitude
                && segmentBox.minLongitude <= box.maxLongitude
        }
    }

    func clearCache() {
        index.removeAll()
        loadedTiles.removeAll()
        tileFetchedAt.removeAll()
        failedAttempts.removeAll()
        segmentCount = 0
        store.clearTileCache()
        store.delete(Self.manifestName)
    }

    var cacheSizeOnDisk: Int64 { store.sizeOnDisk() }

    // MARK: - Cache plumbing

    private func cacheName(for tile: TileKey) -> String { "tile_\(tile.description).json" }

    private func cachedSegments(for tile: TileKey) -> [StreetSegment]? {
        store.load([StreetSegment].self, from: cacheName(for: tile))
    }

    private func isFresh(_ tile: TileKey) -> Bool {
        guard let fetched = tileFetchedAt[tile] else { return false }
        return Date().timeIntervalSince(fetched) < Self.tileMaxAge
    }

    private struct Manifest: Codable {
        var fetchedAt: [String: Date]
    }

    private func loadManifest() {
        guard let manifest = store.load(Manifest.self, from: Self.manifestName) else { return }
        for (key, date) in manifest.fetchedAt {
            let parts = key.split(separator: "_")
            guard parts.count == 2, let x = Int(parts[0]), let y = Int(parts[1]) else { continue }
            tileFetchedAt[TileKey(x: x, y: y)] = date
        }
    }

    private func saveManifest() {
        let mapped = Dictionary(uniqueKeysWithValues: tileFetchedAt.map { ($0.key.description, $0.value) })
        store.save(Manifest(fetchedAt: mapped), to: Self.manifestName)
    }
}
