import SwiftUI
import PhoebusCore
#if canImport(WebKit)
import WebKit
#endif

/// Inline Vimeo player using the embed host `https://player.vimeo.com/video/`.
public struct VimeoPlayerView: View {
    let videoID: String

    public init(videoID: String) {
        self.videoID = videoID
    }

    public var body: some View {
        Group {
            #if canImport(WebKit)
            if let url = VimeoURLParser.playerURL(forVideoID: videoID) {
                VimeoWebView(url: url)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
            } else {
                fallback
            }
            #else
            fallback
            #endif
        }
    }

    private var fallback: some View {
        Link(destination: URL(string: "https://vimeo.com/\(videoID)")!) {
            Label("Watch on Vimeo", systemImage: "play.rectangle")
        }
    }
}

#if canImport(WebKit)
private struct VimeoWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        // Match the other inline players: never autoplay with sound.
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
