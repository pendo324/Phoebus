import Foundation
#if canImport(WebKit)
import WebKit
import UIKit

/// Shared construction for hidden "scrape" web views that load a real
/// reddit.com page purely to read its DOM.
///
/// Two constraints shape this: a hidden web view must not let WebKit's
/// fullscreen video promotion take over the screen (handled by a content
/// rule list blocking all media), and the view must still be attached to a
/// real window, because a detached view reports
/// `document.visibilityState == "hidden"`, a bot signal that stalls Reddit's
/// challenge forever. The two interact: the view is attached only when the
/// blocker compiled, since an attached unblocked view loading Reddit
/// reintroduces the fullscreen-hijack risk.
@MainActor
public enum ScrapeWebView {
    /// Compiled once per session.
    private static var blocker: WKContentRuleList?
    private static var blockerResolved = false

    /// Media/font/ad blocking, trimmed to what matters for a DOM read.
    /// `url-filter` uses a restricted regex grammar, hence the longhand
    /// rules rather than alternation.
    private static let blockerRules = """
    [
    {"trigger":{"url-filter":".*","resource-type":["media"]},"action":{"type":"block"}},
    {"trigger":{"url-filter":".*","resource-type":["font"]},"action":{"type":"block"}},
    {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?ads\\\\.reddit\\\\.com"},"action":{"type":"block"}},
    {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?alb\\\\.reddit\\\\.com"},"action":{"type":"block"}},
    {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?events\\\\.reddit\\\\.com"},"action":{"type":"block"}},
    {"trigger":{"url-filter":"^https?://pixel\\\\.redditmedia\\\\.com"},"action":{"type":"block"}},
    {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?doubleclick\\\\.net"},"action":{"type":"block"}},
    {"trigger":{"url-filter":"^https?://([^/]+\\\\.)?googlesyndication\\\\.com"},"action":{"type":"block"}}
    ]
    """

    /// Mobile Safari UA for this OS version. WKWebView's default UA
    /// lacks the trailing `Version/x … Safari` token, which marks the
    /// request as an embedded web view and raises Reddit's challenge rate.
    public static func safariUserAgent(
        systemVersion: String = UIDevice.current.systemVersion,
        isPad: Bool = UIDevice.current.userInterfaceIdiom == .pad
    ) -> String {
        let parts = systemVersion.split(separator: ".").map(String.init)
        let major = parts.first ?? "18"
        let minor = parts.count > 1 ? parts[1] : "0"
        let os = isPad
            ? "iPad; CPU OS \(major)_\(minor) like Mac OS X"
            : "iPhone; CPU iPhone OS \(major)_\(minor) like Mac OS X"
        return "Mozilla/5.0 (\(os)) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(major).\(minor) Mobile/15E148 Safari/604.1"
    }

    private static func keyWindow() -> UIWindow? { UIKitTree.keyWindow }

    private static func resolveBlocker(_ done: @escaping () -> Void) {
        guard !blockerResolved else { done(); return }
        WKContentRuleListStore.default()?.compileContentRuleList(
            forIdentifier: "PhoebusScrapeBlocker",
            encodedContentRuleList: blockerRules
        ) { list, _ in
            blocker = list
            blockerResolved = true
            done()
        }
    }

    /// Creates a hidden, media-blocked scrape web view.
    public static func create(
        configuration: WKWebViewConfiguration,
        ready: @escaping (WKWebView) -> Void
    ) {
        resolveBlocker {
            if let blocker {
                configuration.userContentController.add(blocker)
            }
            let frame = keyWindow()?.bounds ?? UIScreen.main.bounds
            let web = WKWebView(frame: frame, configuration: configuration)
            web.alpha = 0.011
            web.isUserInteractionEnabled = false
            web.customUserAgent = safariUserAgent()
            // Attach only when the blocker made it in; see the type's
            // doc comment.
            if let window = keyWindow(), blocker != nil {
                window.insertSubview(web, at: 0)
            }
            ready(web)
        }
    }

    public static func destroy(_ web: WKWebView?) {
        guard let web else { return }
        web.navigationDelegate = nil
        web.stopLoading()
        web.removeFromSuperview()
    }

    /// A shared, logged-out, in-memory data store for scrapes.
    ///
    /// Isolation from the app's own cookies matters because Reddit
    /// serves the old reddit layout to a logged-in session whose
    /// account has "Use new Reddit" disabled, and Apollo's OAuth login
    /// runs through a www.reddit.com web view that shares that cookie
    /// jar. Old reddit renders none of the Community Highlights markup
    /// this scraper looks for, so a logged-out store sidesteps it.
    /// Shared rather than per-scrape so the bot-challenge cookie warms
    /// once per session.
    public static let sharedDataStore: WKWebsiteDataStore = .nonPersistent()
}
#endif
