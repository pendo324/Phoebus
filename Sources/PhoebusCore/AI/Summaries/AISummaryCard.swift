import Foundation

/// The inline AI summary cards Apollo shows in a thread: one under the post
/// and one above the comments, each expandable. Strings, prompts, token
/// budgets and thresholds match Apollo-Reborn.
public enum AISummaryCard {
    /// The post card's three titles. The title depends on what was summarised:
    /// a self-post with a body gets "Post summary", a link post "Link summary",
    /// and a self-post that shares a link gets both.
    public enum Kind: Equatable, Sendable {
        case post
        case link
        case postAndLink
        case discussion

        public var title: String {
            switch self {
            case .post: return "Post summary"
            case .link: return "Link summary"
            case .postAndLink: return "Post/Link summary"
            case .discussion: return "Discussion so far"
            }
        }

        var isPost: Bool { self != .discussion }
    }

    /// The card's lifecycle.
    public enum State: Equatable, Sendable {
        /// Nothing to show; the card is absent.
        case none
        /// Waiting for a tap, because Tap to Summarize is on.
        case tapToSummarize
        case loading
        case ready(String)
        case error(String)
        /// Terminal: a tapped link with no usable prose.
        case empty
    }

    /// The collapsed subtitle that follows the title, after "  ·  ".
    /// `nil` when the card shows a chevron instead.
    public static func collapsedSubtitle(for state: State) -> String? {
        switch state {
        case .empty: return "Nothing to summarize"
        case .loading: return "Summarizing…"
        case .tapToSummarize: return "Tap to summarize"
        case .none, .ready, .error: return nil
        }
    }

    /// Whether the card draws its trailing disclosure chevron: only when there
    /// is something to expand or collapse (an expanded card, or a collapsed
    /// ready/error card). Collapsed idle/loading cards use their subtitle instead.
    public static func showsChevron(state: State, expanded: Bool) -> Bool {
        if expanded { return true }
        switch state {
        case .ready, .error: return true
        default: return false
        }
    }

    /// Collapsed idle/loading/empty cards clamp to one line so a long title plus
    /// subtitle cannot wrap. Ready/error collapsed cards keep their chevron.
    public static func clampsToOneLine(state: State, expanded: Bool) -> Bool {
        guard !expanded else { return false }
        switch state {
        case .ready, .error: return false
        default: return true
        }
    }

    /// The expanded body, including the placeholder text each
    /// non-ready state substitutes.
    public static func expandedBody(kind: Kind, state: State) -> String {
        switch state {
        case .tapToSummarize:
            return kind.isPost ? "Tap to summarize this post." : "Tap to summarize the discussion."
        case .loading:
            return kind.isPost ? "Summarizing…" : "Summarizing discussion…"
        case .error(let message):
            return message.isEmpty ? "Couldn't generate this summary." : message
        case .ready(let summary):
            return summary
        case .none, .empty:
            return ""
        }
    }

    /// The trust caption under a ready summary, so it isn't mistaken for the
    /// author's own words; the provider attribution says whether content stayed
    /// on-device or went to the configured cloud service.
    /// `sourceCount` is the number of comments the discussion summary read; it is
    /// 0 for a post card and omitted when zero.
    ///
    /// The caption always ends "· may be inaccurate"; the comment card inserts
    /// "· Based on N representative comments" before it.
    public static func attribution(for provider: AIProvider, sourceCount: Int = 0) -> String {
        let origin = "AI-generated " + providerPhrase(provider)
        if sourceCount > 0 {
            return "\(origin) · Based on \(sourceCount) representative \(sourceCount == 1 ? "comment" : "comments") · may be inaccurate"
        }
        return "\(origin) · may be inaccurate"
    }

    /// Provider attribution phrases. These are prepositional phrases, not
    /// provider names: "on device" has no preposition at all.
    private static func providerPhrase(_ provider: AIProvider) -> String {
        switch provider {
        case .onDevice: return "on device"
        case .gemini: return "with Gemini"
        case .openRouter: return "via OpenRouter"
        case .custom: return "via Custom Provider"
        }
    }
}

/// The per-detail prompts and budgets, kept exact: the prompts are tuned to
/// produce a specific length and the token budgets bound it.
public enum AISummaryPrompts {
    /// Post-summary instructions per detail level.
    public static func postInstructions(_ detail: AISummaryDetail) -> String {
        switch detail {
        case .brief:
            return "Summarize this Reddit post in 1-2 concise plain sentences. Give only the essential point and what the poster asks, claims, or shares. No heading, Markdown, or added facts."
        case .inDepth:
            return "Summarize this Reddit post in 3-5 focused plain sentences. Explain the main point, the poster\u{2019}s reasoning or context, and what they ask, claim, or share. Include useful supporting details, but stay clearly shorter than the post. No heading, Markdown, or added facts."
        case .balanced:
            return "Summarize this Reddit post in 2 short plain sentences. State the main point and what the poster asks, claims, or shares. No heading, Markdown, or added facts."
        }
    }

    /// Comment-summary instructions per detail level. All three say "Summarize
    /// commenters, not the post" so the discussion card does not restate the post.
    public static func commentInstructions(_ detail: AISummaryDetail) -> String {
        switch detail {
        case .brief:
            return "Summarize these Reddit comments in 1-2 concise plain sentences. Give the overall reaction and the most important takeaway. Summarize commenters, not the post. No heading, Markdown, or added facts."
        case .inDepth:
            return "Summarize these Reddit comments in 4-5 focused plain sentences. Explain the consensus, useful supporting details, notable alternatives, and an important disagreement when present. Summarize commenters, not the post, and stay clearly shorter than the discussion. No heading, Markdown, or added facts."
        case .balanced:
            return "Summarize these Reddit comments in 2-3 short plain sentences. Cover the consensus, useful details, and one notable disagreement if present. Summarize commenters, not the post. No heading, Markdown, or added facts."
        }
    }

    /// Linked-article instructions per detail level.
    public static func articleInstructions(_ detail: AISummaryDetail) -> String {
        switch detail {
        case .brief:
            return "Summarize this linked article in 1-2 concise plain sentences. Give the main topic and most important reported fact or conclusion. Summarize the article itself, not website navigation or ads. No heading, Markdown, or added facts."
        case .inDepth:
            return "Summarize this linked article in 4-5 focused plain sentences. Explain the main topic, key facts, supporting context, and important conclusions or implications stated by the source. Stay clearly shorter than the article. Ignore website navigation and ads. No heading, Markdown, or added facts."
        case .balanced:
            return "Summarize this linked news article in 2-3 short plain sentences. State the main topic and the key facts or points it reports. Summarize the article itself, not website navigation or ads. No heading, Markdown, or added facts."
        }
    }

    /// Post-and-linked-article instructions per detail level.
    public static func postAndLinkInstructions(_ detail: AISummaryDetail) -> String {
        switch detail {
        case .brief:
            return "You are given a Reddit post and the article it links to. Summarize both together in 2 concise plain sentences: the post\u{2019}s point and the article\u{2019}s essential fact or conclusion. No heading, Markdown, or added facts."
        case .inDepth:
            return "You are given a Reddit post and the article it links to. Summarize both together in 4-6 focused plain sentences. Explain the post\u{2019}s point, the article\u{2019}s key facts and context, and how they relate, while staying clearly shorter than the sources. No heading, Markdown, or added facts."
        case .balanced:
            return "You are given a Reddit post and the article it links to. Summarize both together in 3-4 short plain sentences: the post\u{2019}s point and the article\u{2019}s key facts. No heading, Markdown, or added facts."
        }
    }

    public static func articleResponseTokens(_ detail: AISummaryDetail) -> Int {
        switch detail {
        case .brief: return 80
        case .inDepth: return 200
        case .balanced: return 110
        }
    }

    public static func postAndLinkResponseTokens(_ detail: AISummaryDetail) -> Int {
        switch detail {
        case .brief: return 100
        case .inDepth: return 240
        case .balanced: return 150
        }
    }

    /// Max post character budget per detail level (how much of the post is sent).
    public static func maxPostChars(_ detail: AISummaryDetail) -> Int {
        switch detail {
        case .brief: return 1000
        case .inDepth: return 2200
        case .balanced: return 1400
        }
    }

    /// Post response token budget per detail level.
    public static func postResponseTokens(_ detail: AISummaryDetail) -> Int {
        switch detail {
        case .brief: return 64
        case .inDepth: return 180
        case .balanced: return 80
        }
    }

    /// Comment response token budget per detail level (Balanced is 110, not 80).
    public static func commentResponseTokens(_ detail: AISummaryDetail) -> Int {
        switch detail {
        case .brief: return 70
        case .inDepth: return 200
        case .balanced: return 110
        }
    }

    /// Sanitized word threshold: out-of-range or non-multiple-of-50 values fall
    /// back to 150 rather than being clamped.
    public static func sanitizedWordThreshold(_ stored: Int) -> Int {
        guard stored >= 50, stored <= 300, stored % 50 == 0 else { return 150 }
        return stored
    }

    /// Whether a text post is long enough to summarise. The threshold applies to
    /// text posts only; linked articles are always eligible.
    public static func postMeetsThreshold(wordCount: Int, threshold: Int) -> Bool {
        wordCount >= sanitizedWordThreshold(threshold)
    }
}
