import SwiftUI
#if canImport(WebKit)
import WebKit
#endif
import PhoebusCore

/// Apollo-Reborn's "Web Session Login (Experimental)" flow: a
/// `WKWebView` loads Reddit's own login page on the persistent website
/// data store, then polls `fetch('/api/me.json')` on a 2-second timer
/// (the login form submits by fetch, so `didFinish` never fires for
/// the moment auth completes) until it returns a signed-in username.
/// Every `.reddit.com` cookie is then harvested into a single
/// `name=value; ...` header, with the CSRF `modhash` read from the
/// same probe response. This lets a user sign in without registering
/// their own Reddit OAuth app, which Reddit no longer allows freely.
public struct WebSessionLoginScreen: View {
    let onSuccess: (WebSessionCredential) -> Void
    let onCancel: () -> Void
    /// When set, the harvested session must belong to this account.
    /// A wrong-account harvest would make Apollo vote as a different
    /// user than the one it's acting for; Reborn shows a
    /// "Different Reddit Account" alert instead.
    let requiredUsername: String?

    @State private var probeResult: WebSessionProbeResult?
    @State private var isHarvesting = false
    @State private var mismatchedUsername: String?

    public init(requiredUsername: String? = nil, onSuccess: @escaping (WebSessionCredential) -> Void, onCancel: @escaping () -> Void) {
        self.requiredUsername = requiredUsername?.lowercased()
        self.onSuccess = onSuccess
        self.onCancel = onCancel
    }

    public var body: some View {
        #if canImport(WebKit)
        VStack(spacing: 0) {
            if isHarvesting {
                ProgressView("Signing you in…")
                    .padding()
            }
            WebSessionLoginWebView(onProbeResult: handleProbeResult)
        }
        .navigationTitle("Sign In")
        // "Different Reddit Account" alert with its verbatim message and actions.
        .alert("Different Reddit Account", isPresented: $mismatchedUsername.isPresent()) {
            Button("Sign In Again") { mismatchedUsername = nil }
            Button("Cancel", role: .cancel) { mismatchedUsername = nil; onCancel() }
        } message: {
            Text("Phoebus is using u/\(requiredUsername ?? ""), but Reddit signed in as u/\(mismatchedUsername ?? ""). Sign in with the matching account for Chat, Modmail, and Polls.")
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
        #else
        Text("Web sign-in requires WebKit, unavailable on this platform.")
            .padding()
        #endif
    }

    private func handleProbeResult(_ result: WebSessionProbeResult) {
        guard !isHarvesting else { return }
        guard let username = result.username, let cookieHeader = result.cookieHeader else { return }
        // Reject a session for the wrong account rather than storing
        // it. Without this a user with two Reddit logins could vote as
        // the wrong one without ever being told.
        if let requiredUsername, requiredUsername != username.lowercased() {
            mismatchedUsername = username
            return
        }
        isHarvesting = true
        let credential = WebSessionCredential(username: username, cookieHeader: cookieHeader, modhash: result.modhash)
        onSuccess(credential)
    }
}

/// Outcome of one `/api/me.json` probe. Auth decisions key off this JSON
/// rather than cookie presence: Reddit sets `reddit_session`/`token_v2` for
/// anonymous sessions too, and `getAllCookies` can briefly report a stale/empty
/// snapshot right after a web view is created.
public struct WebSessionProbeResult: Sendable, Equatable {
    public var username: String?
    public var modhash: String?
    public var cookieHeader: String?
}

#if canImport(WebKit)
private struct WebSessionLoginWebView: PlatformViewRepresentable {
    let onProbeResult: (WebSessionProbeResult) -> Void

    /// 2-second poll timer, not just a one-shot check on page load,
    /// since the Reddit login form submits via fetch with no
    /// navigation event for the delegate to observe.
    static let probeInterval: TimeInterval = 2.0

    @MainActor
    func makeWebView() -> WKWebView {
        // The persistent data store, not `.nonPersistent()`, so signing
        // in once survives app restarts without separate persistence
        // for the raw WebView session, only for the harvested credential.
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        return webView
    }

    @MainActor
    func loadContent(into webView: WKWebView) {}

    @MainActor
    func makeCoordinator() -> WebSessionLoginCoordinator {
        WebSessionLoginCoordinator(onProbeResult: onProbeResult)
    }
}

/// Owns the repeating probe timer and the `/api/me.json` fetch + cookie
/// harvest.
@MainActor
private final class WebSessionLoginCoordinator: NSObject, WKNavigationDelegate {
    let onProbeResult: (WebSessionProbeResult) -> Void
    private var timer: Timer?
    private weak var webView: WKWebView?
    private var finished = false
    /// Bounded retries for the completeness gate below.
    private var harvestAttempts = 0
    /// The probe is inert until the first navigation finishes, so the
    /// 2s timer can't hit `/api/me.json` before the login page has
    /// even loaded. Reddit's edge treats unsolicited polling of an
    /// auth endpoint as scripted traffic and blocks it.
    private var pageLoaded = false
    /// One-shot guard so a genuine, non-cookie block does not loop.
    private var clearedForBlockPage = false

    init(onProbeResult: @escaping (WebSessionProbeResult) -> Void) {
        self.onProbeResult = onProbeResult
        super.init()
    }

    static let loginURL = URL(string: "https://www.reddit.com/login")!

    func attach(to webView: WKWebView) {
        self.webView = webView
        webView.navigationDelegate = self
        load(clearingCookiesFirst: false)
        timer = Timer.scheduledTimer(withTimeInterval: WebSessionLoginWebView.probeInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.probe() }
        }
    }

    /// Loads the login page, optionally clearing Reddit cookies first,
    /// with a 4s safety timeout because WebKit occasionally drops a
    /// cookie-deletion completion.
    private func load(clearingCookiesFirst clearCookies: Bool) {
        guard let webView else { return }
        guard clearCookies else {
            webView.load(URLRequest(url: Self.loginURL))
            return
        }
        let store = webView.configuration.websiteDataStore.httpCookieStore
        var didLoad = false
        let loadOnce: () -> Void = { [weak self] in
            guard let self, !didLoad else { return }
            didLoad = true
            self.pageLoaded = false
            self.webView?.load(URLRequest(url: Self.loginURL))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { loadOnce() }
        store.getAllCookies { cookies in
            let reddit = cookies.filter { $0.domain.lowercased().hasSuffix("reddit.com") }
            guard !reddit.isEmpty else {
                Task { @MainActor in loadOnce() }
                return
            }
            let group = DispatchGroup()
            for cookie in reddit {
                group.enter()
                Task { @MainActor in store.delete(cookie) { group.leave() } }
            }
            group.notify(queue: .main) { loadOnce() }
        }
    }

    /// Detects Reddit's "whoa there, pardner!" network-policy interstitial.
    /// The block can be carried by a poisoned cookie in the shared
    /// jar rather than the client's IP or UA: the same request with a
    /// fresh cookie jar loads the real login form. Without recovery
    /// the user is stuck since every retry replays the same jar.
    private func recoverIfBlocked() {
        guard !clearedForBlockPage, let webView else { return }
        webView.evaluateJavaScript("document.body ? document.body.innerText.slice(0, 400) : ''") { [weak self] result, _ in
            guard let self else { return }
            let body = ((result as? String) ?? "").lowercased()
            guard body.contains("whoa there") || body.contains("blocked due to a network policy")
                    || body.contains("blocked by network security") else { return }
            self.clearedForBlockPage = true
            self.load(clearingCookiesFirst: true)
        }
    }

    /// Mark the page loaded and evaluate auth state once, on every
    /// completed navigation (the login POST itself is a fetch with no
    /// navigation, which is why the poll exists).
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageLoaded = true
        recoverIfBlocked()
        probe()
    }

    /// `fetch('/api/me.json')` run in the page's own content world (so
    /// httpOnly cookies are included) via `callAsyncJavaScript`, which
    /// treats this string as the body of an implicit async function.
    /// Must have an explicit top-level `return`, or the completion
    /// handler always receives `undefined` and the probe never detects
    /// a signed-in session.
    private func probe() {
        // Guard against a finished/unloaded probe firing again.
        guard !finished, pageLoaded, let webView else { return }
        let script = """
        try {
            const res = await fetch('/api/me.json', { credentials: 'include' });
            if (!res.ok) { return null; }
            const json = await res.json();
            return { name: json.name || (json.data && json.data.name), modhash: json.data ? json.data.modhash : null };
        } catch (e) {
            return null;
        }
        """
        webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let value):
                guard let dict = value as? [String: Any], let name = dict["name"] as? String, !name.isEmpty else { return }
                self.finishHarvest(username: name, modhash: dict["modhash"] as? String)
            case .failure:
                break
            }
        }
    }

    /// A far-future expiry used to persist otherwise session-only
    /// cookies.
    private static let farFutureCookieInterval: TimeInterval = 10000.0 * 24 * 60 * 60

    private func finishHarvest(username: String, modhash: String?) {
        guard !finished, let webView else { return }
        finished = true
        // The probe timer is deliberately NOT invalidated here. The
        // completeness gate below may need another tick to retry, and
        // the poll only stops once it has decided to ship a session.
        let store = webView.configuration.websiteDataStore.httpCookieStore
        store.getAllCookies { cookies in
            let redditCookies = cookies.filter { $0.domain.lowercased().hasSuffix("reddit.com") }

            // Completeness gate: just after the fetch-based login completes, the jar
            // can lack token_v2 (and /api/me.json can still omit the modhash).
            // Harvesting that partial state ships a session that works briefly then
            // dies. A poll vote made with it reaches Reddit but is not accepted,
            // surfacing as "Reddit did not confirm the poll vote" on an HTTP 200.
            let complete = WebSessionCompleteness.isComplete(
                cookieNames: redditCookies.map(\.name), modhash: modhash)

            if !complete && self.harvestAttempts < WebSessionCompleteness.maxIncompleteHarvestAttempts {
                // Let the 2s auth poll call us again; the timer is
                // still scheduled and only invalidated once a complete
                // harvest ships.
                Task { @MainActor in
                    self.harvestAttempts += 1
                    self.finished = false
                }
                return
            }
            // Proceeds anyway after the bounded retries: some flows
            // (old.reddit) never produce every field.

            // Persist session-only cookies before harvesting.
            // Without this, cookies the jar holds as session-scoped are
            // dropped when the web view goes away, so a harvested header
            // can reference cookies Reddit no longer honours.
            let farFuture = Date(timeIntervalSinceNow: Self.farFutureCookieInterval)
            for cookie in redditCookies where cookie.isSessionOnly || cookie.expiresDate == nil {
                var props = cookie.properties ?? [:]
                props.removeValue(forKey: .discard)
                props.removeValue(forKey: .maximumAge)
                props[.expires] = farFuture
                if let persistent = HTTPCookie(properties: props) {
                    Task { @MainActor in store.setCookie(persistent) }
                }
            }

            let header = redditCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            // A failed harvest must not ship an empty session.
            guard !header.isEmpty else {
                Task { @MainActor in self.finished = false }
                return
            }
            Task { @MainActor in
                // Committing to this session: stop the poll.
                self.timer?.invalidate()
                self.timer = nil
                self.onProbeResult(WebSessionProbeResult(username: username, modhash: modhash, cookieHeader: header))
            }
        }
    }
}

#if canImport(UIKit)
extension WebSessionLoginWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let webView = makeWebView()
        context.coordinator.attach(to: webView)
        return webView
    }
    func updateUIView(_ webView: WKWebView, context: Context) { loadContent(into: webView) }
}
#elseif canImport(AppKit)
extension WebSessionLoginWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let webView = makeWebView()
        context.coordinator.attach(to: webView)
        return webView
    }
    func updateNSView(_ webView: WKWebView, context: Context) { loadContent(into: webView) }
}
#endif
#endif
