import Foundation

/// Two mutually-exclusive comment-sort memories (Reborn PR #570):
///
/// - `.subreddit`: change a post's sort and every post in that subreddit
///   reopens on it (stock Apollo's behaviour).
/// - `.post`: change a post's sort and only that post reopens on it
///   (Reborn addition, `UDKeyPerPostCommentSortMapping`).
///
/// Both memories are fed by the same gesture (the in-post sort menu), so with
/// both on a single pick could not say whether the user meant "pin this post"
/// or "move the whole subreddit". Enabling one turns the other off.
public enum CommentSortMemoryMode: String, Codable, CaseIterable, Sendable {
    case off
    case subreddit
    case post

    public var title: String {
        switch self {
        case .off: return "Off"
        case .subreddit: return "Remember Subreddit Sort"
        case .post: return "Remember Post Sort"
        }
    }
}

/// Persists both memory stores. Only the active mode is written, but both
/// dictionaries are kept so switching modes does not lose the other's history.
public enum CommentSortMemoryStore {
    private static let modeKey = "Phoebus.commentSortMemoryMode"
    private static let subredditKey = "Phoebus.commentSortBySubreddit"
    private static let postKey = "Phoebus.commentSortByPost"

    public static func loadMode() -> CommentSortMemoryMode {
        guard let raw = UserDefaults.standard.string(forKey: modeKey),
              let mode = CommentSortMemoryMode(rawValue: raw) else {
            return .off
        }
        return mode
    }

    public static func saveMode(_ mode: CommentSortMemoryMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: modeKey)
    }

    /// Live Update (8) is never persisted: its 10s live-refresh timer only starts
    /// from the sort menu handler, so restoring "live" at open would show the live
    /// icon without live behavior.
    public static func recordSortChange(subreddit: String, postID: String, sort: String) {
        guard sort != "live" else { return }
        switch loadMode() {
        case .off:
            return
        case .subreddit:
            var map = subredditMap()
            map[subreddit.lowercased()] = sort
            UserDefaults.standard.set(map, forKey: subredditKey)
        case .post:
            var map = postMap()
            map[postID] = sort
            UserDefaults.standard.set(map, forKey: postKey)
        }
    }

    /// The remembered sort for a given post, if the active mode has one; nil
    /// falls through to the caller's own default chain.
    public static func rememberedSort(subreddit: String, postID: String) -> String? {
        switch loadMode() {
        case .off:
            return nil
        case .subreddit:
            return subredditMap()[subreddit.lowercased()]
        case .post:
            return postMap()[postID]
        }
    }

    private static func subredditMap() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: subredditKey) as? [String: String] ?? [:]
    }

    private static func postMap() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: postKey) as? [String: String] ?? [:]
    }
}
