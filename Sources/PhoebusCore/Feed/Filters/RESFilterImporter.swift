import Foundation

/// Imports a Reddit Enhancement Suite (RES) "filteReddit" subreddit-filter
/// export. A base Apollo feature, not a Reborn addition.
///
/// Apollo's onboarding tells the user to run, in their desktop browser's RES
/// developer console:
///
///     RESStorage get RESoptions.filteReddit
///
/// and paste the JSON into Apollo via the clipboard, long-pressing the "Add
/// Subreddit" button on the Filters screen.
///
/// The JSON shape follows RES's module option schema (`filteReddit` in
/// github.com/honestbleeps/Reddit-Enhancement-Suite): each top-level key is
/// an option ID whose `value` field holds that option's setting. The three
/// options used:
///
///   - `subreddits.value`: `[{ subreddit: String }]`
///   - `keywords.value`: `[{ keyword: String, applyTo: String,
///     subreddits: [String], unlessKeyword: String }]`
///   - `domains.value`: `[{ keyword: String, applyTo: String,
///     subreddits: [String] }]` (RES reuses the `keyword` field name
///     for the domain string itself)
///
/// Apollo's filter model has no per-subreddit "applyTo" scoping, so
/// `applyTo` and per-filter `subreddits` scoping are read but dropped on
/// import.
public enum RESFilterImporter {
    public enum ImportError: Error, Equatable {
        /// Matches Apollo's message: "you currently have no
        /// text on your clipboard for Apollo to import".
        case emptyClipboard
        /// Matches Apollo's message: "the format is either
        /// invalid or there are no subreddits contained in the text".
        case invalidOrEmpty
    }

    /// Parses a `RESStorage get RESoptions.filteReddit` JSON blob and
    /// returns the equivalent `ContentFilter`s Apollo can represent.
    public static func parse(_ clipboardText: String) -> Result<[ContentFilter], ImportError> {
        let trimmed = clipboardText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.emptyClipboard) }
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.invalidOrEmpty)
        }

        var filters: [ContentFilter] = []

        if let subredditsOpt = json["subreddits"] as? [String: Any],
           let rows = subredditsOpt["value"] as? [[String: Any]] {
            for row in rows {
                if let name = (row["subreddit"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                    filters.append(ContentFilter(kind: .subreddit, value: name))
                }
            }
        }

        if let keywordsOpt = json["keywords"] as? [String: Any],
           let rows = keywordsOpt["value"] as? [[String: Any]] {
            for row in rows {
                if let word = (row["keyword"] as? String)?.trimmingCharacters(in: .whitespaces), !word.isEmpty {
                    filters.append(ContentFilter(kind: .keyword, value: word))
                }
            }
        }

        if let domainsOpt = json["domains"] as? [String: Any],
           let rows = domainsOpt["value"] as? [[String: Any]] {
            for row in rows {
                if let domain = (row["keyword"] as? String)?.trimmingCharacters(in: .whitespaces), !domain.isEmpty {
                    filters.append(ContentFilter(kind: .domain, value: domain))
                }
            }
        }

        guard !filters.isEmpty else { return .failure(.invalidOrEmpty) }
        return .success(filters)
    }
}
