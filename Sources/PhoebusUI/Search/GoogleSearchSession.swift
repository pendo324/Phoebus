#if canImport(WebKit) && canImport(UIKit)
import Foundation
import WebKit
import UIKit
import PhoebusCore

/// Runs one Google search the way a browser does (Reborn #1260). Google
/// has served results only to JavaScript clients since early 2025, so the page loads in a hidden
/// scrape web view and `GoogleSearch.extractorJS` reads the rendered DOM.
/// When Google shows its "unusual traffic" check or an EU consent page,
/// the same web view is handed to the user (`verificationWebView`) and
/// the search resumes by itself once Google returns to the results;
/// nothing is ever answered automatically.
@MainActor
final class GoogleSearchSession: NSObject, ObservableObject {
    struct Page {
        var results: [GoogleSearchResult]
        var mayHaveMore: Bool
    }

    enum SearchError: LocalizedError {
        case timedOut, network(String), verificationCancelled, unreadable

        var errorDescription: String? {
            switch self {
            case .timedOut: return "Google took too long to respond."
            case .network(let message): return message
            case .verificationCancelled: return "Google wanted to check this search first."
            case .unreadable: return "Google's results page couldn't be read."
            }
        }
    }

    /// Set while Google's check needs the user; the UI shows it in a sheet.
    @Published private(set) var verificationWebView: WKWebView?
    /// The first page is still loading after 8 s.
    @Published private(set) var isSlow = false

    private var web: WKWebView?
    private var generation = 0
    private var navigationError: Error?

    /// Persistent and dedicated, so Google's consent choice and the
    /// exemption cookie a solved check leaves behind survive relaunches:
    /// the user answers a prompt once, not every launch. Kept apart from
    /// the Reddit scrape jar.
    static let dataStore: WKWebsiteDataStore = {
        if #available(iOS 17.0, *), let id = UUID(uuidString: "6B0E4C1D-2F8A-4C39-9A57-3D1E8F6B2A94") {
            return WKWebsiteDataStore(forIdentifier: id)
        }
        return .nonPersistent()
    }()

    /// Phone layout with the device's own Safari identity on iPhone (a
    /// consistent fingerprint keeps Google's checks quiet); desktop on
    /// iPad, as iPad Safari asks for by default.
    static var usesDesktopLayout: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    static func userAgent(desktop: Bool) -> String {
        let parts = UIDevice.current.systemVersion.split(separator: ".").map(String.init)
        let major = parts.first ?? "18", minor = parts.count > 1 ? parts[1] : "0"
        return desktop
            ? "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(major).\(minor) Safari/605.1.15"
            : "Mozilla/5.0 (iPhone; CPU iPhone OS \(major)_\(minor) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(major).\(minor) Mobile/15E148 Safari/604.1"
    }

    /// One search at a time: a new one (or `cancel`) ends the previous
    /// one, which then throws `CancellationError`.
    func search(_ query: String, options: GoogleSearchOptions, page: Int) async throws -> Page {
        tearDown()
        guard let url = GoogleSearch.searchURL(query, options: options, page: page) else { return Page(results: [], mayHaveMore: false) }
        generation += 1
        let myGeneration = generation
        navigationError = nil
        isSlow = false
        let desktop = Self.usesDesktopLayout

        let config = WKWebViewConfiguration()
        config.websiteDataStore = Self.dataStore
        config.mediaTypesRequiringUserActionForPlayback = .all
        if desktop { config.defaultWebpagePreferences.preferredContentMode = .desktop }
        let web: WKWebView = await withCheckedContinuation { continuation in
            ScrapeWebView.create(configuration: config) { continuation.resume(returning: $0) }
        }
        guard myGeneration == generation else { ScrapeWebView.destroy(web); throw CancellationError() }
        self.web = web
        web.navigationDelegate = self
        web.customUserAgent = Self.userAgent(desktop: desktop)
        if desktop { web.frame = CGRect(x: 0, y: 0, width: 1280, height: 1000) }
        var request = URLRequest(url: url)
        request.timeoutInterval = GoogleSearch.pageTimeout
        web.load(request)

        let started = Date()
        var deadline = started.addingTimeInterval(GoogleSearch.pageTimeout)
        var emptyPolls = 0, stablePolls = 0, lastCount = -1
        try? await Task.sleep(nanoseconds: 600_000_000)
        while true {
            guard myGeneration == generation, let web = self.web else { throw CancellationError() }
            if Date() > deadline { finish(); throw SearchError.timedOut }
            if let navigationError {
                finish()
                throw (navigationError as? SearchError) ?? SearchError.network(navigationError.localizedDescription)
            }
            if page == 0, verificationWebView == nil, Date().timeIntervalSince(started) > GoogleSearch.slowNoticeDelay { isSlow = true }

            let extracted = try? await web.evaluateJavaScript(GoogleSearch.extractorJS) as? String
            guard myGeneration == generation else { throw CancellationError() }
            let info = extracted.flatMap { $0.data(using: .utf8) }
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            let raw = info["results"] as? [[String: Any]] ?? []
            let container = info["container"] as? Bool ?? false
            let complete = info["ready"] as? String == "complete"

            if info["challenge"] is String, raw.isEmpty {
                if verificationWebView == nil { present(web) }
                deadline = Date().addingTimeInterval(GoogleSearch.verificationTimeout)
                try? await Task.sleep(nanoseconds: 800_000_000)
                continue
            }
            if raw.isEmpty, container, complete {
                emptyPolls += 1
                if emptyPolls < GoogleSearch.emptyPollsToSettle {
                    try? await Task.sleep(nanoseconds: UInt64(GoogleSearch.pollInterval * 1e9))
                    continue
                }
                // Plenty of links but nothing recognizable: Google's markup
                // moved, not an empty search.
                if (info["anchorCount"] as? Int ?? 0) == 0, (info["containerLinks"] as? Int ?? 0) >= 5 {
                    finish()
                    throw SearchError.unreadable
                }
            }
            // Google streams the page: take it once loaded, or once the
            // result count has held steady a while.
            if !raw.isEmpty, !complete {
                stablePolls = raw.count == lastCount ? stablePolls + 1 : 0
                lastCount = raw.count
                if stablePolls < GoogleSearch.stablePollsToAccept {
                    try? await Task.sleep(nanoseconds: UInt64(GoogleSearch.pollInterval * 1e9))
                    continue
                }
            }
            if !raw.isEmpty || (container && complete) {
                let more = (info["next"] as? Bool ?? false) || raw.count >= 7
                finish()
                return Page(results: GoogleSearch.results(fromRaw: raw), mayHaveMore: more)
            }
            try? await Task.sleep(nanoseconds: UInt64(GoogleSearch.pollInterval * 1e9))
        }
    }

    func cancel() { tearDown() }

    /// The user closed the verification sheet: the search ends with
    /// "Google Check Not Finished".
    func verificationCancelledByUser() {
        navigationError = SearchError.verificationCancelled
    }

    private func present(_ web: WKWebView) {
        web.removeFromSuperview()
        web.alpha = 1
        web.isUserInteractionEnabled = true
        verificationWebView = web
    }

    /// Done with the page: WebKit's memory goes right away.
    private func finish() {
        isSlow = false
        verificationWebView = nil
        ScrapeWebView.destroy(web)
        web = nil
    }

    private func tearDown() {
        generation += 1
        finish()
    }

    // MARK: Following a result's link

    private final class RedirectStopper: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? { nil }
    }

    private static var follows: [URL: Task<URL?, Never>] = [:]

    /// Google hides each destination behind an encrypted `/goto` link, a
    /// plain 302. It's followed only when the user acts on a result (ten
    /// automated clicks per search is what Google's checks react to): one
    /// redirect-stopping GET with the search's own cookies and identity,
    /// so to Google it's the same browser clicking the result it showed.
    /// Concurrent actions on one result share the follow.
    static func follow(_ link: URL) async -> URL? {
        if let running = follows[link] { return await running.value }
        let task = Task<URL?, Never> { @MainActor in
            let cookies = await dataStore.httpCookieStore.allCookies()
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 8
            configuration.httpAdditionalHeaders = ["User-Agent": userAgent(desktop: usesDesktopLayout)]
            configuration.httpCookieStorage?.setCookies(cookies, for: link, mainDocumentURL: link)
            let session = URLSession(configuration: configuration, delegate: RedirectStopper(), delegateQueue: nil)
            defer { session.finishTasksAndInvalidate() }
            guard let (_, response) = try? await session.data(from: link),
                  let location = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Location") else { return nil }
            return URL(string: location, relativeTo: link)?.absoluteURL
        }
        follows[link] = task
        let target = await task.value
        follows[link] = nil
        return target
    }

    /// The result's Reddit URL, following its Google link when needed.
    static func resolve(_ result: GoogleSearchResult) async -> GoogleSearchResult? {
        if result.url != nil { return result }
        guard let link = result.googleLinkURL, let destination = await follow(link) else { return nil }
        var resolved = result
        return GoogleSearch.apply(destination, to: &resolved) ? resolved : nil
    }

    static func suggestions(for query: String) async -> [String] {
        guard let url = GoogleSearch.suggestionsURL(for: query),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return [] }
        return GoogleSearch.parseSuggestions(data)
    }
}

extension GoogleSearchSession: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        record(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        record(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        navigationError = SearchError.network("Google's page stopped responding.")
    }

    private func record(_ error: Error) {
        let ns = error as NSError
        // A cancelled load (a redirect replacing it) isn't a failure.
        if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled { return }
        if ns.domain == "WebKitErrorDomain", ns.code == 102 { return }
        navigationError = error
    }
}
#endif
