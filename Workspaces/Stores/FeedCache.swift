import Foundation

/// A one-file disk cache of the most recent feed entries so a cold launch can
/// render instantly while fresh data loads in the background.
///
/// The schema version is baked into the filename (`feed-cache-v1.json`): when
/// the `SetupSummary` shape changes, bump the version and any old file is
/// simply never read again. Corrupt or missing files decode to nil and callers
/// fall through to the normal network path.
enum FeedCache {
    static let maxEntries = 25
    private static let filename = "feed-cache-v1.json"

    private static var fileURL: URL? {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(filename)
    }

    /// Returns nil for a missing, unreadable, corrupt, or stale-schema cache.
    static func load() -> [SetupSummary]? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let setups = try? decoder.decode([SetupSummary].self, from: data),
              !setups.isEmpty
        else { return nil }
        return setups
    }

    /// Persists the first `maxEntries` setups. Best-effort: failures are
    /// silent, and the write happens off the main actor.
    static func save(_ setups: [SetupSummary]) {
        guard let url = fileURL else { return }
        let trimmed = Array(setups.prefix(maxEntries))
        Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(trimmed) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
