import Foundation
import Observation

@Observable @MainActor
final class DetailStore {
    enum Phase {
        case loading
        case loaded(SetupDetail)
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    let slug: String

    init(slug: String) {
        self.slug = slug
    }

    /// Serves the disk cache instantly when present, then revalidates over
    /// the network (default HTTP cache policy) and updates the UI and cache
    /// only if the content actually changed.
    func load() async {
        if case .loaded = phase { return }
        if let cached = DetailCache.load(slug: slug) {
            phase = .loaded(cached)
            await revalidate(against: cached)
        } else {
            phase = .loading
            await fetchFresh()
        }
    }

    func retry() async {
        phase = .loading
        await fetchFresh()
    }

    private func fetchFresh() async {
        do {
            if let detail = try await fetch() {
                phase = .loaded(detail)
                DetailCache.save(detail)
            } else {
                phase = .failed("This setup could not be found.")
            }
        } catch is CancellationError {
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Silent background refresh of a cached detail. Failures keep the
    /// cached content on screen.
    private func revalidate(against cached: SetupDetail) async {
        guard let fresh = try? await fetch(), fresh != cached else { return }
        phase = .loaded(fresh)
        DetailCache.save(fresh)
    }

    private func fetch() async throws -> SetupDetail? {
        try await SanityClient.shared.fetch(
            SetupDetail?.self,
            query: GROQ.setupDetail(slug: slug)
        )
    }
}
