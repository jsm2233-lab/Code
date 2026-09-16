import Foundation
import os

/// Fetches street geometry for a tile from the Overpass API and splits it into
/// intersection-to-intersection segments.
actor OverpassClient {

    enum OverpassError: Error, LocalizedError {
        case badResponse(Int)
        case rateLimited
        case decoding

        var errorDescription: String? {
            switch self {
            case .badResponse(let code): return "Street data server returned \(code)."
            case .rateLimited: return "Street data server is busy. Backing off."
            case .decoding: return "Street data was in an unexpected format."
            }
        }
    }

    /// Public Overpass instances. We rotate on failure rather than hammering
    /// one; these are donated servers and the usage policy asks for restraint.
    private let endpoints = [
        URL(string: "https://overpass-api.de/api/interpreter")!,
        URL(string: "https://overpass.kumi.systems/api/interpreter")!,
    ]

    private let session: URLSession
    private let logger = Logger(subsystem: "com.example.StreetCollector", category: "Overpass")
    private var endpointIndex = 0
    /// Minimum spacing between requests, per the Overpass usage policy.
    private var nextAllowedRequest = Date.distantPast
    private let minimumSpacing: TimeInterval = 1.2

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchSegments(for tile: TileKey) async throws -> [StreetSegment] {
        try await throttle()

        let query = """
        [out:json][timeout:45];
        way["highway"]["highway"!~"^(proposed|construction|abandoned|raceway|bus_guideway|escape)$"]\
        ["area"!="yes"]\
        (\(tile.south),\(tile.west),\(tile.north),\(tile.east));
        out geom;
        """

        var request = URLRequest(url: endpoints[endpointIndex])
        request.httpMethod = "POST"
        request.httpBody = "data=\(query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")"
            .data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("StreetCollector/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 50

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OverpassError.decoding }

        switch http.statusCode {
        case 200:
            break
        case 429, 504:
            rotateEndpoint()
            throw OverpassError.rateLimited
        default:
            rotateEndpoint()
            throw OverpassError.badResponse(http.statusCode)
        }

        guard let payload = try? JSONDecoder().decode(OverpassResponse.self, from: data) else {
            throw OverpassError.decoding
        }

        return Self.segments(from: payload.elements, tile: tile)
    }

    private func throttle() async throws {
        let wait = nextAllowedRequest.timeIntervalSinceNow
        if wait > 0 {
            try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
        nextAllowedRequest = Date().addingTimeInterval(minimumSpacing)
    }

    private func rotateEndpoint() {
        endpointIndex = (endpointIndex + 1) % endpoints.count
        nextAllowedRequest = Date().addingTimeInterval(5)
    }

    // MARK: - Parsing

    /// Splits each way at nodes shared with another way, so a segment is always
    /// intersection-to-intersection. Without this, "collecting a street" would
    /// mean wildly different amounts of driving depending on how OSM happened
    /// to chop the way up.
    static func segments(from elements: [OverpassElement], tile: TileKey) -> [StreetSegment] {
        var nodeUseCount: [Int: Int] = [:]
        for element in elements {
            guard let nodes = element.nodes else { continue }
            for node in nodes {
                nodeUseCount[node, default: 0] += 1
            }
        }

        var result: [StreetSegment] = []

        for element in elements {
            guard let highway = element.tags?["highway"],
                  let classification = StreetClassification(osmHighway: highway),
                  let geometry = element.geometry,
                  geometry.count > 1 else { continue }

            let nodes = element.nodes ?? []
            let name = element.tags?["name"]
            let oneWay = element.tags?["oneway"].map { $0 == "yes" || $0 == "1" || $0 == "-1" } ?? false

            var currentPoints: [Coordinate] = [Coordinate(latitude: geometry[0].lat, longitude: geometry[0].lon)]
            var pieceIndex = 0

            for i in 1..<geometry.count {
                currentPoints.append(Coordinate(latitude: geometry[i].lat, longitude: geometry[i].lon))

                let isLast = i == geometry.count - 1
                let isJunction = i < nodes.count && (nodeUseCount[nodes[i]] ?? 0) > 1

                if isLast || isJunction {
                    if let segment = makeSegment(
                        wayID: element.id,
                        pieceIndex: pieceIndex,
                        name: name,
                        classification: classification,
                        points: currentPoints,
                        isOneWay: oneWay,
                        tile: tile
                    ) {
                        result.append(segment)
                    }
                    pieceIndex += 1
                    currentPoints = [currentPoints[currentPoints.count - 1]]
                }
            }
        }

        return result
    }

    private static func makeSegment(
        wayID: Int,
        pieceIndex: Int,
        name: String?,
        classification: StreetClassification,
        points: [Coordinate],
        isOneWay: Bool,
        tile: TileKey
    ) -> StreetSegment? {
        guard points.count > 1 else { return nil }
        let length = GeoMath.polylineLength(points)
        // Sub-5 m stubs are junction artefacts, not streets.
        guard length >= 5 else { return nil }
        return StreetSegment(
            id: "\(wayID)-\(pieceIndex)",
            name: name,
            classification: classification,
            points: points,
            length: length,
            isOneWay: isOneWay,
            tile: tile
        )
    }
}

// MARK: - Wire format

struct OverpassResponse: Decodable {
    let elements: [OverpassElement]
}

struct OverpassElement: Decodable {
    struct Point: Decodable {
        let lat: Double
        let lon: Double
    }

    let id: Int
    let nodes: [Int]?
    let geometry: [Point]?
    let tags: [String: String]?
}
