import Foundation
import Observation

/// Instant offline full-text search over the locally synced archive.
///
/// `ArchiveSync` mirrors every published setup's detail JSON into
/// `DetailCache` (~534 docs ≈ 3 MB). This store folds those documents into a
/// small in-memory index — one pre-folded searchable string per field per
/// issue — so the INDEX search box can answer from disk-cached text with no
/// network at all.
///
/// Index design
/// - Built lazily off the main actor on first use (and warmed by
///   `prepare()` when the INDEX section first appears). Rebuilt whenever the
///   on-disk archive count changes, so results grow as the sync progresses
///   and pick up new issues.
/// - Fields, in ranking order: guest name, guest title, location, gear
///   names, Q&A (questions + answer plain text), bio plain text. The detail
///   documents carry no tag data (see `GROQ.detailProjection`), so tag names
///   cannot be indexed from the offline archive; tag browsing is unaffected.
/// - Matching is case- and diacritic-insensitive substring search. A
///   multi-word query ANDs its tokens: every token must appear somewhere in
///   the issue (fields may differ).
/// - Ranking: best (highest-priority) field that "explains" the match —
///   for each token, the best field containing it; the hit's scope is the
///   weakest of those, i.e. the field needed to complete the match. Hits
///   sort by scope (name > title > location > gear > Q&A > bio), with a
///   boost for word-prefix matches on the guest name, then issue recency.
///
/// Fallback: when fewer than `minimumIndexedCount` documents are cached
/// (fresh install, sync not yet run or barely started), `search` returns nil
/// and the caller keeps the existing network guest-name search.
@Observable @MainActor
final class SearchIndexStore {
    /// Where a match landed, in ranking order (lower is better).
    enum Scope: Int, CaseIterable, Comparable, Sendable {
        case name
        case title
        case location
        case gear
        case qa
        case bio

        static func < (lhs: Scope, rhs: Scope) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        /// Tracked-caps hint shown on result rows. Name matches need no
        /// explanation — that is what a search result is expected to be.
        var hint: String? {
            switch self {
            case .name: nil
            case .title: "In title"
            case .location: "In location"
            case .gear: "In gear"
            case .qa: "In Q&A"
            case .bio: "In bio"
            }
        }
    }

    struct Hit: Identifiable, Sendable {
        let summary: SetupSummary
        let scope: Scope

        var id: String { summary.slug }
    }

    /// One indexed issue: a ready-to-display summary plus one pre-folded
    /// searchable string per scope (indexed by `Scope.rawValue`).
    private struct Document: Sendable {
        let summary: SetupSummary
        let issueNumber: Int
        let folded: [String]
        let nameWords: [String]
    }

    /// Below this many cached documents the archive is considered "not yet
    /// synced" and search falls back to the network path. One sync batch
    /// (50 issues) is the smallest useful archive; anything less would give
    /// silently incomplete results during the first-launch sync window.
    private static let minimumIndexedCount = 50

    /// nil until the first build attempt; false when the archive is too
    /// empty to search locally.
    private(set) var isAvailable: Bool?

    /// How long the last index build took (measured; for diagnostics).
    private(set) var lastBuildDuration: Duration?

    private var documents: [Document] = []
    private var indexedDiskCount = -1
    private var buildTask: Task<Void, Never>?

    /// Warms the index (cheap no-op when already fresh). Call when the
    /// search UI appears so the first keystroke doesn't pay the build.
    func prepare() async {
        await refreshIfNeeded()
    }

    /// Searches the local archive. Returns nil when the archive is not
    /// usable yet (caller should fall back to the network search); otherwise
    /// ranked hits, possibly empty.
    func search(_ query: String) async -> [Hit]? {
        await refreshIfNeeded()
        guard isAvailable == true else { return nil }

        let tokens = Self.fold(query)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !tokens.isEmpty else { return [] }

        let docs = documents
        return await Task.detached(priority: .userInitiated) {
            Self.match(tokens: tokens, in: docs)
        }.value
    }

    // MARK: Build

    /// Rebuilds the index off the main actor when the on-disk archive count
    /// has changed since the last build. Concurrent callers share one build.
    private func refreshIfNeeded() async {
        if let buildTask {
            await buildTask.value
        }
        let diskCount = await Task.detached(priority: .userInitiated) {
            DetailCache.cachedSlugs().count
        }.value
        guard diskCount != indexedDiskCount else { return }

        let task = Task {
            let clock = ContinuousClock()
            let start = clock.now
            let built = await Task.detached(priority: .userInitiated) {
                Self.buildDocuments()
            }.value
            documents = built
            lastBuildDuration = clock.now - start
            indexedDiskCount = diskCount
            isAvailable = built.count >= Self.minimumIndexedCount
            #if DEBUG
            print("SearchIndexStore: indexed \(built.count) issues in \(lastBuildDuration!)")
            #endif
        }
        buildTask = task
        await task.value
        buildTask = nil
    }

    private nonisolated static func buildDocuments() -> [Document] {
        var docs: [Document] = []
        let slugs = DetailCache.cachedSlugs()
        docs.reserveCapacity(slugs.count)
        for slug in slugs {
            guard let detail = DetailCache.load(slug: slug),
                  let summary = summary(from: detail)
            else { continue }

            var folded = [String](repeating: "", count: Scope.allCases.count)
            folded[Scope.name.rawValue] = fold(detail.guestName)
            folded[Scope.title.rawValue] = fold(detail.guestTitle ?? "")
            folded[Scope.location.rawValue] = fold(detail.guestLocation ?? "")
            folded[Scope.gear.rawValue] = fold(detail.gear.map(\.name).joined(separator: "\n"))
            folded[Scope.qa.rawValue] = fold(
                detail.qa
                    .flatMap { [$0.question, $0.answer?.text ?? ""] }
                    .joined(separator: "\n")
            )
            folded[Scope.bio.rawValue] = fold(detail.guestBio?.text ?? "")

            docs.append(Document(
                summary: summary,
                issueNumber: detail.issueNumber,
                folded: folded,
                nameWords: folded[Scope.name.rawValue]
                    .split(whereSeparator: \.isWhitespace)
                    .map(String.init)
            ))
        }
        docs.sort { $0.issueNumber > $1.issueNumber }
        return docs
    }

    // MARK: Matching

    private nonisolated static func match(tokens: [String], in docs: [Document]) -> [Hit] {
        // (hit, name-prefix boost) pairs, scored then sorted.
        var scored: [(hit: Hit, boosted: Bool)] = []
        for doc in docs {
            // For each token, the best field containing it; the hit's scope
            // is the weakest of those (the field needed to complete the match).
            var scope = Scope.name
            var matchesAll = true
            for token in tokens {
                guard let best = Scope.allCases.first(where: {
                    doc.folded[$0.rawValue].contains(token)
                }) else {
                    matchesAll = false
                    break
                }
                scope = max(scope, best)
            }
            guard matchesAll else { continue }

            let boosted = scope == .name && tokens.allSatisfy { token in
                doc.nameWords.contains { $0.hasPrefix(token) }
            }
            scored.append((Hit(summary: doc.summary, scope: scope), boosted))
        }
        scored.sort {
            if $0.hit.scope != $1.hit.scope { return $0.hit.scope < $1.hit.scope }
            if $0.boosted != $1.boosted { return $0.boosted }
            return $0.hit.summary.issueNumber > $1.hit.summary.issueNumber
        }
        return scored.map(\.hit)
    }

    /// Case- and diacritic-insensitive normalization shared by index and query.
    private nonisolated static func fold(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    // MARK: Summary construction

    /// Builds a display-ready `SetupSummary` from a cached detail.
    /// `SetupSummary` only decodes (its custom `init(from:)` suppresses the
    /// memberwise initializer), so this round-trips through JSON using the
    /// summary's own tolerant decoder. Fields the detail lacks degrade the
    /// same way a sparse API document would: `tags` is empty (details carry
    /// none) and `hero`/`photoCount` derive from the photos array.
    private nonisolated static func summary(from detail: SetupDetail) -> SetupSummary? {
        var object: [String: Any] = [
            "issueNumber": detail.issueNumber,
            "slug": detail.slug,
            "guestName": detail.guestName,
            "photoCount": detail.photos.count,
            "tags": [[String: Any]](),
        ]
        if let title = detail.guestTitle { object["guestTitle"] = title }
        if let location = detail.guestLocation { object["guestLocation"] = location }
        if let publishedAt = detail.publishedAt {
            object["publishedAt"] = iso.string(from: publishedAt)
        }
        if let hero = detail.photos.first {
            var photo: [String: Any] = ["url": hero.url.absoluteString]
            if let alt = hero.alt { photo["alt"] = alt }
            object["hero"] = photo
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return try? decoder.decode(SetupSummary.self, from: data)
    }

    // ISO8601DateFormatter is documented thread-safe; it just lacks a
    // Sendable annotation.
    private nonisolated(unsafe) static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated static let decoder: JSONDecoder = {
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
