import SwiftUI
import PhoebusCore

/// A full-screen, pinch-to-zoom, double-tap-to-zoom image viewer presented
/// when tapping an inline image, dismissed by swipe-down or tap.
public struct FullscreenImageViewer: View {
    let url: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    /// Settings key: `LiveTextAnalyzer`.
    @Setting(GeneralSettings.self) private var general
    private var liveTextEnabled: Bool { general.liveTextAnalyzer }

    public init(url: URL?) {
        self.url = url
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            imageContent
                .scaleEffect(scale)
                .offset(offset)
                .gesture(magnifyGesture)
                .simultaneousGesture(dragGesture)
                .onTapGesture(count: 2) { toggleZoom() }
                .onTapGesture(count: 1) {
                    if scale == 1 { dismiss() }
                }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark").foregroundStyle(.white)
                    .accessibilityLabel("Close")
                }
            }
            if let url {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up").foregroundStyle(.white)
                    }
                }
                // Apollo's copy-link share action
                // (`com.christianselig.Apollo.CopyMediaLink`) for the media share sheet.
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        PasteboardHelper.copy(url: url)
                    } label: {
                        Image(systemName: "link").foregroundStyle(.white)
                    }
                    .accessibilityLabel("Copy Media Link")
                }
            }
        }
    }

    /// Live Text needs a real `UIImageView` (`ImageAnalysisInteraction`
    /// attaches to a `UIView`), so `LiveTextImageView` is used only when the
    /// setting is on and VisionKit is available; otherwise the plain
    /// `CachedAsyncImage` path.
    @ViewBuilder
    private var imageContent: some View {
        #if canImport(VisionKit) && canImport(UIKit)
        if liveTextEnabled, #available(iOS 16.0, *) {
            LiveTextImageView(url: url)
        } else {
            CachedAsyncImage(url: url)
        }
        #else
        CachedAsyncImage(url: url)
        #endif
    }


    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = max(1, min(lastScale * value.magnification, 5))
            }
            .onEnded { _ in
                lastScale = scale
                if scale == 1 { offset = .zero; lastOffset = .zero }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in lastOffset = offset }
    }

    private func toggleZoom() {
        withAnimation(.spring) {
            if scale > 1 {
                scale = 1
                lastScale = 1
                offset = .zero
                lastOffset = .zero
            } else {
                scale = 2.5
                lastScale = 2.5
            }
        }
    }
}

/// Convenience modifier: presents a `FullscreenImageViewer` in a sheet
/// when tapped, matching Apollo's tap-to-expand image behavior.
public extension View {
    func apolloTapToZoom(url: URL?, isPresented: Binding<Bool>) -> some View {
        self
            .onTapGesture { isPresented.wrappedValue = true }
            .fullScreenCoverIfAvailable(isPresented: isPresented) {
                NavigationStack {
                    FullscreenImageViewer(url: url)
                        .toolbarBackground(.hidden, for: .navigationBar)
                }
            }
    }
}

/// A URL made presentable by `fullScreenCover(item:)`.
///
/// `URL` is not `Identifiable`, and the item-based presentation is what
/// this needs: the URL is chosen by the SAME interaction that triggers
/// presentation, so a `Bool` would present before it was written.
private struct ViewerImage: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

public extension View {
    /// Presents the app's own image viewer for a tapped image link.
    func apolloImageViewer(url: Binding<URL?>) -> some View {
        let item = Binding<ViewerImage?>(
            get: { url.wrappedValue.map(ViewerImage.init) },
            set: { url.wrappedValue = $0?.url }
        )
        return fullScreenCoverIfAvailable(item: item) { image in
            NavigationStack {
                FullscreenImageViewer(url: image.url)
                    .toolbarBackground(.hidden, for: .navigationBar)
            }
        }
    }
}
