import Foundation

/// Share as Image's "Link" menu (Reborn #1278):
/// which permalink rides alongside a shared card or video. Stored under
/// Reborn's own keys so a Reborn backup carries it.
public enum ShareLinkMode: Int, CaseIterable, Sendable {
    case none = 0
    case post = 1
    case comment = 2

    public static let preferenceKey = "ApolloShareAsImageLinkMode"
    /// Reborn's old Boolean "Include Link", kept in step for older builds.
    public static let legacyEnabledKey = "ApolloShareAsImageIncludeLink"
    /// Legacy Boolean from before the menu (read once, never written).
    static let rewriteLegacyKey = "ApolloShareIncludeLink"

    public var title: String {
        switch self {
        case .none: return "No Link"
        case .post: return "Post Link"
        case .comment: return "Comment Link"
        }
    }

    /// The menu's choices: Comment Link only when a comment is shared.
    public static func options(hasComment: Bool) -> [ShareLinkMode] {
        hasComment ? [.none, .post, .comment] : [.none, .post]
    }

    /// The saved choice. An old Boolean "on" reads as Post Link. On a post
    /// share a saved Comment reads as Post, without writing it back, so the
    /// next comment share still remembers Comment.
    public static func read(_ defaults: UserDefaults = .standard, hasComment: Bool) -> ShareLinkMode {
        let mode: ShareLinkMode
        if let stored = defaults.object(forKey: preferenceKey) as? NSNumber,
           let valid = ShareLinkMode(rawValue: stored.intValue) {
            mode = valid
        } else {
            mode = defaults.bool(forKey: legacyEnabledKey) || defaults.bool(forKey: rewriteLegacyKey) ? .post : .none
        }
        return !hasComment && mode == .comment ? .post : mode
    }

    public static func write(_ mode: ShareLinkMode, _ defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: preferenceKey)
        defaults.set(mode != .none, forKey: legacyEnabledKey)
    }

    /// The link to attach, or nil for No Link.
    public func url(post: URL, comment: URL?) -> URL? {
        switch self {
        case .none: return nil
        case .post: return post
        case .comment: return comment ?? post
        }
    }
}
