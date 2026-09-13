import Foundation
import PhoebusCore
#if canImport(WebKit)
import WebKit

/// Mints Reddit Chat's `token_v2` the way Reborn's chat poller does: an
/// offscreen web view with a throwaway cookie store seeded with the
/// stored session (minus the old `token_v2` and the old-Reddit opt-out)
/// loads the homepage and Reddit sets a fresh `token_v2` in that store.
/// Reddit only issues it to a real browser load, not a `URLSession`
/// request with the same cookies.
@MainActor
public final class ChatTokenWebMinter: NSObject, WKNavigationDelegate {
    /// Hooks this up as `RedditChatClient.browserMinter`.
    public static func install() {
        RedditChatClient.browserMinter = { cookieHeader in
            await withCheckedContinuation { continuation in
                Task { @MainActor in
                    ChatTokenWebMinter(cookieHeader: cookieHeader) { continuation.resume(returning: $0) }.start()
                }
            }
        }
    }

    /// Minters in flight, kept alive until they finish.
    private static var active: Set<ChatTokenWebMinter> = []

    private let cookieHeader: String
    private let completion: (String?) -> Void
    private var webView: WKWebView?
    private var finished = false
    private var jarChecksLeft = 8

    private init(cookieHeader: String, completion: @escaping (String?) -> Void) {
        self.cookieHeader = cookieHeader
        self.completion = completion
    }

    private func start() {
        Self.active.insert(self)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.customUserAgent = ScrapeWebView.safariUserAgent()
        self.webView = webView

        let seeds = cookieHeader.components(separatedBy: "; ").compactMap { pair -> HTTPCookie? in
            guard let eq = pair.firstIndex(of: "="), eq != pair.startIndex else { return nil }
            let name = String(pair[..<eq])
            // Without `redesign_optout`: old Reddit never sets token_v2.
            guard name != "token_v2", name != "redesign_optout" else { return nil }
            return HTTPCookie(properties: [
                .name: name,
                .value: String(pair[pair.index(after: eq)...]),
                .domain: ".reddit.com",
                .path: "/",
                .secure: "TRUE",
                .expires: Date().addingTimeInterval(24 * 60 * 60),
            ])
        }
        let jar = configuration.websiteDataStore.httpCookieStore
        let group = DispatchGroup()
        for cookie in seeds {
            group.enter()
            jar.setCookie(cookie) { group.leave() }
        }
        group.notify(queue: .main) { [self] in
            guard let url = URL(string: "https://www.reddit.com/") else { return finish(nil) }
            webView.load(URLRequest(url: url))
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [self] in finish(nil) }
        }
    }

    /// The token usually comes with the document; Reddit sometimes sets
    /// it a moment later, so the store is checked for a few seconds.
    private func checkJar() {
        guard !finished, let webView else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [self] cookies in
            guard !finished else { return }
            if let token = cookies.first(where: { $0.name == "token_v2" && !$0.value.isEmpty })?.value,
               !RedditChatClient.isExpired(token, margin: 120) {
                return finish(token)
            }
            jarChecksLeft -= 1
            guard jarChecksLeft > 0 else { return finish(nil) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in checkJar() }
        }
    }

    private func finish(_ token: String?) {
        guard !finished else { return }
        finished = true
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        completion(token)
        Self.active.remove(self)
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        checkJar()
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        // The response headers, and their Set-Cookie, may still have
        // arrived.
        checkJar()
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }
}
#endif
