import Foundation

/// The primary on-disk store of full setup details: the entire archive
/// (~534 small JSON files, ~3 MB total) is synced here by `ArchiveSync`, so
/// every issue's text renders instantly and offline. Visited issues still
/// revalidate over the network in the background.
///
/// Layout: one JSON file per slug inside `Caches/detail-cache-v1/`. The
/// schema version is baked into the directory name: when `SetupDetail`
/// changes shape, bump the version and old files are simply never read
/// again. There is no eviction — the archive is small and `ArchiveSync`
/// would only re-download pruned entries. All failures are silent; callers
/// fall through to the normal network path.
enum DetailCache {
    private static let directoryName = "detail-cache-v1"

    private static var directory: URL? {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    private static func fileURL(for slug: String) -> URL? {
        // Slugs are URL-safe, but sanitize defensively for the filesystem.
        let safe = slug.replacingOccurrences(of: "/", with: "-")
        guard !safe.isEmpty else { return nil }
        return directory?.appendingPathComponent(safe + ".json")
    }

    /// Returns nil for a missing, unreadable, corrupt, or stale-schema entry.
    static func load(slug: String) -> SetupDetail? {
        guard let url = fileURL(for: slug),
              let data = try? Data(contentsOf: url),
              let detail = try? decoder.decode(SetupDetail.self, from: data)
        else { return nil }
        return detail
    }

    /// True when an entry for this slug exists on disk (without decoding it).
    /// Lets the archive sync skip already-synced issues cheaply.
    static func contains(slug: String) -> Bool {
        guard let url = fileURL(for: slug) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// The slugs currently cached, derived from the filenames on disk.
    static func cachedSlugs() -> Set<String> {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: nil,
                  options: .skipsHiddenFiles
              )
        else { return [] }
        return Set(
            files
                .filter { $0.pathExtension == "json" }
                .map { $0.deletingPathExtension().lastPathComponent }
        )
    }

    /// Persists a detail keyed by its slug. Best-effort and off the main actor.
    static func save(_ detail: SetupDetail) {
        Task.detached(priority: .utility) {
            write(detail)
        }
    }

    /// Synchronous variant for callers already off the main actor (the
    /// archive sync writes hundreds of entries in sequence).
    static func write(_ detail: SetupDetail) {
        guard let directory, let url = fileURL(for: detail.slug) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? encoder.encode(detail) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // Fractional-seconds ISO 8601 both ways so dates round-trip with the
    // same precision the Sanity API delivers, keeping cached details equal
    // to freshly fetched ones when nothing actually changed.
    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(iso.string(from: date))
        }
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = iso.date(from: string) ?? ISO8601DateFormatter().date(from: string) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unrecognized date: \(string)"
            ))
        }
        return decoder
    }()
}
