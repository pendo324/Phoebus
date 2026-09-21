import Foundation

/// Picks a compact, representative set of comments to summarize rather than
/// the first N rendered rows: consensus (score), OP context, disagreement
/// (controversiality) and some thread-order signal, without paying for the
/// full comment section. Backs the card caption "Based on N representative
/// comments".
public enum AICommentSelector {
    /// Reborn's selection constants.
    public static let minComments = 5
    public static let minCommentChars = 500
    public static let maxCommentChars = 3000
    public static let maxComments = 16
    public static let maxSingleCommentChars = 300
    /// A comment shorter than this carries no summarizable content.
    public static let minSingleCommentChars = 30

    public struct Candidate: Sendable {
        public let id: String
        public let author: String
        public let body: String
        public let score: Int
        public let controversiality: Int
        public let depth: Int
        /// The POST's author, used to detect OP comments.
        public let linkAuthor: String

        public init(id: String, author: String, body: String, score: Int,
                    controversiality: Int, depth: Int, linkAuthor: String) {
            self.id = id
            self.author = author
            self.body = body
            self.score = score
            self.controversiality = controversiality
            self.depth = depth
            self.linkAuthor = linkAuthor
        }

        var isOP: Bool {
            !author.isEmpty && !linkAuthor.isEmpty
                && author.caseInsensitiveCompare(linkAuthor) == .orderedSame
        }
    }

    /// Eligibility: AutoModerator is excluded by name, since its comments are
    /// boilerplate rules text that would otherwise dominate a short thread.
    public static func isEligible(_ candidate: Candidate) -> Bool {
        let author = candidate.author.trimmingCharacters(in: .whitespacesAndNewlines)
        if author.isEmpty
            || author.caseInsensitiveCompare("AutoModerator") == .orderedSame
            || author.caseInsensitiveCompare("[deleted]") == .orderedSame {
            return false
        }
        if candidate.body == "[deleted]" || candidate.body == "[removed]" { return false }
        return cleanInputText(candidate.body, limit: maxSingleCommentChars).count >= minSingleCommentChars
    }

    /// Ranking, with Reborn's constants.
    ///
    /// The clamp on `score` matters: one 40k-upvote joke would
    /// otherwise outrank every substantive reply combined.
    public static func rank(_ candidate: Candidate, originalIndex: Int) -> Int {
        var rank = min(max(candidate.score, -50), 5000)
        if candidate.isOP { rank += 1400 }
        if candidate.controversiality > 0 { rank += 700 }
        rank -= min(max(candidate.depth, 0), 8) * 70
        rank -= min(originalIndex, 100) * 3
        return rank
    }

    /// The prompt-ready text plus how many comments it represents.
    ///
    /// Each line is `[kind, score N] body`, where kind is OP /
    /// controversial / comment - the labels are what let
    /// the model report disagreement and OP context.
    public static func gather(_ candidates: [Candidate]) -> (text: String, count: Int) {
        let eligible = candidates.enumerated().filter { isEligible($0.element) }
        let sorted = eligible.sorted { a, b in
            let rankA = rank(a.element, originalIndex: a.offset)
            let rankB = rank(b.element, originalIndex: b.offset)
            // Stable on ties: equal ranks keep their existing order.
            if rankA == rankB { return a.offset < b.offset }
            return rankA > rankB
        }

        var seen = Set<String>()
        var lines: [String] = []
        var joinedLength = 0
        var count = 0
        for (_, candidate) in sorted {
            if count >= maxComments || joinedLength >= maxCommentChars { break }
            let body = cleanInputText(candidate.body, limit: maxSingleCommentChars)
            if body.count < minSingleCommentChars { continue }
            if candidate.id.isEmpty || seen.contains(candidate.id) { continue }
            seen.insert(candidate.id)
            let kind = candidate.isOP
                ? "OP"
                : (candidate.controversiality > 0 ? "controversial" : "comment")
            let line = "[\(kind), score \(candidate.score)] \(body)"
            lines.append(line)
            joinedLength += line.count + 1
            count += 1
        }
        return (lines.joined(separator: "\n"), count)
    }

    /// Whether the gathered text clears BOTH thresholds.
    ///
    /// Both the comment COUNT check and this
    /// 500-character floor matter: five one-line "this" replies pass the
    /// count but contain nothing to summarize.
    public static func hasEnoughDiscussion(text: String, count: Int) -> Bool {
        count >= minComments && text.count >= minCommentChars
    }

    /// Collapses whitespace and truncates, so the prompt isn't paying
    /// for markdown blank lines.
    static func cleanInputText(_ text: String?, limit: Int) -> String {
        guard let text else { return "" }
        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(collapsed.prefix(limit))
    }
}
