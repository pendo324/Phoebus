import Foundation

/// "Hide Post Scores" and "Hide Comment Scores": the numbers go, the vote
/// arrows and their voted colours stay. Phoebus-only; Apollo and Reborn
/// have neither, so there is no stock key.
public struct VoteCountSettings: Codable, Equatable, Sendable {
    public var hidePostScores: Bool
    public var hideCommentScores: Bool

    public static let `default` = VoteCountSettings()

    public init(hidePostScores: Bool = false, hideCommentScores: Bool = false) {
        self.hidePostScores = hidePostScores
        self.hideCommentScores = hideCommentScores
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hidePostScores = (try? container.decodeIfPresent(Bool.self, forKey: .hidePostScores)) ?? false
        hideCommentScores = (try? container.decodeIfPresent(Bool.self, forKey: .hideCommentScores)) ?? false
    }

    /// A post's score as rows draw it ("10.9K"), nil while hidden.
    public func postScoreText(_ score: Int) -> String? {
        hidePostScores ? nil : score.apolloAbbreviated
    }

    /// A comment's score as its header draws it, nil while hidden. Reddit's
    /// own hidden score (a new comment's) is Apollo's em dash.
    public func commentScoreText(_ score: Int, scoreHidden: Bool) -> String? {
        guard !hideCommentScores else { return nil }
        return scoreHidden ? "\u{2014}" : score.apolloAbbreviated
    }

    /// The approximate upvote/downvote totals are worked back from the score,
    /// so they hide with it; the "% Upvoted" alone doesn't reveal it and stays.
    public var showsPostVoteEstimate: Bool { !hidePostScores }
}

public enum VoteCountStore {
    public static let storage = SettingsStore<VoteCountSettings>(key: "com.pendo324.Phoebus.voteCountSettings") { .default }

    public static func load() -> VoteCountSettings { storage.load() }

    public static func save(_ settings: VoteCountSettings) { storage.save(settings) }
}

extension VoteCountSettings: StoredSettingsModel {
    public static var store: SettingsStore<VoteCountSettings> { VoteCountStore.storage }
}
