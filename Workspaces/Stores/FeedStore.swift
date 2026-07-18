import Foundation
import Observation

/// Drives the paginated feed. Also reused (with a tag/search filter) by Explore.
@Observable @MainActor
final class FeedStore {
    enum Phase {
        case idle
        case loading
        case loaded
        case empty
        case failed(String)
    }

    private(set) var setups: [SetupSummary] = []
    private(set) var phase: Phase = .idle
    private(set) var isLoadingMore = false
    private(set) var reachedEnd = false

    var tagSlug: String?
    var search: String?
    var gearName: String?
    var collectionId: String?

    private let client = SanityClient.shared
    private var loadTask: Task<Void, Never>?
    private var paginationTask: Task<Void, Never>?

    /// Bumped by every `reload` so stale tasks (an earlier reload, or a
    /// pagination fetch racing a filter change) can detect that their results
    /// belong to a superseded query and must not be appended or persisted.
    private var generation = 0

    /// Whether gear results fell back to the loose GROQ token `match` because
    /// exact (case-insensitive) name equality found nothing. Exact-first keeps
    /// result counts consistent with the gear index tallies; the fallback
    /// keeps detail-page gear rows useful for variant spellings.
    private var gearLooseMatch = false

    /// True for the unfiltered front-of-book feed, the only configuration the
    /// disk cache serves and persists.
    private var isUnfiltered: Bool {
        tagSlug == nil && (search ?? "").isEmpty && gearName == nil && collectionId == nil
    }

    func loadInitial() async {
        guard case .idle = phase else { return }
        if isUnfiltered, let cached = FeedCache.load() {
            // Instant launch from disk; refresh quietly in the background.
            setups = cached
            phase = .loaded
            await reload(showSpinner: false)
        } else {
            await reload(showSpinner: true)
        }
        if isUnfiltered {
            // Fire-and-forget offline sync of the archive (runs once per
            // launch, cheap no-op when already up to date).
            ArchiveSync.shared.kickoff()
        }
    }

    /// Pull-to-refresh: bypasses HTTP caching so the update is real.
    func refresh() async {
        await reload(showSpinner: setups.isEmpty, forceFresh: true)
    }

    /// Cancels any in-flight load or pagination and refetches the first page
    /// with current filters, resetting pagination. `forceFresh` skips the
    /// local HTTP cache.
    func reload(showSpinner: Bool, forceFresh: Bool = false) async {
        loadTask?.cancel()
        paginationTask?.cancel()
        isLoadingMore = false
        generation += 1
        let requestGeneration = generation
        if showSpinner { phase = .loading }
        let task = Task { [tagSlug, search, gearName, collectionId] in
            do {
                var loose = false
                var page = try await fetchPage(
                    offset: 0, tagSlug: tagSlug, search: search, gearName: gearName,
                    gearLoose: false, collectionId: collectionId, forceFresh: forceFresh
                )
                if page.isEmpty, let gearName, !gearName.isEmpty {
                    // No exact-name gear hits: fall back to the loose token match.
                    loose = true
                    page = try await fetchPage(
                        offset: 0, tagSlug: tagSlug, search: search, gearName: gearName,
                        gearLoose: true, collectionId: collectionId, forceFresh: forceFresh
                    )
                }
                guard !Task.isCancelled, requestGeneration == generation else { return }
                gearLooseMatch = loose
                setups = page
                reachedEnd = page.count < GROQ.pageSize
                phase = page.isEmpty ? .empty : .loaded
                persistCacheIfNeeded()
                prefetchLeadDetailIfNeeded()
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, requestGeneration == generation else { return }
                if setups.isEmpty {
                    phase = .failed(error.localizedDescription)
                }
            }
        }
        loadTask = task
        await task.value
    }

    func loadMoreIfNeeded(current setup: SetupSummary) {
        guard !isLoadingMore, !reachedEnd, case .loaded = phase else { return }
        let threshold = setups.index(setups.endIndex, offsetBy: -5, limitedBy: setups.startIndex) ?? setups.startIndex
        guard let index = setups.firstIndex(of: setup), index >= threshold else { return }

        isLoadingMore = true
        let requestGeneration = generation
        paginationTask = Task { [tagSlug, search, gearName, collectionId, gearLooseMatch] in
            defer {
                if requestGeneration == generation { isLoadingMore = false }
            }
            do {
                let page = try await fetchPage(
                    offset: setups.count, tagSlug: tagSlug, search: search, gearName: gearName,
                    gearLoose: gearLooseMatch, collectionId: collectionId, forceFresh: false
                )
                // A reload (filter change) may have superseded this fetch;
                // appending would mix results across queries and could even
                // persist them into the feed cache.
                guard !Task.isCancelled, requestGeneration == generation else { return }
                let existing = Set(setups.map(\.slug))
                setups.append(contentsOf: page.filter { !existing.contains($0.slug) })
                if page.count < GROQ.pageSize { reachedEnd = true }
                persistCacheIfNeeded()
            } catch {
                // Pagination failures are silent; scrolling again retries.
            }
        }
    }

    /// One page fetch, decoded lossily so a single malformed document can't
    /// take down the whole page.
    private func fetchPage(
        offset: Int, tagSlug: String?, search: String?, gearName: String?,
        gearLoose: Bool, collectionId: String?, forceFresh: Bool
    ) async throws -> [SetupSummary] {
        let query = GROQ.setups(
            offset: offset, tagSlug: tagSlug, search: search,
            gearName: gearName, gearLoose: gearLoose, collectionId: collectionId
        )
        return try await client.fetch(
            LossyArray<SetupSummary>.self, query: query, forceFresh: forceFresh
        ).wrappedValue
    }

    /// Rewrites the disk cache from the current list, but only for the
    /// unfiltered feed (tag/search results are never cached).
    private func persistCacheIfNeeded() {
        guard isUnfiltered else { return }
        FeedCache.save(setups)
    }

    private var prefetchedLeadSlug: String?

    /// Warms the detail cache for the newest issue so the lead story opens
    /// instantly. Fire-and-forget at low priority; failures are silent.
    private func prefetchLeadDetailIfNeeded() {
        guard isUnfiltered, let lead = setups.first, lead.slug != prefetchedLeadSlug else { return }
        prefetchedLeadSlug = lead.slug
        let slug = lead.slug
        Task.detached(priority: .utility) {
            guard let detail = try? await SanityClient.shared.fetch(
                SetupDetail?.self,
                query: GROQ.setupDetail(slug: slug)
            ) else { return }
            DetailCache.save(detail)
        }
    }
}
