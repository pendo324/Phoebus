import Foundation

/// Decides whether a post has an external ARTICLE worth summarizing,
/// and which of the three post-card titles applies.
///
/// This is the gate that picks "Post summary" vs "Link summary" vs
/// "Post/Link summary", so it can't be approximated: get it wrong and
/// the card either claims to have read an article it never fetched, or
/// tries to summarize a YouTube player page and produces nothing.
/// Mirrors Reborn's AI article detection.
public enum AIArticleDetector {
    /// Direct media/file URLs have no prose.
    static let mediaExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "gifv", "webp",
        "bmp", "mp4", "webm", "mov", "m4v", "mp3", "pdf",
    ]

    /// Registrable domains whose pages yield no article prose. The matcher
    /// also catches any subdomain, and the runtime "no prose -> hide" fallback
    /// covers anything not listed (clip hosts rotate domains faster than a
    /// list can track).
    static let blockedHosts: [String] = [
        // Reddit-internal + Reddit media (Apollo renders these natively)
        "reddit.com", "redd.it", "redditmedia.com",
        // Image / GIF / screenshot hosts - no article prose
        "imgur.com", "giphy.com", "tenor.com", "redgifs.com", "gfycat.com",
        "imgchest.com", "flickr.com", "ibb.co", "postimg.cc", "postimages.org",
        "imgbb.com", "prnt.sc", "gyazo.com", "imgflip.com",
        // Video / short-clip hosts (r/soccer goal clips etc.) - player-only pages
        "youtube.com", "youtu.be", "twitch.tv", "streamable.com", "streamja.com",
        "streamff.com", "streamff.pro", "streamff.live", "streamff.io", "streamff.net",
        "streamff.co", "streamin.one", "streamin.me", "streamin.link", "streamye.com",
        "streamwo.com", "streamgg.com", "streamvi.com", "dubz.co", "dubz.link",
        "dubz.cc", "dubz.one", "dropr.co", "sendvid.com", "clippituser.tv",
        "imgtc.com", "streamtape.com", "doodstream.com", "vidoza.net", "qu.ax",
        "juststream.live", "vidlii.com", "fb.watch",
        // Social / micro-post platforms - content is self-contained + already
        // shown inline, and the pages are JS-rendered SPAs with no article body
        "twitter.com", "x.com", "t.co", "twimg.com", "fixupx.com", "fxtwitter.com",
        "vxtwitter.com", "nitter.net", "bsky.app", "bsky.social", "threads.com",
        "threads.net", "instagram.com", "tiktok.com", "facebook.com", "fb.com",
        "tumblr.com", "weibo.com", "weibo.cn", "vk.com", "truthsocial.com",
        "mastodon.social", "mastodon.online", "discordapp.com",
    ]

    /// `post_hint` values that mark non-article content.
    static let nonArticleHints: Set<String> = [
        "image", "hosted:video", "rich:video", "gallery", "animated_gif",
    ]

    /// Article-candidate URL rule.
    public static func isArticleCandidate(_ urlString: String?) -> Bool {
        guard let urlString, let url = URL(string: urlString) else { return false }
        let scheme = (url.scheme ?? "").lowercased()
        guard scheme == "http" || scheme == "https" else { return false }
        if mediaExtensions.contains(url.pathExtension.lowercased()) { return false }
        var host = (url.host ?? "").lowercased()
        // Strip only these two prefixes: a general "drop the first label" rule
        // would turn news.bbc.co.uk into bbc.co.uk and could wrongly block it.
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        if host.hasPrefix("m.") { host = String(host.dropFirst(2)) }
        for blocked in blockedHosts {
            if host == blocked || host.hasSuffix("." + blocked) { return false }
        }
        return true
    }

    /// Finds the first article link in a self-post body.
    ///
    /// Markdown links come FIRST, deliberately: those are the explicit
    /// "here's the article" shares, so a post that links an article
    /// and also mentions a bare URL summarizes the article.
    private static let selfTextURLRegexes = [
        try! NSRegularExpression(pattern: #"\]\((https?://[^)\s]+)\)"#),  // markdown links, capture group 1
        try! NSRegularExpression(pattern: #"https?://[^\s)\]]+"#),        // then bare URLs, whole match
    ]

    public static func firstArticleURLInSelfText(_ selfText: String?) -> String? {
        guard let selfText, !selfText.isEmpty else { return nil }
        var candidates: [String] = []
        for (index, regex) in selfTextURLRegexes.enumerated() {
            let range = NSRange(selfText.startIndex..., in: selfText)
            for match in regex.matches(in: selfText, range: range) {
                let group = index == 0 ? 1 : 0
                guard let r = Range(match.range(at: group), in: selfText) else { continue }
                candidates.append(String(selfText[r]))
            }
        }
        // Trailing punctuation a URL picks up from surrounding prose.
        let trailing = CharacterSet(charactersIn: ".,;:)]\"'")
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: trailing)
            if isArticleCandidate(trimmed) { return trimmed }
        }
        return nil
    }

    /// Link-is-article rule. Self-posts are deliberately NOT excluded: a
    /// "link + text" post is a self-post whose URL still points at an
    /// article, and a pure self-post's URL is its own reddit.com permalink,
    /// which the host blocklist rejects anyway.
    public static func linkIsArticle(post: RedditPost) -> Bool {
        guard let urlString = post.url, !urlString.isEmpty else { return false }
        // Media posts -> no article prose to extract.
        if post.media?.redditVideo != nil { return false }
        if let gallery = post.galleryData?.items, !gallery.isEmpty { return false }
        if post.isCrosspost { return false }
        let hint = (post.postHint ?? "").lowercased()
        if !hint.isEmpty && nonArticleHints.contains(hint) { return false }
        return isArticleCandidate(urlString)
    }

    /// Article-URL resolution: a pure link post uses its own URL; a self-post
    /// uses the first article link in its body.
    public static func articleURL(for post: RedditPost) -> String? {
        // A Devvit widget post's "body" is Reddit's fallback markup
        // plus a data blob, so there is nothing to read. See
        // `DevvitPostDetector`.
        if DevvitPostDetector.isDevvitPost(post: post),
           DevvitPostDetector.selfTextIsInteractive(post.selftext ?? "") { return nil }
        if linkIsArticle(post: post) { return post.url }
        guard post.isSelf else { return nil }
        return firstArticleURLInSelfText(post.selftext)
    }

    /// Which post-card title applies, or `nil` when there is nothing
    /// to summarize.
    ///
    /// The condition order matters: BOTH wins over link-only, which wins over
    /// the plain post title.
    public static func postCardKind(for post: RedditPost, wordThreshold: Int) -> AISummaryCard.Kind? {
        let article = articleURL(for: post)
        let body = post.selftext ?? ""
        let words = body.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let bodyless = DevvitPostDetector.aiShouldTreatAsBodyless(post: post, devvitInteractivePosts: true)
        let hasBody = !bodyless && words > 0

        if article != nil {
            // Article present: a body alongside it gets both; a bare
            // link post gets the link title. The word threshold does
            // NOT apply here: linked articles remain eligible
            // regardless of length.
            return hasBody ? .postAndLink : .link
        }
        // Text-only post: the threshold decides. A two-line post is
        // shorter than any summary of it would be.
        guard hasBody,
              AISummaryPrompts.postMeetsThreshold(wordCount: words, threshold: wordThreshold) else {
            return nil
        }
        return .post
    }
}
