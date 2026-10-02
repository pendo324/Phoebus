import Foundation

/// A widget's chosen feed (Reborn "Widgets for Any Feed").
///
/// Feed and Post widgets have a Source picker (Home / Popular / All /
/// Subreddit or Multireddit), and the free-text field accepts everything
/// people type or paste:
///
/// | You type | You get |
/// |---|---|
/// | `soccer`, `r/soccer`, `https://reddit.com/r/soccer/top` | r/soccer |
/// | `soccer+nba`, `soccer, nba`, `r/soccer r/nba` | the combined listing |
/// | `home`, `popular`, `all` | the built-in feeds |
/// | `https://reddit.com/user/foo/m/bar`, `u/foo/m/bar` | foo's multireddit |
/// | `m/bar`, `/me/m/bar` | your own multireddit |
///
/// A bare `bar` is your own multireddit when it names one of yours, and
/// `r/bar` forces the subreddit reading. A widget extension cannot see the
/// multireddit list without the account setup code, so a bare name resolves
/// to a SUBREDDIT and `m/` is reserved for multireddits.
public enum WidgetFeedSource: Equatable, Sendable {
    case home
    case popular
    case all
    /// One or more subreddits; several become Reddit's `a+b` combined
    /// listing.
    case subreddits([String])
    /// `owner` is nil for "your own" (`m/bar`, `/me/m/bar`).
    case multireddit(owner: String?, name: String)

    /// The header text the widget shows: "Home", "r/soccer+nba", "m/bar".
    public var displayName: String {
        switch self {
        case .home: return "Home"
        case .popular: return "Popular"
        case .all: return "All"
        case .subreddits(let names): return "r/" + names.joined(separator: "+")
        case .multireddit(_, let name): return "m/" + name
        }
    }

    /// The listing path this source fetches.
    public var path: String {
        switch self {
        case .home: return ""
        case .popular: return "/r/popular"
        case .all: return "/r/all"
        case .subreddits(let names): return "/r/" + names.joined(separator: "+")
        case .multireddit(let owner, let name):
            if let owner { return "/user/\(owner)/m/\(name)" }
            return "/me/m/\(name)"
        }
    }

    /// Home and your own multireddits need the with-account setup code; the
    /// widget says so ("Sign in for this feed") instead of failing quietly.
    public var requiresAccount: Bool {
        switch self {
        case .home: return true
        case .multireddit(let owner, _): return owner == nil
        case .popular, .all, .subreddits: return false
        }
    }

    /// Copy for that case.
    public static let signInMessage = "Sign in for this feed"

    /// Parses the free-text field.
    public static func parse(_ raw: String) -> WidgetFeedSource? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // A pasted URL is reduced to its path first, so every rule
        // below applies equally to typed and pasted input.
        if let range = text.range(of: "reddit.com/", options: .caseInsensitive) {
            text = String(text[range.upperBound...])
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let lowered = text.lowercased()
        // Built-in feeds, typed directly.
        if lowered == "home" { return .home }
        if lowered == "popular" || lowered == "r/popular" { return .popular }
        if lowered == "all" || lowered == "r/all" { return .all }

        // Another user's multireddit: user/foo/m/bar or u/foo/m/bar.
        let parts = text.split(separator: "/").map(String.init)
        if parts.count >= 4, parts[0].lowercased() == "user" || parts[0].lowercased() == "u",
           parts[2].lowercased() == "m" {
            return .multireddit(owner: parts[1], name: parts[3])
        }
        // Your own: me/m/bar.
        if parts.count >= 3, parts[0].lowercased() == "me", parts[1].lowercased() == "m" {
            return .multireddit(owner: nil, name: parts[2])
        }
        // Your own, short form: m/bar.
        if parts.count >= 2, parts[0].lowercased() == "m" {
            return .multireddit(owner: nil, name: parts[1])
        }

        // Subreddits.
        //
        // Order matters here: stripping the leading "r/" before
        // normalising separators would turn "r/soccer r/nba" into
        // parts ["r", "soccer r", "nba"], losing the second name. The
        // multi-token forms have to be recognised first.
        var body = text
        let hasSeparators = text.contains(" ") || text.contains(",") || text.contains("+")
        if !hasSeparators, parts.count >= 2, parts[0].lowercased() == "r" {
            // Single name, so a trailing sort segment on a pasted URL
            // ("r/soccer/top") is not part of the name.
            body = parts[1]
        }
        // "soccer+nba", "soccer, nba" and "r/soccer r/nba" are all the
        // same combined listing, so every separator is normalised.
        let names = body
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "+", with: " ")
            .split(separator: " ")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
            .map { name -> String in
                // A multi-token form repeats the r/ prefix per name.
                if name.lowercased().hasPrefix("r/") { return String(name.dropFirst(2)) }
                return name
            }
            .filter { !$0.isEmpty }
        guard !names.isEmpty else { return nil }
        return .subreddits(names)
    }
}
