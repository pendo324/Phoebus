import Foundation

/// Detects Reborn's "Live Interactive Posts" (Devvit): a self-text post
/// whose `selftext` contains Reddit's old-Reddit fallback body, e.g.:
/// ```
/// This post contains content not supported on old Reddit.
/// [Click here to view the full post](https://sh.reddit.com/r/<sub>/comments/<id>)
/// ```
/// Both the "not supported on old Reddit" phrase and a `sh.reddit.com/r/`
/// link must appear within 300 characters of each other. Proximity, not a
/// length cap, keeps a post that merely quotes the fallback from matching
/// while still matching posts with a long markdown body above the
/// appended block. Selftext must be 40-40,000 characters.
public enum DevvitPostDetector {
    private static let markerWindow = 300
    private static let minBodyLength = 40
    private static let maxBodyLength = 40000

    public static func isDevvitPost(post: RedditPost) -> Bool {
        guard post.isSelf, let selftext = post.selftext else { return false }
        return selfTextIsInteractive(selftext)
    }

    /// The detection predicate on a raw selftext string, for callers that only
    /// have JSON (a raw `t3` `data` dictionary rather than a decoded model).
    public static func selfTextIsInteractive(_ body: String) -> Bool {
        guard body.count >= minBodyLength, body.count <= maxBodyLength else { return false }
        let lowered = body.lowercased()
        guard let fallbackRange = lowered.range(of: "not supported on old reddit") else { return false }

        let fallbackStart = lowered.distance(from: lowered.startIndex, to: fallbackRange.lowerBound)
        let fallbackEnd = lowered.distance(from: lowered.startIndex, to: fallbackRange.upperBound)
        let from = max(0, fallbackStart - markerWindow)
        let to = min(lowered.count, fallbackEnd + markerWindow)
        guard from < to else { return false }

        let startIndex = lowered.index(lowered.startIndex, offsetBy: from)
        let endIndex = lowered.index(lowered.startIndex, offsetBy: to)
        let window = lowered[startIndex..<endIndex]
        return window.contains("sh.reddit.com/r/")
    }

    /// Whether the feed row shows the widget: the master switch and
    /// `GeneralSettings.devvitFeedWidgets` ("Show in Feed") both on. Pure and
    /// SwiftUI-free so it is smoke-testable. When `false` the row renders the
    /// normal selftext/thumbnail; the post-detail header widget is gated by the
    /// master switch alone.
    public static func feedShouldShowWidget(post: RedditPost, devvitInteractivePosts: Bool, devvitFeedWidgets: Bool) -> Bool {
        guard devvitInteractivePosts, devvitFeedWidgets else { return false }
        return isDevvitPost(post: post)
    }

    /// Whether AI features should treat this post as having no body.
    ///
    /// Reborn #1046: a live interactive post renders as its widget, and its
    /// `selftext` is the fallback text plus a data blob, which would otherwise
    /// be summarized as markup. Post and link summaries (and the discussion
    /// summary's body context) treat it as bodyless; the comment-based
    /// discussion summary still works.
    ///
    /// Gated on the master switch only, not the feed toggle: whether the body
    /// is data-blob markup is independent of where the widget is shown.
    public static func aiShouldTreatAsBodyless(post: RedditPost, devvitInteractivePosts: Bool) -> Bool {
        guard devvitInteractivePosts else { return false }
        return isDevvitPost(post: post)
    }
}
