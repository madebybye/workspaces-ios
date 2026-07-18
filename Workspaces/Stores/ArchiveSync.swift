import Foundation

/// Background two-tier offline sync of the whole magazine, kicked off after
/// the feed loads and run at most once per launch.
///
/// - Tier 1 — newest 50 issues, full, with images: their detail JSON is
///   ensured in `DetailCache` and every photo is fetched through the shared
///   `ImageLoader` session at the widths the views request (gallery and
///   full-width feed hero 1200, split-layout feed hero 600, row thumbnail
///   300), so the cache keys match and recent issues render fully offline.
///   Already-cached photos are local disk hits (HTTP caching via
///   `URLCache`), not re-downloads. Photo prefetch only runs on
///   unconstrained, inexpensive networks (Wi-Fi, not cellular or Low Data
///   Mode) and photo-sync completion is only recorded when nearly every
///   fetch succeeded, so a gated or interrupted sync retries next launch.
/// - Tier 2 — full archive, text only: every published setup's detail JSON
///   (~534 docs ≈ 3 MB) is fetched in GROQ batches of 50 (~300 KB each) into
///   `DetailCache`, so any issue's text opens instantly offline; its photos
///   load lazily when online.
///
/// Incremental and resumable: per-slug files make "what's missing" a set
/// difference against the on-disk cache, so an interrupted sync just picks
/// up where it left off. Each launch re-checks cheaply — a tiny
/// newest-issue + total-count probe — and exits immediately when nothing
/// changed. Failures are silent (best-effort, like the caches).
actor ArchiveSync {
    static let shared = ArchiveSync()

    /// Issues whose photos are prefetched (tier 1).
    static let tier1Count = 50
    private static let batchSize = 50
    private static let photoConcurrency = 3
    private static let stateFilename = "archive-sync-state-v1.json"

    private var startedThisLaunch = false

    /// Fire-and-forget entry point; safe to call repeatedly. The text tier
    /// runs at `.utility` so a fresh install has the archive's text within a
    /// reasonable window; photo prefetch tasks stay at `.background`.
    nonisolated func kickoff() {
        Task(priority: .utility) { await self.run() }
    }

    private func run() async {
        guard !startedThisLaunch else { return }
        startedThisLaunch = true
        await sync()
    }

    // MARK: Sync

    private struct Head: Decodable {
        let newest: Int?
        let total: Int
    }

    /// Persisted head marker: what the archive looked like when the last
    /// sync fully completed (text and, when noted, tier-1 photos).
    private struct SyncState: Codable {
        var newestIssue: Int
        var totalCount: Int
        var photosSyncedNewest: Int?
    }

    private func sync() async {
        // Cheap freshness probe (bypasses the local HTTP cache so a new
        // issue is noticed immediately).
        guard let head = try? await SanityClient.shared.fetch(
            Head.self, query: GROQ.archiveHead, forceFresh: true
        ), let newest = head.newest else { return }

        let state = loadState()
        if let state,
           state.newestIssue == newest,
           state.totalCount == head.total,
           state.photosSyncedNewest == newest,
           DetailCache.cachedSlugs().count >= head.total {
            return
        }

        // Full slug index, newest first (~15 KB).
        guard let index = try? await SanityClient.shared.fetch(
            [String].self, query: GROQ.archiveIndex, forceFresh: true
        ), !index.isEmpty else { return }

        // Tier 2: fetch whatever detail JSON is missing, in batches.
        let cached = DetailCache.cachedSlugs()
        let missing = index.filter { !cached.contains($0) }
        var textComplete = true
        for start in stride(from: 0, to: missing.count, by: Self.batchSize) {
            let chunk = Array(missing[start..<min(start + Self.batchSize, missing.count)])
            guard let batch = try? await SanityClient.shared.fetch(
                LossyArray<SetupDetail>.self, query: GROQ.setupDetails(slugs: chunk)
            ) else {
                textComplete = false
                break
            }
            for detail in batch.wrappedValue {
                DetailCache.write(detail)
            }
            await Task.yield()
        }

        // Tier 1: ensure the newest issues' photos are in the image disk
        // cache, at the canonical widths the views actually request:
        // w=1200 (gallery figures + lead/full-width feed heroes), w=600
        // (split-layout feed heroes), w=300 (index/saved row thumbnails).
        // Completion is only recorded when >= 95% of the fetches succeeded
        // (tolerates a few permanently broken CDN entries without retrying
        // forever) — a cellular-gated or interrupted run records nothing and
        // retries next launch, where already-cached photos are free local
        // cache hits.
        var photosComplete = state?.photosSyncedNewest == newest
        if !photosComplete {
            var urls: [URL] = []
            for slug in index.prefix(Self.tier1Count) {
                guard let detail = DetailCache.load(slug: slug) else { continue }
                urls.append(contentsOf: detail.photos.map { $0.url(width: 1200) })
                if let hero = detail.photos.first {
                    urls.append(hero.url(width: 600))
                    urls.append(hero.url(width: 300))
                }
            }
            let succeeded = await prefetch(urls)
            let threshold = Int((Double(urls.count) * 0.95).rounded(.up))
            photosComplete = !urls.isEmpty && succeeded >= threshold
        }

        if textComplete {
            saveState(SyncState(
                newestIssue: newest,
                totalCount: head.total,
                photosSyncedNewest: photosComplete ? newest : state?.photosSyncedNewest
            ))
        }
    }

    /// Fetches image URLs through the shared loader with a small concurrency
    /// window at background priority — polite to the CDN and the battery.
    /// Returns how many URLs are now cached (fetched or already on disk).
    private func prefetch(_ urls: [URL]) async -> Int {
        await withTaskGroup(of: Bool.self) { group in
            var iterator = urls.makeIterator()
            func addNext() {
                guard let url = iterator.next() else { return }
                group.addTask(priority: .background) {
                    await ImageLoader.shared.prefetch(url)
                }
            }
            for _ in 0..<Self.photoConcurrency { addNext() }
            var succeeded = 0
            while let ok = await group.next() {
                if ok { succeeded += 1 }
                addNext()
            }
            return succeeded
        }
    }

    // MARK: State persistence (versioned, silent-failure — cache pattern)

    private var stateURL: URL? {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(Self.stateFilename)
    }

    private func loadState() -> SyncState? {
        guard let url = stateURL,
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(SyncState.self, from: data)
    }

    private func saveState(_ state: SyncState) {
        guard let url = stateURL,
              let data = try? JSONEncoder().encode(state)
        else { return }
        try? data.write(to: url, options: .atomic)
    }
}
