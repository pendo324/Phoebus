import SwiftUI
import PhoebusCore
#if canImport(WebKit)
import WebKit
#endif

/// Plays a YouTube video inline using the YouTube IFrame Player embed (like
/// Apollo, which embeds the public `youtube.com/embed/<id>` player in a web
/// view and needs no API key), with "Off to Safari we goooo" as the fallback
/// string when inline playback isn't possible.
public struct YouTubePlayerView: View {
    let videoID: String
    let startSeconds: Int
    @Environment(\.openURL) private var openURL
    @Setting(GeneralSettingsStore.storage) private var settings

    public init(videoID: String, startSeconds: Int = 0) {
        self.videoID = videoID
        self.startSeconds = startSeconds
    }

    public var body: some View {
        Group {
            // Apollo's OpenVideosInYouTubeApp setting: hands off to the native
            // YouTube app (via Universal Links) instead of playing inline.
            if settings.openVideosInYouTubeApp {
                openInYouTubeAppPrompt
            } else {
                #if canImport(WebKit)
                YouTubeWebView(videoID: videoID, startSeconds: startSeconds)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                #else
                Link("Open on YouTube", destination: youtubeURL)
                #endif
            }
        }
    }

    /// The video's poster frame with a play button, shown when "Open Videos in
    /// YouTube App" is on. A poster rather than text, because the setting means
    /// "open in the app when I tap it": nothing launches until the user taps.
    private var openInYouTubeAppPrompt: some View {
        Button {
            if let url = YouTubeURLParser.nativeAppURL(forVideoID: videoID) {
                openURL(url)
            }
        } label: {
            ZStack {
                if let thumbnail = YouTubeURLParser.thumbnailURL(forVideoID: videoID) {
                    CachedAsyncImage(url: thumbnail, contentMode: .fill)
                } else {
                    Color.black.opacity(0.08)
                }
                // Play glyph over a scrim, so it stays legible on a
                // bright thumbnail.
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 6)
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play on YouTube")
        .accessibilityIdentifier("youtube.openInApp")
    }

    private var youtubeURL: URL {
        URL(string: "https://www.youtube.com/watch?v=\(videoID)") ?? URL(string: "https://youtube.com")!
    }

    /// Extracts an 11-character YouTube video ID from any common YouTube URL
    /// shape. Delegates to PhoebusCore's `YouTubeURLParser` so it is testable on
    /// Linux.
    public nonisolated static func extractVideoID(from url: URL) -> String? {
        YouTubeURLParser.extractVideoID(from: url)
    }
}

#if canImport(WebKit)
struct YouTubeWebView: PlatformViewRepresentable {
    let videoID: String
    let startSeconds: Int

    @MainActor
    func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        return WKWebView(frame: .zero, configuration: config)
    }

    @MainActor
    func loadContent(into webView: WKWebView) {
        let embedURL = "https://www.youtube.com/embed/\(videoID)?playsinline=1&start=\(startSeconds)"
        let html = """
        <html><body style="margin:0;background:black;">
        <iframe width="100%" height="100%" src="\(embedURL)" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
    }
}

#if canImport(UIKit)
extension YouTubeWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView() }
    func updateUIView(_ webView: WKWebView, context: Context) { loadContent(into: webView) }
}
#elseif canImport(AppKit)
extension YouTubeWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView() }
    func updateNSView(_ webView: WKWebView, context: Context) { loadContent(into: webView) }
}
#endif

/// Marker protocol so `YouTubeWebView` can share `makeWebView`/
/// `loadContent` logic across the platform-specific
/// UIViewRepresentable/NSViewRepresentable conformances.
protocol PlatformViewRepresentable {}
#endif
