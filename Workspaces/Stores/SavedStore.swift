import Foundation
import Observation

/// The reader's saved setups ("clippings"), kept as full summaries in one
/// versioned JSON file in Application Support so the SAVED list renders
/// offline. Newest-saved first, deduped by slug.
///
/// Persistence follows the `FeedCache` pattern: the schema version is baked
/// into the filename (`saved-setups-v1.json`) so a `SetupSummary` shape
/// change just orphans the old file, writes are atomic and off the main
/// actor, and all failures are silent.
@Observable @MainActor
final class SavedStore {
    private(set) var saved: [SetupSummary]

    private static let filename = "saved-setups-v1.json"

    private static var fileURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(filename)
    }

    init() {
        saved = Self.load() ?? []
    }

    func isSaved(_ slug: String) -> Bool {
        saved.contains { $0.slug == slug }
    }

    /// Saves (inserting at the top) or unsaves, then persists.
    func toggle(_ summary: SetupSummary) {
        if let index = saved.firstIndex(where: { $0.slug == summary.slug }) {
            saved.remove(at: index)
        } else {
            saved.insert(summary, at: 0)
        }
        persist()
    }

    /// Returns nil for a missing, unreadable, corrupt, or stale-schema file.
    private static func load() -> [SetupSummary]? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([SetupSummary].self, from: data)
    }

    /// Best-effort atomic write off the main actor; failures are silent.
    private func persist() {
        guard let url = Self.fileURL else { return }
        let snapshot = saved
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
