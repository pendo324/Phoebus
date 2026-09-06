import Foundation
import PhoebusCore
#if canImport(WebKit) && canImport(UIKit)
import WebKit
import UIKit

/// Reborn's "Universal OAuth Sign-In" switch (`apollo_usesCustomOAuthSignIn`):
/// "Signs in with an in-app web view so any Redirect URI works, including
/// http/https (\"Web app\" Reddit API clients). Turn off for Apollo's native
/// sign-in."
///
/// `ASWebAuthenticationSession` (the default when this switch is off) needs the
/// redirect URI's scheme registered with the OS, so it never calls back for a
/// "web app" client whose redirect URI is an ordinary `http(s)://` URL. This
/// plain-`WKWebView` alternative inspects every navigation itself: when the URL
/// matches the configured redirect URI it cancels that navigation and hands the
/// URL back like `ASWebAuthenticationSession`'s completion handler would.
///
/// `@MainActor`: it owns UIKit views and a `WKWebView`, and this lets the
/// `@objc` cancel action and the `WKNavigationDelegate` callback reach `finish`
/// without tripping Swift 6's sending-`self` checks.
@MainActor
public final class CustomOAuthSession: NSObject {
    public typealias CompletionHandler = (URL?, Error?) -> Void

    private let url: URL
    private let redirectURIPrefix: String
    private let completionHandler: CompletionHandler
    private weak var explicitPresenter: UIViewController?
    private var webView: WKWebView?
    private var hostNavigationController: UINavigationController?
    /// Keeps the session alive while its sheet is up: the caller holds it only as
    /// a local, and the web view's delegate, the Cancel button's target and the
    /// present completion all reference it weakly.
    private var retainedWhilePresented: CustomOAuthSession?
    private var isFinished = false
    /// A rejected sign-in has already been explained, so Reddit's own 400
    /// authorize page doesn't stack a second alert.
    private var explainedRejectedSignIn = false

    /// - Parameters:
    ///   - url: the authorize URL to load (from `RedditAuthClient.buildAuthorizeURL`).
    ///   - redirectURIPrefix: the configured redirect URI (`RedditOAuthConfig.redirectURI`); any
    ///     navigation whose URL starts with this string is treated as the OAuth callback.
    ///   - presentingViewController: explicit presenter, or `nil` to fall back to the key
    ///     window's root view controller.
    public init(url: URL, redirectURIPrefix: String, presentingViewController: UIViewController? = nil, completionHandler: @escaping CompletionHandler) {
        self.url = url
        self.redirectURIPrefix = redirectURIPrefix
        self.explicitPresenter = presentingViewController
        self.completionHandler = completionHandler
    }

    /// Mirrors `ASWebAuthenticationSession.start()`'s shape so call sites
    /// can branch between the two with minimal duplication.
    @MainActor
    public func start() {
        guard let presenter = explicitPresenter ?? Self.keyWindowRootViewController() else {
            completionHandler(nil, URLError(.cannotFindHost))
            return
        }

        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = self
        self.webView = webView

        let container = UIViewController()
        container.view.backgroundColor = .systemBackground
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.view.bottomAnchor),
        ])
        container.title = "Sign In"
        container.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped)
        )

        let nav = UINavigationController(rootViewController: container)
        nav.modalPresentationStyle = .formSheet
        // Swiping the sheet away is a cancel, not a hang.
        nav.presentationController?.delegate = self
        self.hostNavigationController = nav
        retainedWhilePresented = self

        presenter.present(nav, animated: true) { [weak self] in
            guard let self else { return }
            self.webView?.load(URLRequest(url: self.url))
        }
    }

    private static func keyWindowRootViewController() -> UIViewController? {
        UIKitTree.keyWindow?
            .rootViewController
    }

    @objc private func cancelTapped() {
        finish(url: nil, error: URLError(.cancelled))
    }

    private func finish(url: URL?, error: Error?) {
        // The continuation behind `completionHandler` must resume once.
        guard !isFinished else { return }
        isFinished = true
        defer { retainedWhilePresented = nil }
        hostNavigationController?.presentingViewController?.dismiss(animated: true)
        hostNavigationController = nil
        webView?.navigationDelegate = nil
        webView = nil
        completionHandler(url, error)
    }
}

extension CustomOAuthSession: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        if let requestURL = navigationAction.request.url, requestURL.absoluteString.hasPrefix(redirectURIPrefix) {
            decisionHandler(.cancel)
            finish(url: requestURL, error: nil)
            return
        }
        decisionHandler(.allow)
    }

    /// Reddit's consent page shows Accept/Decline even for a key and redirect URI
    /// that match no Reddit app; only the POST to `/svc/shreddit/oauth-grant` fails,
    /// with a bare HTTP 400 "{}" body. That response is cancelled (the consent page
    /// stays) and explained; an error on the authorize page itself (Old Reddit's
    /// names the bad field) loads, with the same alert once (Reborn #1236).
    public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                        decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        let http = navigationResponse.response as? HTTPURLResponse
        guard navigationResponse.isForMainFrame, let http, let url = http.url else {
            decisionHandler(.allow)
            return
        }
        switch OAuthConsentFailure.classify(url: url, status: http.statusCode) {
        case .none:
            decisionHandler(.allow)
        case .grantRejected:
            decisionHandler(.cancel)
            explainRejectedSignIn(status: http.statusCode, offerOldReddit: true)
        case .authorizeRejected:
            decisionHandler(.allow)
            if !explainedRejectedSignIn { explainRejectedSignIn(status: http.statusCode, offerOldReddit: false) }
        }
    }

    private func explainRejectedSignIn(status: Int, offerOldReddit: Bool) {
        guard let container = hostNavigationController?.topViewController,
              container.presentedViewController == nil else { return }
        explainedRejectedSignIn = true
        let copy = OAuthConsentFailure.alert(status: status, offerOldReddit: offerOldReddit,
                                             hasCustomKey: CustomAPISettingsStore.load().redditClientID?
                                                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        let alert = UIAlertController(title: copy.title, message: copy.message, preferredStyle: .alert)
        if offerOldReddit {
            alert.addAction(UIAlertAction(title: "Switch to Old Reddit", style: .default) { [weak self] _ in
                guard let self else { return }
                // The grant endpoint has no Old Reddit twin: restart from
                // the authorize request.
                self.webView?.load(URLRequest(url: OAuthConsentFailure.oldRedditURL(self.url)))
            })
        }
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        container.present(alert, animated: true)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        // A load replaced by the next one (a redirect) isn't a failure.
        if (error as NSError).domain == NSURLErrorDomain, (error as NSError).code == NSURLErrorCancelled { return }
        Task { @MainActor in
            self.finish(url: nil, error: error)
        }
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // "Frame load interrupted": a response this class cancelled on
        // purpose (the rejected grant above), not a failed sign-in.
        let nsError = error as NSError
        if nsError.domain == "WebKitErrorDomain", nsError.code == 102 { return }
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
        Task { @MainActor in
            self.finish(url: nil, error: error)
        }
    }
}

extension CustomOAuthSession: UIAdaptivePresentationControllerDelegate {
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finish(url: nil, error: URLError(.cancelled))
    }
}
#endif
