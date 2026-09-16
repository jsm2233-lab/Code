import Foundation

/// Exports the collection so it isn't trapped in the app.
///
/// GeoJSON for the collected streets (opens in anything), GPX for individual
/// trips (imports into Strava, Garmin, Komoot).
enum ExportService {

    static func geoJSON(
        coverage: CoverageStore,
        data: StreetDataStore,
        completedOnly: Bool
    ) -> Data? {
        var features: [[String: Any]] = []

        for entry in coverage.all {
            guard let segment = data.segment(id: entry.segmentID) else { continue }
            if completedOnly && !entry.isComplete { continue }

            for interval in entry.intervals.intervals {
                let points = segment.polyline(from: interval.lower, to: interval.upper)
                guard points.count > 1 else { continue }
                features.append([
                    "type": "Feature",
                    "geometry": [
                        "type": "LineString",
                        "coordinates": points.map { [$0.longitude, $0.latitude] },
                    ],
                    "properties": [
                        "name": segment.displayName,
                        "segment_id": segment.id,
                        "class": segment.classification.rawValue,
                        "fraction": entry.fraction,
                        "complete": entry.isComplete,
                        "first_seen": ISO8601DateFormatter().string(from: entry.firstSeen),
                        "last_seen": ISO8601DateFormatter().string(from: entry.lastSeen),
                    ],
                ])
            }
        }

        let collection: [String: Any] = [
            "type": "FeatureCollection",
            "features": features,
        ]
        return try? JSONSerialization.data(withJSONObject: collection, options: [.prettyPrinted])
    }

    static func gpx(for trip: Trip) -> Data? {
        let formatter = ISO8601DateFormatter()
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Street Collector" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata>
            <name>\(trip.mode.displayName) \(formatter.string(from: trip.startedAt))</name>
            <time>\(formatter.string(from: trip.startedAt))</time>
          </metadata>
          <trk>
            <name>\(trip.mode.displayName)</name>
            <trkseg>

        """

        for point in trip.track {
            xml += "      <trkpt lat=\"\(point.latitude)\" lon=\"\(point.longitude)\"></trkpt>\n"
        }

        xml += """
            </trkseg>
          </trk>
        </gpx>
        """
        return xml.data(using: .utf8)
    }

    /// Writes to a temp file and returns the URL, ready for a share sheet.
    static func write(_ data: Data, named name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
