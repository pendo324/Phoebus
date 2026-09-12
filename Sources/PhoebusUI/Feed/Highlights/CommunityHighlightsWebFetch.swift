import Foundation
#if canImport(WebKit)
import WebKit
import PhoebusCore

/// Full-mode Community Highlights: harvests up to 6 highlights from
/// Reddit's web carousel.
///
/// Ported from Reborn's community highlights web fetch. A web view is
/// needed because it is the only path past Reddit's JS bot-challenge
/// that blocks direct fetches: the OAuth token cannot reach the GraphQL
/// endpoint the first-party apps use, so the REST listing only returns
/// the two stickied posts old Reddit shows.
///
/// Partial mode is the REST result alone. Full adds this scrape on top
/// and never replaces it on failure; the carousel keeps the REST pair.
@MainActor
public final class CommunityHighlightsWebFetch: NSObject {
    /// Timing constants matching Reborn.
    public static let initialPollDelay: TimeInterval = 0.20
    public static let pollInterval: TimeInterval = 0.50
    /// A small result is given this long to grow before it is accepted.
    public static let smallSetSettleDelay: TimeInterval = 3.0
    public static let timeout: TimeInterval = 18.0
    /// The carousel holds at most 6.
    public static let maximumItems = 6

    private var web: WKWebView?
    private var subreddit = ""
    private var done: (([ScrapedHighlight]) -> Void)?
    private var startedAt: Date?
    private var polls = 0
    private var bestItems: [ScrapedHighlight] = []
    private var pollScheduled = false
    private var evaluationInFlight = false
    private var awaitingLargeSetConfirmation = false
    /// "Prove your humanity" was seen at least once this fetch. A
    /// challenged load that still times out is retryable, unlike a
    /// clean page that genuinely has no highlights.
    private(set) public var sawChallenge = false

    public override init() { super.init() }

    deinit {
        // Last-resort insurance: the web view is attached to the window, so
        // dropping a fetch without destroying it would orphan an attached view.
        let web = self.web
        Task { @MainActor in ScrapeWebView.destroy(web) }
    }

    public func start(subreddit: String, completion: @escaping ([ScrapedHighlight]) -> Void) {
        self.subreddit = subreddit
        self.done = completion
        self.polls = 0
        self.startedAt = Date()
        self.bestItems = []
        self.pollScheduled = false
        self.evaluationInFlight = false
        self.awaitingLargeSetConfirmation = false
        self.sawChallenge = false

        let config = WKWebViewConfiguration()
        // The isolated, logged-out store (see `ScrapeWebView.sharedDataStore`);
        // a shared store returns only the first 2 posts.
        config.websiteDataStore = ScrapeWebView.sharedDataStore

        ScrapeWebView.create(configuration: config) { [weak self] web in
            guard let self, self.done != nil else {
                ScrapeWebView.destroy(web)
                return
            }
            self.web = web
            web.navigationDelegate = self
            web.load(URLRequest(url: URL(string: "https://www.reddit.com/r/\(subreddit)/")!))
            self.pollAfter(Self.initialPollDelay)
        }
    }

    public func cancel() {
        done = nil
        ScrapeWebView.destroy(web)
        web = nil
        reset()
    }

    private func reset() {
        pollScheduled = false
        evaluationInFlight = false
        awaitingLargeSetConfirmation = false
        startedAt = nil
        bestItems = []
    }

    /// Keeps exactly one scheduled probe and one `evaluateJavaScript` in
    /// flight so faster polling never stacks work in WebKit.
    private func pollAfter(_ delay: TimeInterval) {
        guard web != nil, !pollScheduled else { return }
        pollScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.pollScheduled = false
            self?.poll()
        }
    }

    private func poll() {
        guard let web, !evaluationInFlight else { return }
        let elapsed = startedAt.map { -$0.timeIntervalSinceNow } ?? 0
        if elapsed >= Self.timeout {
            finish(bestItems)
            return
        }
        evaluationInFlight = true
        polls += 1
        web.evaluateJavaScript(Self.scrapeJS) { [weak self] result, _ in
            guard let self else { return }
            self.evaluationInFlight = false
            guard self.web != nil else { return }

            let items = Self.parse(result)
            if items.count > self.bestItems.count { self.bestItems = items }
            if let text = result as? String, text.contains("Prove your humanity") {
                // Keep polling, since it can clear mid-fetch, but remember so a
                // timeout is classified blocked-not-empty.
                self.sawChallenge = true
            }

            let now = self.startedAt.map { -$0.timeIntervalSinceNow } ?? 0
            if self.bestItems.count > 2 && !self.awaitingLargeSetConfirmation && now < Self.timeout {
                // Reddit can hydrate a larger carousel progressively: once a probe
                // first sees more than the REST-sized two cards, take one confirming
                // probe before finishing.
                self.awaitingLargeSetConfirmation = true
                self.pollAfter(Self.pollInterval)
            } else if self.bestItems.count > 2
                        || (self.bestItems.count > 0 && now >= Self.smallSetSettleDelay) {
                self.finish(self.bestItems)
            } else if now >= Self.timeout {
                self.finish(self.bestItems)
            } else {
                self.pollAfter(Self.pollInterval)
            }
        }
    }

    private func finish(_ items: [ScrapedHighlight]) {
        ScrapeWebView.destroy(web)
        web = nil
        let completion = done
        done = nil
        reset()
        completion?(items)
    }

    /// The scrape: finds the leaf element whose text is exactly "community
    /// highlights", walks up to 7 parents until one contains a `/comments/`
    /// link, then de-duplicates those links by href and takes title + image.
    static let scrapeJS = """
    (function(){
    var all=document.querySelectorAll('*'),heading=null;
    for(var i=0;i<all.length;i++){var e=all[i];if(e.children.length===0&&(e.textContent||'').trim().toLowerCase()==='community highlights'){heading=e;break;}}
    if(!heading)return JSON.stringify({n:0,t:document.title});
    var c=heading;for(var d=0;d<7&&c.parentElement;d++){c=c.parentElement;if(c.querySelectorAll('a[href*="/comments/"]').length>=1)break;}
    var links=c.querySelectorAll('a[href*="/comments/"]');var seen={},out=[];
    for(var j=0;j<links.length;j++){var l=links[j];var h=(l.getAttribute('href')||'').split('?')[0];if(!h||seen[h])continue;var t=(l.textContent||'').trim().split('\\n')[0].trim();if(!t)continue;seen[h]=1;
    var img=l.querySelector('img');var src=img?(img.getAttribute('src')||img.getAttribute('data-src')||''):'';
    out.push({t:t.substring(0,140),h:h,img:src});}
    return JSON.stringify({n:out.length,items:out});})()
    """

    /// Parses the JS result. Pure and `static` so the rules are checkable
    /// without a web view.
    public static func parse(_ result: Any?) -> [ScrapedHighlight] {
        guard let text = result as? String,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["items"] as? [[String: Any]] else { return [] }
        var out: [ScrapedHighlight] = []
        for item in raw {
            guard let title = item["t"] as? String, !title.isEmpty,
                  let permalink = item["h"] as? String, !permalink.isEmpty else { continue }
            var thumbnail: URL?
            if let img = item["img"] as? String,
               img.hasPrefix("http"),
               // Skip the subreddit profile icon (shown for text-post highlights);
               // those render as plain text cards.
               img.range(of: "profileIcon", options: .caseInsensitive) == nil {
                thumbnail = URL(string: img)
            }
            out.append(ScrapedHighlight(title: title, permalink: permalink, thumbnailURL: thumbnail))
            if out.count >= maximumItems { break }
        }
        return out
    }
}

extension CommunityHighlightsWebFetch: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // On a warm WebKit process the full carousel is often present
        // immediately, so probe now instead of waiting for the fallback timer.
        if webView == web { poll() }
    }
}

/// One scraped highlight card.
public struct ScrapedHighlight: Equatable, Hashable, Sendable, Identifiable, Codable {
    public var title: String
    public var permalink: String
    public var thumbnailURL: URL?

    public var id: String { permalink }

    public init(title: String, permalink: String, thumbnailURL: URL? = nil) {
        self.title = title
        self.permalink = permalink
        self.thumbnailURL = thumbnailURL
    }
}
#endif

/// A subreddit's last fetched highlights, per mode, kept on disk so a
/// return visit, even after a relaunch, shows them without waiting on the
/// network.
@MainActor
final class CommunityHighlightsCache {
    static let shared = CommunityHighlightsCache()

    struct Entry: Codable {
        var posts: [RedditPost]
        var scraped: [ScrapedHighlight]
        var fetchedAt: Date
    }

    private lazy var entries: [String: Entry] = Self.read()

    private static var fileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("community-highlights.json")
    }

    /// Entries past the cache's lifetime are dropped on load.
    private static func read() -> [String: Entry] {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let all = try? JSONDecoder.reddit.decode([String: Entry].self, from: data) else { return [:] }
        return all.filter { !CommunityHighlights.isStale(fetchedAt: $0.value.fetchedAt) }
    }

    private func write() {
        guard let url = Self.fileURL, let data = try? JSONEncoder.reddit.encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func key(_ subreddit: String, _ mode: SubredditLayoutSettings.CommunityHighlightsMode) -> String {
        "\(subreddit.lowercased())|\(mode.rawValue)"
    }

    func entry(subreddit: String, mode: SubredditLayoutSettings.CommunityHighlightsMode) -> Entry? {
        entries[Self.key(subreddit, mode)]
    }

    func store(_ entry: Entry, subreddit: String, mode: SubredditLayoutSettings.CommunityHighlightsMode) {
        entries[Self.key(subreddit, mode)] = entry
        write()
    }
}
