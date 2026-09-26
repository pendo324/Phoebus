import SwiftUI
import PhoebusCore
#if canImport(WebKit)
import WebKit
#endif

/// Renders a Reddit Developer Platform (Devvit) custom-widget post inline
/// via an embedded WKWebView pointing at the post's own reddit.com URL,
/// since Reddit's web renderer already knows how to display the custom UI.
/// See `DevvitPostDetector`.
///
/// Like Reborn, injects CSS to crop away Reddit's site chrome and a small JS
/// script that reports the widget's content height back to SwiftUI so the
/// embed sizes itself.
public struct DevvitWebView: View {
    let url: URL
    /// For the post-tap subscription check (#1264): the account asking.
    var repository: RedditRepository?
    @State private var measuredHeight: CGFloat = 320

    public init(url: URL, repository: RedditRepository? = nil) {
        self.url = url
        self.repository = repository
    }

    public var body: some View {
        #if canImport(WebKit)
        DevvitWebViewRepresentable(url: url, measuredHeight: $measuredHeight, onTap: {
            guard let repository, let subreddit = DevvitSubscriptionSync.subreddit(ofPermalink: url) else { return }
            DevvitSubscriptionSync.shared.tapped(subreddit: subreddit, repository: repository)
        })
            .frame(height: measuredHeight)
        #else
        Link("Open Interactive Post", destination: url)
        #endif
    }
}

#if canImport(WebKit)
/// CSS injected on document-ready to hide Reddit's site chrome (top nav
/// bar, left sidebar, footer) around the embedded widget.
///
/// Reddit's one-time "Give <app> limited access to your Reddit Account"
/// prompt (Deny / Allow) is portaled outside the post to
/// `div#devvit-app-permission-consent-dialog-<post>` under `shreddit-app`.
/// It is let through uncropped, or the app would wait on a prompt nobody
/// can see (Reborn #1264).
private let devvitChromeCropCSS = """
header, nav, footer, #right-sidebar, [data-testid="mobile-header"],
[data-testid="left-nav"], [data-testid="post-bottom-bar"],
.header, .side,
shreddit-app > *:not(shreddit-post):not([id^="devvit-app-permission-consent-dialog"]) {
  display: none !important;
}
body, html { margin: 0 !important; padding: 0 !important; background: transparent !important; }
"""

/// Polls `document.body.scrollHeight` and posts it to the
/// `devvitHeight` script message handler whenever it changes, so the
/// SwiftUI wrapper can resize to fit the widget's real content height
/// instead of a fixed guess.
private let devvitHeightScript = """
(function() {
  var lastHeight = 0;
  function consentOpen() {
    try {
      var cd = document.querySelector('devvit-app-permissions-consent-dialog');
      var rd = cd && cd.shadowRoot ? cd.shadowRoot.querySelector('rpl-dialog') : null;
      return !!(rd && rd.hasAttribute('open'));
    } catch (e) { return false; }
  }
  function report() {
    var h = document.body.scrollHeight;
    // The permission prompt is a modal that needs the tall size (512) to
    // show its text and both buttons (Reborn's probe `consent`).
    if (consentOpen()) { h = Math.max(h, 512); }
    if (h !== lastHeight && h > 0) {
      lastHeight = h;
      window.webkit.messageHandlers.devvitHeight.postMessage(h);
    }
  }
  var style = document.createElement('style');
  style.textContent = \(devvitChromeCropString());
  document.head.appendChild(style);
  report();
  new MutationObserver(report).observe(document.body, { childList: true, subtree: true, attributes: true });
  window.addEventListener('resize', report);
  setInterval(report, 500);
})();
"""

private func devvitChromeCropString() -> String {
    let escaped = devvitChromeCropCSS
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: " ")
    return "\"\(escaped)\""
}

private final class DevvitHeightMessageHandler: NSObject, WKScriptMessageHandler {
    let onHeight: (CGFloat) -> Void

    init(onHeight: @escaping (CGFloat) -> Void) {
        self.onHeight = onHeight
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let height = message.body as? Double {
            onHeight(CGFloat(height))
        } else if let height = message.body as? Int {
            onHeight(CGFloat(height))
        }
    }
}

private struct DevvitWebViewRepresentable: PlatformViewRepresentable {
    let url: URL
    @Binding var measuredHeight: CGFloat
    var onTap: () -> Void = {}

    @MainActor
    func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        let userScript = WKUserScript(source: devvitHeightScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        let controller = WKUserContentController()
        controller.addUserScript(userScript)
        controller.add(DevvitHeightMessageHandler { height in
            DispatchQueue.main.async {
                measuredHeight = max(120, height)
            }
        }, name: "devvitHeight")
        config.userContentController = controller

        return WKWebView(frame: .zero, configuration: config)
    }

    @MainActor
    func loadContent(into webView: WKWebView) {
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }
}

#if canImport(UIKit)
extension DevvitWebViewRepresentable: UIViewRepresentable {
    func makeCoordinator() -> DevvitTapWatcher { DevvitTapWatcher() }

    func makeUIView(context: Context) -> WKWebView {
        let webView = makeWebView()
        // Sees every tap in the widget (including ones inside its frames)
        // without taking any from the page.
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(DevvitTapWatcher.tapped))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesEnded = false
        tap.delegate = context.coordinator
        webView.addGestureRecognizer(tap)
        context.coordinator.onTap = onTap
        return webView
    }
    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onTap = onTap
        loadContent(into: webView)
    }
}

final class DevvitTapWatcher: NSObject, UIGestureRecognizerDelegate {
    var onTap: () -> Void = {}
    @objc func tapped() { onTap() }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
#elseif canImport(AppKit)
extension DevvitWebViewRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView() }
    func updateNSView(_ webView: WKWebView, context: Context) { loadContent(into: webView) }
}
#endif
#endif

/// After a tap in an interactive post, asks Reddit whether the post just
/// subscribed the user to its subreddit (Subscriber Goal's "Subscribe to
/// r/X", games' join buttons): that happens on Reddit's servers, so nothing
/// here heard about it (Reborn #1264 "Subscription sync"). Checks at 2, 5
/// and 12 s after the LAST tap, stops once subscribed, and is capped per
/// subreddit (`DevvitSubscriptionCheckLimiter`). Apps can't unsubscribe a
/// user, so only this direction exists.
@MainActor
final class DevvitSubscriptionSync {
    static let shared = DevvitSubscriptionSync()
    private var limiter = DevvitSubscriptionCheckLimiter()
    private var generations: [String: Int] = [:]
    private var serial = 0

    /// "/r/<name>/comments/<id>/…" → <name>.
    static func subreddit(ofPermalink url: URL) -> String? {
        let parts = url.pathComponents
        guard let index = parts.firstIndex(of: "r"), index + 1 < parts.count, !parts[index + 1].isEmpty else { return nil }
        return parts[index + 1]
    }

    func tapped(subreddit: String, repository: RedditRepository) {
        let key = subreddit.lowercased()
        serial += 1
        let generation = serial
        generations[key] = generation
        Task {
            // Already subscribed: nothing to learn.
            if await SubscribedSubredditsCache.shared.subscribedNames(repository: repository).contains(key) {
                generations[key] = nil
                return
            }
            var elapsed: TimeInterval = 0
            for delay in DevvitSubscriptionCheckLimiter.delays {
                try? await Task.sleep(nanoseconds: UInt64((delay - elapsed) * 1_000_000_000))
                elapsed = delay
                // A newer tap re-armed the sequence.
                guard generations[key] == generation else { return }
                guard limiter.take(key, now: ProcessInfo.processInfo.systemUptime) else { continue }
                if let info = try? await repository.fetchSubredditInfo(name: subreddit), info.userIsSubscriber == true {
                    generations[key] = nil
                    await RedditRepository.announce(SubscriptionChange(name: subreddit, fullname: info.name, subscribed: true))
                    return
                }
            }
            if generations[key] == generation { generations[key] = nil }
        }
    }
}
