import Foundation

/// Subreddit-scoped writes Phoebus sends as `POST /r/<sub>/api/<action>`:
/// a post's or user's flair (selectflair), your own flair's visibility
/// (setflairenabled) and wiki saves (wiki/edit, the AutoModerator editor).
/// www.reddit.com 404s that form for cookie requests but serves the same
/// action as `POST /api/<action>` with the subreddit in an `r` form field, so
/// a web-session account sends it that way.
///
/// Reborn "Post flair and wiki saves" (#1309).
public enum WebSubredditWrite {
    private static let actions: Set<String> = ["selectflair", "setflairenabled", "wiki/edit"]

    /// The www form of a subreddit-scoped write, or nil when `path` isn't one
    /// of them. An `r` already in `parameters` is kept.
    public static func rewrite(path: String, parameters: [String: String]) -> (path: String, parameters: [String: String])? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 4, parts[0].lowercased() == "r", parts[2].lowercased() == "api" else { return nil }
        let action = parts[3...].joined(separator: "/").lowercased()
        guard actions.contains(action) else { return nil }
        var rewritten = parameters
        if rewritten["r"] == nil { rewritten["r"] = parts[1] }
        return ("/api/" + action, rewritten)
    }
}
