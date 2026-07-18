import Foundation
import Observation

@Observable @MainActor
final class TagStore {
    enum Phase {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var tags: [Tag] = []
    private(set) var phase: Phase = .loading

    func load() async {
        if !tags.isEmpty { return }
        phase = .loading
        do {
            // Lossy: one malformed tag document must not kill the whole index.
            tags = try await SanityClient.shared.fetch(
                LossyArray<Tag>.self, query: GROQ.allTags
            ).wrappedValue
            phase = .loaded
        } catch is CancellationError {
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
