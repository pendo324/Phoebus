import Foundation

/// Apollo's display capitalization for subreddit names.
///
/// Reddit's API returns a subreddit's name in whatever case the URL
/// used, which in listings is effectively lowercase: `pics`, `funny`,
/// `technology`. Apollo's feed rows show `Pics`, `Funny`,
/// `Technology`, and `NBA`, `AskReddit`, `TodayILearned`.
///
/// This cannot be a capitalization rule: Apollo ships a lookup table of
/// about 5,500 subreddit names with their canonical mixed-case display
/// form, and most entries differ from `String.capitalized`:
///
///     nba               -> NBA                (not "Nba")
///     askreddit         -> AskReddit          (not "Askreddit")
///     todayilearned     -> TodayILearned
///     explainlikeimfive -> ExplainLikeImFive
///     1200isjerky       -> 1200isJerky        (lowercase "is"!)
///     1200isplenty      -> 1200IsPlenty       (but uppercase here)
///
/// The last two are the clearest proof: two sibling subreddits whose
/// names differ only in the case of the same word. Only a table knows.
///
/// The table is Apollo's own data file, converted from plist to JSON
/// and stripped of its 5 identity entries (a mapping of `x -> x` does
/// nothing). It is the community's own spelling of community names,
/// not artwork or proprietary logic.
public enum SubredditCapitalization {
    /// Lowercased name -> display name.
    ///
    /// Loaded once. The table is ~150KB of JSON, which is why it is
    /// not an inline Swift literal: a dictionary literal that size
    /// makes the type checker crawl.
    private static let mapping: [String: String] = {
        guard let url = Bundle.module.url(forResource: "SubredditCapitalization",
                                          withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return decoded
    }()

    /// The display spelling of `name`, or `name` unchanged.
    ///
    /// Returns the INPUT unchanged when there is no entry, rather than
    /// falling back to `.capitalized`. A guess would be wrong for
    /// every name the table deliberately leaves alone, and wrong in a
    /// way that looks like a typo: `r/rust` is not `R/Rust`.
    ///
    /// Also preserves any casing the caller already has: if Reddit
    /// hands back `PixelArt` from a subreddit endpoint, the lookup
    /// misses on the exact string, so the mixed-case original is kept.
    public static func display(_ name: String) -> String {
        guard !name.isEmpty else { return name }
        let key = name.lowercased()
        // A name that already has non-lowercase characters came from a
        // source that knows its own case; only normalise it if the
        // table has an entry, which is the authoritative spelling.
        return mapping[key] ?? name
    }

    /// How many entries loaded, so the resource's presence can be
    /// asserted rather than assumed. A missing resource degrades to an
    /// empty table and silently un-capitalizes every row.
    public static var entryCount: Int { mapping.count }
}
