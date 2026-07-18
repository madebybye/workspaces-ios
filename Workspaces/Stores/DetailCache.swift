import Foundation

/// A disk cache of full setup details so revisiting (or prefetched) issues
/// render instantly while fresh data revalidates in the background.
///
/// Layout: one JSON file per slug inside `Caches/detail-cache-v1/`. The
/// schema version is baked into the directory name: when `SetupDetail`
/// changes shape, bump the version and old files are simply never read
/// again. Eviction is LRU-ish: reads touch the file's modification date and
/// saves prune the oldest files beyond `maxEntries`. All failures are
/// silent; callers fall through to the normal network path.
enum DetailCache {
    static let maxEntries = 30
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
    /// A successful read marks the entry as recently used.
    static func load(slug: String) -> SetupDetail? {
        guard let url = fileURL(for: slug),
              let data = try? Data(contentsOf: url),
              let detail = try? decoder.decode(SetupDetail.self, from: data)
        else { return nil }
        // Touch the modification date so eviction keeps recently read entries.
        Task.detached(priority: .utility) {
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: url.path
            )
        }
        return detail
    }

    /// Persists a detail keyed by its slug, then prunes the least recently
    /// used entries beyond `maxEntries`. Best-effort and off the main actor.
    static func save(_ detail: SetupDetail) {
        guard let directory, let url = fileURL(for: detail.slug) else { return }
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
            guard let data = try? encoder.encode(detail) else { return }
            try? data.write(to: url, options: .atomic)
            pruneIfNeeded(in: directory)
        }
    }

    /// Deletes the oldest-touched files beyond `maxEntries`.
    private static func pruneIfNeeded(in directory: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ), files.count > maxEntries else { return }

        let dated = files.map { url in
            (url: url,
             date: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast)
        }
        for stale in dated.sorted(by: { $0.date > $1.date }).dropFirst(maxEntries) {
            try? fm.removeItem(at: stale.url)
        }
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
