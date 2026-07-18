import SwiftUI

/// A small cached async image view: in-memory NSCache in front of a
/// disk-backed URLCache, with a graceful placeholder and failure state.
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                Rectangle()
                    .fill(.primary.opacity(0.05))
                    .overlay {
                        if failed {
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundStyle(.tertiary)
                        } else {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.secondary)
                        }
                    }
            }
        }
        .animation(.easeOut(duration: 0.2), value: image != nil)
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        guard let url else {
            failed = true
            return
        }
        failed = false
        if let cached = ImageLoader.shared.cachedImage(for: url) {
            image = cached
            return
        }
        image = nil
        do {
            image = try await ImageLoader.shared.image(for: url)
        } catch is CancellationError {
        } catch {
            failed = true
        }
    }
}

/// Shared loader that deduplicates in-flight requests and caches decoded images.
final class ImageLoader: @unchecked Sendable {
    static let shared = ImageLoader()

    private let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024
        )
        return URLSession(configuration: configuration)
    }()

    private let lock = NSLock()
    private var inFlight: [URL: Task<UIImage, Error>] = [:]

    func cachedImage(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func image(for url: URL) async throws -> UIImage {
        if let cached = cachedImage(for: url) { return cached }

        let task = loadTask(for: url)
        defer { clearTask(for: url) }

        let image = try await task.value
        cache.setObject(image, forKey: url as NSURL, cost: data(of: image))
        return image
    }

    /// Returns the in-flight task for this URL, creating one if needed.
    /// Synchronous so locking stays out of async contexts.
    private func loadTask(for url: URL) -> Task<UIImage, Error> {
        lock.lock()
        defer { lock.unlock() }
        if let existing = inFlight[url] { return existing }
        let task = Task<UIImage, Error> { [session] in
            let (data, _) = try await session.data(from: url)
            guard let image = UIImage(data: data) else {
                throw URLError(.cannotDecodeContentData)
            }
            return image
        }
        inFlight[url] = task
        return task
    }

    private func clearTask(for url: URL) {
        lock.lock()
        defer { lock.unlock() }
        inFlight[url] = nil
    }

    private func data(of image: UIImage) -> Int {
        let pixels = Int(image.size.width * image.scale) * Int(image.size.height * image.scale)
        return pixels * 4
    }
}
