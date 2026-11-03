import Foundation

/// The authors a page of content hands to `AvatarCache.prefetch`, so a feed
/// page, an Inbox page or a "more replies" expansion costs one
/// `user_data_by_account_ids` request per 100 authors instead of one
/// `/about` per row (Reborn's API-Key-Free request diet, `Apollo-Reborn#1416`;
/// Phoebus applies it to every account). Only authors Reddit gave a `t2_` id
/// for qualify; each appears once.
public enum AvatarBatchAuthors {
    public typealias Author = (username: String, fullname: String)

    public static func authors(in posts: [RedditPost]) -> [Author] {
        unique(posts.map { ($0.author, $0.authorFullname) })
    }

    public static func authors(in messages: [RedditMessage]) -> [Author] {
        unique(messages.map { (InboxAvatarPolicy.avatarUsername(forAuthor: $0.author) ?? "", $0.authorFullname) })
    }

    public static func authors(in comments: [RedditComment]) -> [Author] {
        unique(comments.map { ($0.author, $0.authorFullname) })
    }

    private static func unique(_ pairs: [(String, String?)]) -> [Author] {
        var seen = Set<String>()
        var result: [Author] = []
        for (username, fullname) in pairs {
            guard let fullname, fullname.hasPrefix("t2_"), !username.isEmpty, username != "[deleted]",
                  seen.insert(username.lowercased()).inserted else { continue }
            result.append((username, fullname))
        }
        return result
    }
}
