import Foundation

/// Apollo's "Find in Comments" matcher: walks post body, author, subreddit,
/// and every comment's author + body in document order, with comma-separated
/// multi-term OR ("word1, word2" finds either term). Apollo's native matcher
/// searches the literal comma-joined string and finds nothing for multiple
/// terms; Reborn splits on commas and takes the earliest match of any term.
public struct CommentSearchMatch: Identifiable, Equatable, Sendable {
    /// The comment this match belongs to, or nil for the post itself.
    public let commentID: String?
    public let id: String

    public init(commentID: String?) {
        self.commentID = commentID
        self.id = commentID ?? "__post__"
    }
}

public enum CommentSearchEngine {
    /// Splits a query on commas into non-empty, trimmed search terms. A plain
    /// query with no comma is just itself.
    public static func terms(for query: String) -> [String] {
        query.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public static func matches(_ text: String, query: String) -> Bool {
        let queryTerms = terms(for: query)
        guard !queryTerms.isEmpty else { return false }
        return queryTerms.contains { text.range(of: $0, options: .caseInsensitive) != nil }
    }

    /// Finds every comment (in a document-order flattened list) whose author or
    /// body matches any term, plus the post itself if its title/selftext/author
    /// matches.
    public static func findMatches(
        query: String,
        postTitle: String,
        postSelftext: String?,
        postAuthor: String,
        subreddit: String,
        flattenedComments: [(id: String, author: String, body: String)]
    ) -> [CommentSearchMatch] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        var results: [CommentSearchMatch] = []
        let postHaystack = [postTitle, postSelftext ?? "", postAuthor, subreddit].joined(separator: " ")
        if matches(postHaystack, query: query) {
            results.append(CommentSearchMatch(commentID: nil))
        }
        for comment in flattenedComments {
            let haystack = comment.author + " " + comment.body
            if matches(haystack, query: query) {
                results.append(CommentSearchMatch(commentID: comment.id))
            }
        }
        return results
    }
}
