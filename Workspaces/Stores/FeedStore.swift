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

    private let client = SanityClient.shared
    private var loadTask: Task<Void, Never>?

    /// True for the unfiltered front-of-book feed, the only configuration the
    /// disk cache serves and persists.
    private var isUnfiltered: Bool {
        tagSlug == nil && (search ?? "").isEmpty
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
    }

    /// Pull-to-refresh: bypasses HTTP caching so the update is real.
    func refresh() async {
        await reload(showSpinner: setups.isEmpty, forceFresh: true)
    }

    /// Cancels any in-flight load and refetches the first page with current
    /// filters, resetting pagination. `forceFresh` skips the local HTTP cache.
    func reload(showSpinner: Bool, forceFresh: Bool = false) async {
        loadTask?.cancel()
        if showSpinner { phase = .loading }
        let task = Task { [tagSlug, search] in
            do {
                let query = GROQ.setups(offset: 0, tagSlug: tagSlug, search: search)
                let page = try await client.fetch([SetupSummary].self, query: query, forceFresh: forceFresh)
                guard !Task.isCancelled else { return }
                setups = page
                reachedEnd = page.count < GROQ.pageSize
                phase = page.isEmpty ? .empty : .loaded
                persistCacheIfNeeded()
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
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
        Task { [tagSlug, search] in
            defer { isLoadingMore = false }
            do {
                let query = GROQ.setups(offset: setups.count, tagSlug: tagSlug, search: search)
                let page = try await client.fetch([SetupSummary].self, query: query)
                let existing = Set(setups.map(\.slug))
                setups.append(contentsOf: page.filter { !existing.contains($0.slug) })
                if page.count < GROQ.pageSize { reachedEnd = true }
                persistCacheIfNeeded()
            } catch {
                // Pagination failures are silent; scrolling again retries.
            }
        }
    }

    /// Rewrites the disk cache from the current list, but only for the
    /// unfiltered feed (tag/search results are never cached).
    private func persistCacheIfNeeded() {
        guard isUnfiltered else { return }
        FeedCache.save(setups)
    }
}
