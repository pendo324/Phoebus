import SwiftUI
import PhoebusCore
#if canImport(VisionKit) && canImport(UIKit)
import VisionKit
import UIKit

/// Backs the "Live Text Analyzer" setting (`GeneralSettings.liveTextAnalyzer`):
/// runs Apple's Live Text OCR (VisionKit's `ImageAnalyzer` and
/// `ImageAnalysisInteraction`) over the fullscreen-viewed image so its text
/// becomes selectable.
///
/// VisionKit's analyzer is iOS 16+ only, hence the `@available` gate;
/// `FullscreenImageViewer` falls back to the plain `CachedAsyncImage` on
/// older targets or non-UIKit platforms.
@available(iOS 16.0, *)
struct LiveTextImageView: UIViewRepresentable {
    let url: URL?

    /// Reports the image's own size to SwiftUI's layout system.
    ///
    /// Without this a `UIViewRepresentable` has no intrinsic size and gets the
    /// full proposed area, letterboxing the image inside a wrong-shaped frame.
    /// `.aspectRatio()` alone doesn't help because it constrains a view that
    /// reports no size; `sizeThatFits` is what feeds the ratio into layout.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
        guard let image = uiView.image, image.size.height > 0 else { return nil }
        let ratio = image.size.width / image.size.height
        let width = proposal.width ?? image.size.width
        let height = proposal.height ?? image.size.height
        // Fit inside the proposal while preserving the real ratio.
        if width / height > ratio {
            return CGSize(width: height * ratio, height: height)
        }
        return CGSize(width: width, height: width / ratio)
    }

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        // Let SwiftUI drive the frame; the view must not fight it.
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.isUserInteractionEnabled = true
        let interaction = ImageAnalysisInteraction()
        imageView.addInteraction(interaction)
        context.coordinator.interaction = interaction
        return imageView
    }

    func updateUIView(_ imageView: UIImageView, context: Context) {
        guard let url, context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        Task {
            guard let data = await LiveTextImageView.loadImageData(url: url),
                  let image = UIImage(data: data) else { return }
            await MainActor.run {
                imageView.image = image
                // New image, new intrinsic size.
                imageView.invalidateIntrinsicContentSize()
            }
            guard ImageAnalyzer.isSupported else { return }
            let analyzer = ImageAnalyzer()
            let configuration = ImageAnalyzer.Configuration([.text])
            guard let analysis = try? await analyzer.analyze(image, configuration: configuration) else { return }
            await MainActor.run {
                context.coordinator.interaction?.analysis = analysis
                context.coordinator.interaction?.preferredInteractionTypes = .textSelection
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var interaction: ImageAnalysisInteraction?
        var loadedURL: URL?
    }

    /// Shares `CachedAsyncImage`'s in-memory image cache (and its Imgur proxy
    /// rewriting) so the image the plain viewer already loaded isn't fetched
    /// again.
    static func loadImageData(url: URL) async -> Data? {
        await MediaBytes.data(for: url)
    }
}
#endif
