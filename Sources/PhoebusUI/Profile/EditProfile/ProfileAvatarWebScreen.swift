import SwiftUI
import PhoebusCore
#if canImport(WebKit) && canImport(UIKit)
import WebKit
import UIKit

/// Edit Profile's Avatar row: reddit.com's profile settings, where a photo or
/// the avatar builder can be chosen, signed in as the account being edited.
/// Phoebus's own design; Reborn's Edit Profile shows the same page (#1367).
///
/// The account's stored web session goes into a private, non-persistent data
/// store that belongs to this one web view, so the page can only be signed in
/// as the account it was opened for and the shared jar the web sign-in keeps
/// is never touched. A rejected session offers the web sign-in again.
struct ProfileAvatarWebScreen: View {
    let username: String
    @Environment(\.accountManager) private var accountManager
    @StateObject private var model: ProfileAvatarWebModel
    @State private var showingWebSignIn = false

    init(username: String) {
        self.username = username
        _model = StateObject(wrappedValue: ProfileAvatarWebModel(username: username))
    }

    var body: some View {
        ZStack {
            ProfileAvatarWebHost(webView: model.webView)
                .ignoresSafeArea(.container, edges: .bottom)
            if model.state != .ready {
                cover
                    .transition(.opacity)
            }
        }
        .navigationTitle("Avatar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { model.reload() } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    Button {
                        UIApplication.shared.open(model.systemURL)
                    } label: {
                        Label("Open in Safari", systemImage: "safari")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel("More Options")
                }
                .accessibilityIdentifier("profileAvatar.options")
            }
        }
        .onAppear { model.appeared() }
        .sheet(isPresented: $showingWebSignIn) {
            NavigationStack {
                WebSessionLoginScreen(
                    requiredUsername: username,
                    onSuccess: { credential in
                        accountManager?.addWebSessionAccount(credential)
                        showingWebSignIn = false
                        model.webSignInFinished()
                    },
                    onCancel: { showingWebSignIn = false })
            }
        }
    }

    private var cover: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 10) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 46))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                switch model.state {
                case .loading:
                    ProgressView().padding(.top, 8)
                case .signIn:
                    Button("Sign In") { showingWebSignIn = true }
                        .buttonStyle(.bordered)
                        .padding(.top, 8)
                        .accessibilityIdentifier("profileAvatar.signIn")
                    openInSafariButton
                case .failed:
                    Button("Try Again") { model.reload() }
                        .buttonStyle(.bordered)
                        .padding(.top, 8)
                        .accessibilityIdentifier("profileAvatar.retry")
                    openInSafariButton
                case .ready:
                    EmptyView()
                }
            }
            .padding(.horizontal, 32)
            .offset(y: -24)
        }
    }

    private var openInSafariButton: some View {
        Button("Open in Safari") { UIApplication.shared.open(model.systemURL) }
            .accessibilityIdentifier("profileAvatar.openInSafari")
    }

    private var title: String {
        switch model.state {
        case .signIn: return "Reddit Sign-In Needed"
        case .failed: return "Page Couldn’t Open"
        default: return "Opening Reddit"
        }
    }

    private var detail: String {
        switch model.state {
        case .signIn(let detail), .failed(let detail): return detail
        default: return "Signing in as u/\(username)…"
        }
    }
}

private struct ProfileAvatarWebHost: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}

@MainActor
final class ProfileAvatarWebModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    enum State: Equatable {
        case loading
        case signIn(String)
        case failed(String)
        case ready
    }

    @Published private(set) var state: State = .loading

    let username: String
    let webView: WKWebView
    private var pageURL = ProfileAvatarWeb.pageURL
    private var started = false
    private var generation = 0

    init(username: String) {
        self.username = username
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.customUserAgent = ScrapeWebView.safariUserAgent()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        // A long-press preview would load the link outside the policy below.
        webView.allowsLinkPreview = false
    }

    /// The page on screen, for "Open in Safari".
    var systemURL: URL { ProfileAvatarWeb.reloadURL(current: webView.url) }

    func appeared() {
        guard !started else { return }
        started = true
        seedAndLoad()
    }

    func reload() {
        pageURL = ProfileAvatarWeb.reloadURL(current: webView.url)
        seedAndLoad()
    }

    func webSignInFinished() {
        if WebSessionRegistry.featureSession(for: username)?.cookieHeader.isEmpty == false {
            pageURL = ProfileAvatarWeb.pageURL
            seedAndLoad()
        } else {
            state = .signIn("That sign-in wasn’t u/\(username). Sign in with that account to change its avatar.")
        }
    }

    private func seedAndLoad() {
        generation += 1
        let generation = generation
        let header = WebSessionRegistry.featureSession(for: username)?.cookieHeader ?? ""
        guard !header.isEmpty else {
            webView.stopLoading()
            state = .signIn("Sign in to Reddit as u/\(username) to change your avatar here.")
            return
        }
        webView.stopLoading()
        state = .loading
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let cookies = WebSessionCookies.cookies(fromHeader: header)
        let url = pageURL
        Task { @MainActor [weak self] in
            for cookie in cookies { await store.setCookie(cookie) }
            guard let self, generation == self.generation else { return }
            webView.load(URLRequest(url: url))
        }
    }

    private func sessionRejected() {
        generation += 1
        webView.stopLoading()
        state = .signIn("Your Reddit web session for u/\(username) has expired. Sign in again to change your avatar.")
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        let frame: ProfileAvatarWeb.TargetFrame
        if let target = navigationAction.targetFrame {
            frame = target.isMainFrame ? .main : .sub
        } else {
            frame = .newWindow
        }
        let url = navigationAction.request.url
        switch ProfileAvatarWeb.decision(for: url, tapped: navigationAction.navigationType == .linkActivated, frame: frame) {
        case .allow:
            if frame == .newWindow {
                webView.load(navigationAction.request)
                return .cancel
            }
            return .allow
        case .cancel:
            return .cancel
        case .sessionRejected:
            sessionRejected()
            return .cancel
        case .openInSystem:
            if let url { UIApplication.shared.open(url, options: [:], completionHandler: nil) }
            return .cancel
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        // While the page is still opening, a refusal means the same as a
        // redirect to the login page.
        if navigationResponse.isForMainFrame, state == .loading,
           let response = navigationResponse.response as? HTTPURLResponse,
           ProfileAvatarWeb.isSessionRefusal(statusCode: response.statusCode, url: response.url) {
            sessionRejected()
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard state == .loading else { return }
        withAnimation(.easeOut(duration: 0.2)) { state = .ready }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationFailed(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationFailed(error)
    }

    private func navigationFailed(_ error: Error) {
        let nsError = error as NSError
        // -999: superseded by another load or stopped by our own cancel. 102
        // (frame load interrupted by a policy change): a navigation the policy
        // cancelled. Neither is a failure.
        if (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled)
            || (nsError.domain == "WebKitErrorDomain" && nsError.code == 102) { return }
        // A page that is already up keeps showing; only the first load turns
        // into an error screen.
        guard state == .loading else { return }
        state = .failed("Check your connection, then try again.")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // The process ends under memory pressure while the screen is in the
        // background; the page is blank on return, so it loads again.
        reload()
    }

    // MARK: WKUIDelegate

    /// target="_blank" links are routed in the policy above, which cancels
    /// them, so this only runs if WebKit skips it: never a second web view.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        if ProfileAvatarWeb.decision(for: url, tapped: true, frame: .newWindow) == .openInSystem {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        } else if ProfileAvatarWeb.isRedditURL(url), !ProfileAvatarWeb.isLoginURL(url), !ProfileAvatarWeb.isLogoutURL(url) {
            webView.load(navigationAction.request)
        }
        return nil
    }
}
#endif
