import SwiftUI
import UniformTypeIdentifiers

/// A `UIScrollView`-backed zoom container for a single photo: pinch to zoom
/// (1x–4x), pan while zoomed, and double-tap to toggle 1x/2.5x. UIKit's
/// scroll view handles gesture precedence natively — at 1x its pan gesture
/// fails (content fits) so the enclosing vertical SwiftUI scroll view keeps
/// scrolling; once zoomed in, drags pan the photo instead of the stack.
///
/// Size the view from the outside to the image's aspect ratio (e.g.
/// `.aspectRatio(w/h, contentMode: .fit)`) so the photo exactly fills the
/// bounds at 1x. `minimumZoomScale` is pinned to 1, so the photo can never
/// be zoomed out below its natural size, and `bouncesZoom` snaps any
/// over-pinch back within the 1x–4x band.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    /// Incrementing this snaps the zoom back to 1x without animation —
    /// used when a figure scrolls offscreen so it reappears un-zoomed.
    var resetToken: Int = 0
    var maximumZoom: CGFloat = 4
    var doubleTapZoom: CGFloat = 2.5
    /// When true (Reduce Motion), the double-tap zoom jumps without animating.
    var reduceMotion: Bool = false

    func makeUIView(context: Context) -> ZoomScrollView {
        let view = ZoomScrollView()
        view.delegate = context.coordinator
        view.minimumZoomScale = 1
        view.maximumZoomScale = maximumZoom
        view.bouncesZoom = true
        view.showsVerticalScrollIndicator = false
        view.showsHorizontalScrollIndicator = false
        view.contentInsetAdjustmentBehavior = .never
        view.backgroundColor = .clear
        view.imageView.image = image

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)
        return view
    }

    func updateUIView(_ uiView: ZoomScrollView, context: Context) {
        context.coordinator.parent = self
        uiView.maximumZoomScale = maximumZoom
        if uiView.imageView.image !== image {
            uiView.imageView.image = image
        }
        if context.coordinator.lastResetToken != resetToken {
            context.coordinator.lastResetToken = resetToken
            if uiView.zoomScale > 1 {
                uiView.setZoomScale(1, animated: false)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomableImageView
        var lastResetToken: Int

        init(parent: ZoomableImageView) {
            self.parent = parent
            self.lastResetToken = parent.resetToken
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? ZoomScrollView)?.imageView
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? ZoomScrollView else { return }
            let animated = !parent.reduceMotion
            if scrollView.zoomScale > 1.01 {
                scrollView.setZoomScale(1, animated: animated)
            } else {
                // Zoom into the tapped point: the target rect (in image-view
                // coordinates) is the region that will fill the bounds.
                let scale = min(parent.doubleTapZoom, parent.maximumZoom)
                let point = gesture.location(in: scrollView.imageView)
                let size = CGSize(
                    width: scrollView.bounds.width / scale,
                    height: scrollView.bounds.height / scale
                )
                let rect = CGRect(
                    x: point.x - size.width / 2,
                    y: point.y - size.height / 2,
                    width: size.width,
                    height: size.height
                )
                scrollView.zoom(to: rect, animated: animated)
            }
        }
    }

    /// Scroll view that hosts the image view and re-fits it (at 1x) whenever
    /// its bounds change — initial layout, rotation, size-class changes.
    final class ZoomScrollView: UIScrollView {
        let imageView = UIImageView()
        private var lastBoundsSize: CGSize = .zero

        override init(frame: CGRect) {
            super.init(frame: frame)
            imageView.contentMode = .scaleAspectFit
            addSubview(imageView)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            if bounds.size != lastBoundsSize {
                lastBoundsSize = bounds.size
                zoomScale = 1
                imageView.frame = CGRect(origin: .zero, size: bounds.size)
                contentSize = bounds.size
            }
        }
    }
}

// MARK: - Sharing

/// A photo prepared for the share sheet: JPEG bytes at the full cached
/// resolution (the w=1200 rendition the gallery displays). Shared as data
/// rather than a URL so the sheet's built-in activities — including
/// "Save Image", which runs out-of-process and needs no photo-library
/// usage description from the host app — all work offline from cache.
struct SharedPhoto: Transferable {
    let jpegData: Data
    let fileName: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { $0.jpegData }
            .suggestedFileName { $0.fileName }
    }

    /// Builds share data for the photo at `url` through the shared image
    /// cache. The CDN's `auto=format` can serve WebP/AVIF, which some share
    /// targets handle poorly, so anything that isn't already JPEG is
    /// re-encoded from the decoded image.
    static func load(from url: URL, fileName: String) async throws -> SharedPhoto {
        let data = try await ImageLoader.shared.imageData(for: url)
        if data.starts(with: [0xFF, 0xD8, 0xFF]) {
            return SharedPhoto(jpegData: data, fileName: fileName)
        }
        guard let image = UIImage(data: data),
              let jpeg = image.jpegData(compressionQuality: 0.9)
        else {
            throw URLError(.cannotDecodeContentData)
        }
        return SharedPhoto(jpegData: jpeg, fileName: fileName)
    }
}
