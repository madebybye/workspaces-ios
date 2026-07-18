import ImageIO
import SwiftUI

/// A small cached async image view: in-memory NSCache in front of a
/// disk-backed URLCache, with a graceful placeholder and failure state.
struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var failed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: image != nil)
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
        // A dedicated on-disk directory (rather than the shared default
        // location) so image responses reliably persist across launches and
        // hero images render instantly on a cold start from the feed cache.
        let directory = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("RemoteImageCache", isDirectory: true)
        // Sized to hold the tier-1 prefetch (newest 50 issues × ~8 photos
        // at w=1200 ≈ 100–150 MB) plus normal browsing without churn.
        configuration.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity: 512 * 1024 * 1024,
            directory: directory
        )
        return URLSession(configuration: configuration)
    }()

    private let lock = NSLock()
    private var inFlight: [URL: Task<UIImage, Error>] = [:]

    func cachedImage(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    /// Warms the disk-backed URLCache without decoding the image or touching
    /// the in-memory cache. Used by the archive sync's tier-1 photo
    /// prefetch: the request goes through the same session (and thus the
    /// same cache keys) the views use, so an already-cached photo is a local
    /// disk hit and a new one is stored for offline display.
    ///
    /// Unlike on-demand loads, prefetching is a bulk background download the
    /// user never asked for, so it refuses expensive (cellular/hotspot) and
    /// constrained (Low Data Mode) networks — already-cached photos still
    /// resolve as local cache hits. Returns whether the photo is now cached,
    /// so the caller can avoid recording a failed sync as complete.
    func prefetch(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.allowsExpensiveNetworkAccess = false
        request.allowsConstrainedNetworkAccess = false
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else { return false }
        return true
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
            guard let image = Self.decodeDownsampled(data, requestedFrom: url) else {
                throw URLError(.cannotDecodeContentData)
            }
            return image
        }
        inFlight[url] = task
        return task
    }

    /// Decodes via ImageIO thumbnailing so the decoded bitmap never exceeds
    /// the pixel width the view asked the CDN for (`?w=`), instead of
    /// `UIImage(data:)`'s deferred full-resolution decode. The CDN usually
    /// honors `w`, making this a same-size decode — but it caps any
    /// larger-than-requested response, decodes eagerly off the render path
    /// (`kCGImageSourceShouldCacheImmediately`), and drops the compressed
    /// buffer, which is what kept deep-scroll RSS in the hundreds of MB.
    private static func decodeDownsampled(_ data: Data, requestedFrom url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        // Cap the decoded *width* at the requested `w` (already a pixel
        // width — views pick it as point width × screen scale, so no extra
        // scale factor here). `kCGImageSourceThumbnailMaxPixelSize` bounds
        // the larger dimension, so for portrait images it is derived from
        // the source aspect ratio to preserve the full requested width.
        var maxPixelSize: CGFloat?
        if let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "w" })?.value,
           let requestedWidth = Double(value), requestedWidth > 0,
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let sourceWidth = properties[kCGImagePropertyPixelWidth] as? CGFloat,
           let sourceHeight = properties[kCGImagePropertyPixelHeight] as? CGFloat,
           sourceWidth > 0, sourceHeight > 0 {
            let widthCap = min(CGFloat(requestedWidth), sourceWidth)
            maxPixelSize = (widthCap * max(1, sourceHeight / sourceWidth)).rounded(.up)
        }

        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if let maxPixelSize {
            options[kCGImageSourceThumbnailMaxPixelSize] = maxPixelSize
        }
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data) // Fall back to the plain decode.
        }
        return UIImage(cgImage: cgImage)
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
