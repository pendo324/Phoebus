import SwiftUI
import PhoebusCore
#if canImport(WebKit)
import WebKit
#endif

/// Plays a YouTube video inline using the YouTube IFrame Player API (like
/// Apollo, which loads it in a web view and needs no API key). A video that
/// can't play inline (embedding disabled, removed) becomes a tap-to-open
/// poster instead of YouTube's error page.
public struct YouTubePlayerView: View {
    let videoID: String
    let startSeconds: Int
    @State private var unplayableInline = false
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
            } else if unplayableInline {
                openInYouTubeAppPrompt(caption: "Can't play here. Watch on YouTube")
            } else {
                #if canImport(WebKit)
                YouTubeWebView(videoID: videoID, startSeconds: startSeconds) { unplayableInline = true }
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
    private var openInYouTubeAppPrompt: some View { openInYouTubeAppPrompt(caption: nil) }

    private func openInYouTubeAppPrompt(caption: String?) -> some View {
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
            .overlay(alignment: .bottom) {
                if let caption {
                    Text(caption)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 3)
                        .padding(.bottom, 10)
                }
            }
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
    let onUnplayable: () -> Void

    @MainActor
    func makeWebView(_ coordinator: Coordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(coordinator, name: YouTubeEmbed.messageHandlerName)
        return WKWebView(frame: .zero, configuration: config)
    }

    // The page's origin, not youtube.com, is what YouTube sees as the
    // embedder; see `YouTubeEmbed.origin`.
    @MainActor
    func loadContent(into webView: WKWebView, coordinator: Coordinator) {
        coordinator.onUnplayable = onUnplayable
        let key = "\(videoID)#\(startSeconds)"
        guard coordinator.loadedKey != key else { return }
        coordinator.loadedKey = key
        let origin = YouTubeEmbed.origin(bundleIdentifier: Bundle.main.bundleIdentifier)
        if let html = YouTubeEmbed.html(videoID: videoID, startSeconds: startSeconds, origin: origin,
                                       captionsWanted: YouTubeCaptions.wanted) {
            webView.loadHTMLString(html, baseURL: origin)
        } else {
            DispatchQueue.main.async(execute: onUnplayable)
        }
    }

    @MainActor
    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Receives the page's `ready` / `error` messages. Registered with the
    /// web view's user content controller, which retains it.
    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler {
        var loadedKey: String?
        var onUnplayable: () -> Void = {}

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], body["event"] as? String == "error",
                  let code = body["code"] as? Int, YouTubeEmbed.isUnplayableInline(errorCode: code)
            else { return }
            onUnplayable()
        }
    }
}

#if canImport(UIKit)
extension YouTubeWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateUIView(_ webView: WKWebView, context: Context) { loadContent(into: webView, coordinator: context.coordinator) }
}
#elseif canImport(AppKit)
extension YouTubeWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateNSView(_ webView: WKWebView, context: Context) { loadContent(into: webView, coordinator: context.coordinator) }
}
#endif

/// Marker protocol so `YouTubeWebView` can share `makeWebView`/
/// `loadContent` logic across the platform-specific
/// UIViewRepresentable/NSViewRepresentable conformances.
protocol PlatformViewRepresentable {}
#endif
