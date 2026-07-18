import Foundation
import Observation

/// The most-featured gear index. GROQ has no group-by, so the store fetches
/// every setup's gear names once (~420 KB), tallies them client-side —
/// normalizing case and whitespace so "MacBook Pro" and "macbook  pro"
/// collapse, and counting each setup at most once per item — and keeps the
/// top `maxEntries`. The ranked result is cached to disk for a week;
/// pull-to-refresh forces a re-fetch.
@Observable @MainActor
final class GearIndexStore {
    enum Phase {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var entries: [GearIndexEntry] = []
    private(set) var phase: Phase = .loading

    static let maxEntries = 40
    private static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    func load() async {
        if !entries.isEmpty { return }
        if let cached = GearIndexCache.load() {
            entries = cached.entries
            phase = .loaded
            // Stale cache still renders instantly; refresh quietly behind it.
            if Date.now.timeIntervalSince(cached.fetchedAt) > Self.maxAge {
                await fetch(forceFresh: true, quiet: true)
            }
        } else {
            await fetch(forceFresh: false, quiet: false)
        }
    }

    /// Pull-to-refresh: bypasses HTTP caching so the update is real.
    func refresh() async {
        await fetch(forceFresh: true, quiet: !entries.isEmpty)
    }

    func retry() async {
        await fetch(forceFresh: false, quiet: false)
    }

    private struct GearDoc: Decodable {
        var gear: [Item]?

        struct Item: Decodable {
            var name: String?
            var category: String?
        }
    }

    private func fetch(forceFresh: Bool, quiet: Bool) async {
        if !quiet { phase = .loading }
        do {
            let docs = try await SanityClient.shared.fetch(
                [GearDoc].self, query: GROQ.allGear, forceFresh: forceFresh
            )
            entries = Self.aggregate(docs)
            phase = .loaded
            GearIndexCache.save(.init(fetchedAt: .now, entries: entries))
        } catch is CancellationError {
        } catch {
            if entries.isEmpty { phase = .failed(error.localizedDescription) }
        }
    }

    private static func aggregate(_ docs: [GearDoc]) -> [GearIndexEntry] {
        struct Tally {
            let name: String
            var category: String?
            var count = 0
        }

        var tallies: [String: Tally] = [:]
        for doc in docs {
            var counted: Set<String> = []
            for item in doc.gear ?? [] {
                let display = (item.name ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacing(/\s+/, with: " ")
                guard !display.isEmpty else { continue }
                let key = display.lowercased()
                // A setup listing the same item twice still counts once.
                guard counted.insert(key).inserted else { continue }
                var tally = tallies[key] ?? Tally(name: display, category: item.category)
                tally.count += 1
                if tally.category == nil { tally.category = item.category }
                tallies[key] = tally
            }
        }
        return tallies.values
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            .prefix(maxEntries)
            .map { GearIndexEntry(name: $0.name, category: $0.category, setupCount: $0.count) }
    }
}
