import Foundation

/// Which inbox rows have an account to draw an avatar for. A row only gets
/// one when its sender is a real username: a subreddit's notice, a deleted
/// author or a chat room named by a sentence has no `/user/<name>/about`,
/// and asking for it is a wasted 404 per row.
public enum InboxAvatarPolicy {
    /// Reddit usernames are 3 to 20 letters, digits, `_` or `-`.
    public static func isUsername(_ text: String) -> Bool {
        (3...20).contains(text.count) && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }

    /// The account behind a message's `author`, or nil for no avatar.
    public static func avatarUsername(forAuthor author: String) -> String? {
        isUsername(author) ? author : nil
    }

    /// The account behind a chat room's row title. The title is the other
    /// person's name, but also the room's own name (a sentence from a
    /// subreddit's notice), several names joined, an account id, or the
    /// "Conversation" fallback.
    public static func avatarUsername(forChatTitle title: String) -> String? {
        guard isUsername(title), title != "Conversation", !title.hasPrefix("t2_") else { return nil }
        return title
    }
}
