#if canImport(WebKit) && canImport(UIKit)
import UIKit
import WebKit

/// Hosts a `window.open()` popup for the sign-in web views. Reborn "Sign-in
/// popups" (#1342, #1372): Reddit's login page runs "Continue with Google"
/// and "Continue with Apple" in popup mode (the button opens the provider's
/// page with `window.open()`, waits for it to post the result back to
/// `window.opener`, and the popup closes itself). A `WKWebView` with no
/// `WKUIDelegate` drops the window, so both buttons did nothing.
///
/// The popup's web view is built from the configuration WebKit passes in,
/// unchanged: that keeps `window.opener` connected and shares the sign-in
/// web view's cookie store, so the main login completes.
@MainActor
final class WebAuthPopupViewController: UIViewController {
    private var webView: WKWebView?
    private let spinner = UIActivityIndicatorView(style: .medium)

    /// Presents a popup sheet above the sign-in sheet that contains `webView`
    /// and returns the popup's web view for WebKit to load the request into,
    /// or `nil` when the sign-in sheet isn't on screen or is already covered.
    static func present(from webView: WKWebView, configuration: WKWebViewConfiguration,
                        navigationAction: WKNavigationAction) -> WKWebView? {
        guard let host = hostViewController(for: webView) else { return nil }
        return present(over: host, configuration: configuration, navigationAction: navigationAction)
    }

    /// `host` is the sign-in sheet's view controller. A window request with an
    /// alert or another popup already up is dropped.
    static func present(over host: UIViewController, configuration: WKWebViewConfiguration,
                        navigationAction: WKNavigationAction) -> WKWebView? {
        guard host.view.window != nil, !host.isBeingDismissed, host.presentedViewController == nil else { return nil }

        let popup = WebAuthPopupViewController()
        let popupWebView = WKWebView(frame: .zero, configuration: configuration)
        // Google's sign-in can refuse an embedded web view, which the default
        // WKWebView user agent announces. Only the popup gets Safari's.
        popupWebView.customUserAgent = ScrapeWebView.safariUserAgent()
        popupWebView.uiDelegate = popup
        popupWebView.navigationDelegate = popup
        popup.webView = popupWebView
        popup.title = navigationAction.request.url?.host ?? "Sign In"

        let nav = UINavigationController(rootViewController: popup)
        nav.modalPresentationStyle = .formSheet
        host.present(nav, animated: true)
        return popupWebView
    }

    /// The top of the sheet's view-controller tree that `webView` lives in.
    private static func hostViewController(for webView: WKWebView) -> UIViewController? {
        var responder: UIResponder? = webView
        while let next = responder?.next {
            if var controller = next as? UIViewController {
                while let parent = controller.parent { controller = parent }
                return controller
            }
            responder = next
        }
        return nil
    }

    /// Closes a popup open above the sheet containing `webView`, then runs
    /// `then`. Call it before the sign-in finishes or presents an alert: an
    /// alert presented while a popup is on top never shows. Runs `then` right
    /// away when no popup is open.
    static func closePopups(above webView: WKWebView, then: @escaping () -> Void) {
        guard let host = hostViewController(for: webView),
              let nav = host.presentedViewController as? UINavigationController,
              nav.viewControllers.first is WebAuthPopupViewController else {
            then()
            return
        }
        if nav.isBeingDismissed, let coordinator = nav.transitionCoordinator {
            // UIKit ignores a second dismiss while the first is animating.
            coordinator.animate(alongsideTransition: nil) { _ in
                DispatchQueue.main.async(execute: then)
            }
            return
        }
        host.dismiss(animated: false, completion: then)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let cancel = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.close() })
        cancel.accessibilityIdentifier = "signin.popup.cancel"
        navigationItem.leftBarButtonItem = cancel

        if let webView {
            webView.frame = view.bounds
            webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(webView)
        }
        spinner.hidesWhenStopped = true
        spinner.center = view.center
        spinner.autoresizingMask = [.flexibleTopMargin, .flexibleBottomMargin, .flexibleLeftMargin, .flexibleRightMargin]
        view.addSubview(spinner)
        if webView?.isLoading == true { spinner.startAnimating() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Cancel, swipe-down, window.close() and `closePopups` all end here.
        // Releasing the web view closes its page, so the opener sees
        // `window.closed` and Reddit's button works again on the next tap.
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            tearDownWebView()
        }
    }

    private func tearDownWebView() {
        guard let webView else { return }
        webView.uiDelegate = nil
        webView.navigationDelegate = nil
        webView.stopLoading()
        webView.removeFromSuperview()
        self.webView = nil
    }

    private func close() {
        guard navigationController?.isBeingDismissed != true else { return }
        dismiss(animated: true)
    }
}

extension WebAuthPopupViewController: WKUIDelegate {
    /// Google and Apple close their popup with `window.close()` once the
    /// result is posted back to the opener.
    func webViewDidClose(_ webView: WKWebView) {
        close()
    }

    /// A link inside the popup asking for yet another window would replace the
    /// sign-in page the opener is waiting on, so it is left alone.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        nil
    }
}

extension WebAuthPopupViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        spinner.startAnimating()
    }

    /// The title shows the host the popup is on, as Safari's address bar would.
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let host = webView.url?.host, !host.isEmpty { title = host }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        spinner.stopAnimating()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        spinner.stopAnimating()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        spinner.stopAnimating()
    }
}
#endif
