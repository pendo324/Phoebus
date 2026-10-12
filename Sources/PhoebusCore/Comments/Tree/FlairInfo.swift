import Foundation

/// A tapped flair, for Apollo's flair alert (`FlairAlertController`): the
/// title "Flair", the flair in full (a pill truncates it), and OK. The line
/// naming the kind and the subreddit is Phoebus's own.
public struct FlairInfo: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable, Equatable {
        /// An author's flair, beside their name.
        case user
        /// A post's own flair, under its title.
        case post
    }

    public let kind: Kind
    public let text: String
    public let parts: [FlairPart]?
    public let subreddit: String?

    public init(kind: Kind, text: String, parts: [FlairPart]?, subreddit: String?) {
        self.kind = kind
        self.text = text
        self.parts = parts
        self.subreddit = subreddit
    }

    public var id: String { "\(kind)|\(subreddit ?? "")|\(text)" }

    public static let title = "Flair"

    /// "User flair in r/nfl", or just the kind when the subreddit is unknown.
    public var detail: String {
        let kindName = kind == .user ? "User flair" : "Post flair"
        let name = subreddit?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? kindName : "\(kindName) in r/\(name)"
    }

    /// What to draw: Reddit's rich parts when it sent any, else the plain
    /// text with its `:emoji:` codes (which name images) stripped.
    public var runs: [FlairPart.Kind] { Self.runs(text: text, parts: parts) }

    public static func runs(text: String, parts: [FlairPart]?) -> [FlairPart.Kind] {
        if let parts, !parts.isEmpty { return parts.map(\.kind) }
        let stripped = text.replacingOccurrences(of: #":[A-Za-z0-9_+\-]+:"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return stripped.isEmpty ? [] : [.text(stripped)]
    }

    /// The flair's words alone, for VoiceOver.
    public var spokenText: String {
        runs.compactMap { run -> String? in
            guard case .text(let value) = run else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
        .joined(separator: " ")
    }
}
