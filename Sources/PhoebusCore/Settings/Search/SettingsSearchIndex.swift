import Foundation

/// One searchable settings row, mirroring Apollo-Reborn's settings search.
/// `screen` identifies the destination and `rowTitle` names the row to
/// scroll to and flash once there.
public struct SettingsSearchEntry: Sendable, Equatable, Identifiable {
    public let title: String
    public let breadcrumb: String
    public let screen: SettingsSearchScreen
    /// The row to highlight once `screen` is showing. `nil` when the entry IS the screen.
    public let rowTitle: String?

    public var id: String { "\(screen.rawValue)|\(breadcrumb)|\(title)" }

    public init(title: String, breadcrumb: String, screen: SettingsSearchScreen, rowTitle: String? = nil) {
        self.title = title
        self.breadcrumb = breadcrumb
        self.screen = screen
        self.rowTitle = rowTitle
    }
}

/// Every settings screen a search result can land on.
public enum SettingsSearchScreen: String, Sendable, CaseIterable, Codable {
    case settingsRoot
    case gestures
    case filters
    case markRead
    case appIcon
    case appearance
    case theme
    case about
    case notifications
    case security
    case portraitLock
    case accounts
    case commentsTheme
    case wallpapers
    case themeGallery
}

/// Settings search: matching and ranking, ported from Apollo-Reborn's
/// matcher with its score constants reproduced exactly.
public enum SettingsSearch {
    // MARK: Normalisation

    /// Folds diacritics and reduces every run of non-alphanumerics to a
    /// single space, so hyphens/ampersands/punctuation in settings names
    /// don't need to be typed exactly.
    public static func normalized(_ string: String) -> String {
        let folded = string.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        var result = ""
        var lastWasSpace = true
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
                lastWasSpace = false
            } else if !lastWasSpace {
                result.append(" ")
                lastWasSpace = true
            }
        }
        if result.hasSuffix(" ") { result.removeLast() }
        return result
    }

    static func words(_ normalized: String) -> [String] {
        normalized.isEmpty ? [] : normalized.components(separatedBy: " ")
    }

    // MARK: Fuzzy matching

    /// Bounded edit distance, abandoning a row once its cheapest
    /// candidate exceeds `limit`. Uses Damerau-Levenshtein (adjacent
    /// transpositions cost 1, not 2 as in upstream's plain Levenshtein),
    /// since transposition is the most common typo and upstream only
    /// forgives one edit.
    public static func editDistanceAtMost(_ a: [Character], _ b: [Character], limit: Int) -> Int {
        if a.count > b.count + limit || b.count > a.count + limit { return limit + 1 }
        guard !a.isEmpty else { return min(b.count, limit + 1) }
        guard !b.isEmpty else { return min(a.count, limit + 1) }

        // Three rows, because a transposition looks back two.
        var beforePrevious = [Int](repeating: 0, count: b.count + 1)
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            var rowMin = current[0]
            let ac = a[i - 1]
            for j in 1...b.count {
                let substitution = previous[j - 1] + (ac == b[j - 1] ? 0 : 1)
                var best = min(min(previous[j] + 1, current[j - 1] + 1), substitution)
                if i > 1, j > 1, ac == b[j - 2], a[i - 2] == b[j - 1] {
                    best = min(best, beforePrevious[j - 2] + 1)
                }
                current[j] = best
                rowMin = min(rowMin, best)
            }
            if rowMin > limit { return limit + 1 }
            beforePrevious = previous
            previous = current
        }
        return previous[b.count]
    }

    /// Fuzzy token match: only words of 4+ characters are eligible, and
    /// only one typo is forgiven.
    public static func tokenFuzzyMatchesWord(_ token: String, _ word: String) -> Bool {
        guard token.count >= 4, word.count >= 4 else { return false }
        if word.hasPrefix(token) || token.hasPrefix(word) { return true }
        return editDistanceAtMost(Array(token), Array(word), limit: 1) <= 1
    }

    // MARK: Scoring

    /// Scoring function, constants included. Returns a negative score for
    /// "no match".
    public static func score(_ entry: SettingsSearchEntry, query: String) -> Int {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let title = entry.title
        var score = -1

        if title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil {
            score = 100
        } else if let inTitle = title.range(of: query, options: options) {
            // A word-boundary prefix ranks above a mid-word hit, so "read"
            // scores higher in "Mark Read" than inside "Thread".
            let before = title[title.index(before: inTitle.lowerBound)]
            let isAlnum = before.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
            score = isAlnum ? 55 : 80
        } else if entry.breadcrumb.range(of: query, options: options) != nil {
            score = 25
        } else {
            // Multi-word query: every token must land somewhere in title+breadcrumb.
            let tokens = query.components(separatedBy: .whitespaces)
            let haystack = "\(title) \(entry.breadcrumb)"
            var allLiteral = tokens.count >= 2
            for token in tokens where !token.isEmpty {
                if haystack.range(of: token, options: options) == nil {
                    allLiteral = false
                    break
                }
            }
            if allLiteral {
                score = 40
            } else {
                let normalizedQuery = normalized(query)
                let queryWords = words(normalizedQuery)
                let haystackWords = words(normalized(haystack))

                // Initialisms matter here: "pip" finds Picture-in-Picture,
                // "api" finds Accounts & API Keys.
                var initials = ""
                for word in words(normalized(title)) where !word.isEmpty {
                    initials.append(word.first!)
                }
                if normalizedQuery.count >= 2 && initials.hasPrefix(normalizedQuery) {
                    score = 48
                } else {
                    var allFuzzy = !queryWords.isEmpty
                    for token in queryWords {
                        var tokenMatched = false
                        for word in haystackWords where tokenFuzzyMatchesWord(token, word) {
                            tokenMatched = true
                            break
                        }
                        if !tokenMatched {
                            allFuzzy = false
                            break
                        }
                    }
                    if !allFuzzy { return -1 }
                    score = 32
                }
            }
        }

        // Tiebreak: prefer screens over leaf rows of the same name.
        if entry.rowTitle == nil { score += 1 }
        return score
    }

    /// Ranked results for a query, best first: score descending, with
    /// equal scores kept in index order (`sort(by:)` isn't stable, hence
    /// the manual offset tiebreak).
    public static func results(for query: String, in entries: [SettingsSearchEntry] = index) -> [SettingsSearchEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var scored: [(offset: Int, entry: SettingsSearchEntry, score: Int)] = []
        for (offset, entry) in entries.enumerated() {
            let value = score(entry, query: trimmed)
            if value > 0 { scored.append((offset, entry, value)) }
        }
        scored.sort { a, b in
            a.score == b.score ? a.offset < b.offset : a.score > b.score
        }
        return scored.map { $0.entry }
    }
}
