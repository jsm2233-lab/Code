import Foundation
import os

/// Minimal on-disk JSON store.
///
/// Coverage is a big but simple blob written on a debounce, not a relational
/// workload, so Core Data would be overhead without payoff. Writes go through a
/// temp file and an atomic replace so a kill mid-write can't corrupt the
/// player's progress.
final class FileStore {

    static let shared = FileStore()

    private let queue = DispatchQueue(label: "com.example.StreetCollector.filestore", qos: .utility)
    private let logger = Logger(subsystem: "com.example.StreetCollector", category: "FileStore")
    private let root: URL

    private lazy var encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private lazy var decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.root = base.appendingPathComponent("StreetCollector", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    func url(for name: String) -> URL {
        root.appendingPathComponent(name)
    }

    func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        let url = url(for: name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            logger.error("Failed to decode \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Encodes on the caller's thread (so the value isn't mutated underneath us)
    /// and writes on the store's queue.
    func save<T: Encodable>(_ value: T, to name: String) {
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            logger.error("Failed to encode \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }
        let destination = url(for: name)
        queue.async { [logger] in
            let temporary = destination.appendingPathExtension("tmp")
            do {
                try data.write(to: temporary, options: .atomic)
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
            } catch {
                logger.error("Failed to write \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                try? FileManager.default.removeItem(at: temporary)
            }
        }
    }

    func delete(_ name: String) {
        let url = url(for: name)
        queue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: name).path)
    }

    func sizeOnDisk() -> Int64 {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return contents.reduce(into: Int64(0)) { total, url in
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    func clearTileCache() {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ) else { return }
        for url in contents where url.lastPathComponent.hasPrefix("tile_") {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
