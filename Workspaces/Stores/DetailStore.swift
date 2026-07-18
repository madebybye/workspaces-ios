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

    func load() async {
        if case .loaded = phase { return }
        phase = .loading
        do {
            let detail = try await SanityClient.shared.fetch(
                SetupDetail?.self,
                query: GROQ.setupDetail(slug: slug)
            )
            if let detail {
                phase = .loaded(detail)
            } else {
                phase = .failed("This setup could not be found.")
            }
        } catch is CancellationError {
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func retry() async {
        phase = .loading
        await load()
    }
}
