import Foundation

/// The inbox row overview line: who did what, and to which post.
public enum InboxRowText {
    public enum Kind: Equatable, Sendable {
        case commentReply, postReply, mention, message

        /// The row's type glyph (`inbox-comment-type-*`).
        public var glyph: String {
            switch self {
            case .commentReply: return "inbox-comment-type-comment-reply"
            case .postReply: return "inbox-comment-type-post-reply"
            case .mention: return "inbox-comment-type-username-mention"
            case .message: return "inbox-comment-type-message"
            }
        }
    }

    public static func kind(of message: RedditMessage) -> Kind {
        guard message.wasComment else { return .message }
        switch message.subject.lowercased() {
        case "post reply": return .postReply
        case "username mention": return .mention
        default: return .commentReply
        }
    }

    /// One run of the overview: bold for names and titles.
    public struct Run: Equatable, Sendable {
        public let text: String
        public let bold: Bool
    }

    /// Stock's phrasing; a comment reply quotes the start of your comment
    /// when it's known, as Reborn's inbox shows.
    public static func overview(for message: RedditMessage, parentSnippet: String?) -> [Run] {
        let title = message.linkTitle ?? message.subject
        switch kind(of: message) {
        case .message:
            return [Run(text: message.subject, bold: true)]
        case .postReply:
            return [Run(text: message.author, bold: true), Run(text: " replied to your post ", bold: false),
                    Run(text: title, bold: true)]
        case .mention:
            return [Run(text: message.author, bold: true), Run(text: " mentioned you on the post ", bold: false),
                    Run(text: title, bold: true)]
        case .commentReply:
            guard let snippet = parentSnippet.map(quoteSnippet), !snippet.isEmpty else {
                return [Run(text: message.author, bold: true),
                        Run(text: " replied to your comment on the post ", bold: false),
                        Run(text: title, bold: true)]
            }
            return [Run(text: message.author, bold: true), Run(text: " replied to your comment ", bold: false),
                    Run(text: "\u{201C}\(snippet)\u{201D}", bold: false), Run(text: " in ", bold: false),
                    Run(text: title, bold: true)]
        }
    }

    /// The first 50 characters of the comment on one line, then an ellipsis.
    public static func quoteSnippet(_ body: String) -> String {
        let flat = GoogleSearch.plainText(fromMarkdown: body).split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard flat.count > 50 else { return flat }
        return String(flat.prefix(50)) + "\u{2026}"
    }
}
