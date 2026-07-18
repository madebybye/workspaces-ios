import Foundation
import Observation

/// Loads the curated collections (nine small documents with server-computed
/// setup counts) for the INDEX section. Cheap enough that protocol-level
/// HTTP caching is the only cache; pull-to-refresh forces a fresh fetch.
@Observable @MainActor
final class CollectionStore {
    enum Phase {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var collections: [SetupCollection] = []
    private(set) var phase: Phase = .loading

    func load(forceFresh: Bool = false) async {
        if !collections.isEmpty && !forceFresh { return }
        if collections.isEmpty { phase = .loading }
        do {
            collections = try await SanityClient.shared.fetch(
                [SetupCollection].self, query: GROQ.collections, forceFresh: forceFresh
            )
            phase = .loaded
        } catch is CancellationError {
        } catch {
            if collections.isEmpty { phase = .failed(error.localizedDescription) }
        }
    }
}
