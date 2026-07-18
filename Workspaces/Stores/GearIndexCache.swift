import Foundation

/// A one-file disk cache of the aggregated most-featured-gear index so the
/// INDEX tab doesn't refetch every setup's gear (~420 KB) on each launch.
///
/// The schema version is baked into the filename (`gear-index-v1.json`):
/// when `GearIndexEntry` changes shape, bump the version and any old file is
/// simply never read again. `fetchedAt` lets the store refresh weekly.
/// Corrupt or missing files decode to nil and callers fall through to the
/// normal network path. Failures are silent, writes are atomic.
enum GearIndexCache {
    private static let filename = "gear-index-v1.json"

    struct Payload: Codable {
        let fetchedAt: Date
        let entries: [GearIndexEntry]
    }

    private static var fileURL: URL? {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(filename)
    }

    /// Returns nil for a missing, unreadable, corrupt, or stale-schema cache.
    static func load() -> Payload? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(Payload.self, from: data),
              !payload.entries.isEmpty
        else { return nil }
        return payload
    }

    /// Best-effort: failures are silent, and the write happens off the main
    /// actor.
    static func save(_ payload: Payload) {
        guard let url = fileURL else { return }
        Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(payload) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
