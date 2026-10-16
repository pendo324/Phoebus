import Foundation

/// Reddit's current awards, which only a web session reaches (the OAuth API
/// carries none of them). Without a session, or with "Show Awards" off, a
/// thread makes no award request at all.
extension RedditRepository {
    /// Asks for the thread's award badges once per opened thread: one request
    /// for the whole comment tree, never one per comment. Failures leave the
    /// rows as they were.
    public func loadThreadAwards(subreddit: String, postID: String, sort: String, force: Bool = false) async {
        guard GeneralSettingsStore.load().showAwards, let session = await webFeatureSession(),
              let url = AwardWebService.threadFragmentURL(subreddit: subreddit, postID: postID, sort: sort)
        else { return }
        let thread = Self.awardThreadKey(postID, sort: sort)
        guard await AwardStore.shared.beginLoad(thread: thread, force: force) else { return }
        guard let found = try? await AwardWebService.fetchFragment(url: url, session: session) else {
            await AwardStore.shared.failLoad(thread: thread)
            return
        }
        await AwardStore.shared.finishLoad(thread: thread, found: found, replacing: true)
    }

    /// The badges of the comments a "more comments" stub revealed, from
    /// Shreddit's more-comments partial.
    public func loadMoreAwards(subreddit: String, postID: String, sort: String,
                               position: AwardWebService.MorePosition) async {
        guard GeneralSettingsStore.load().showAwards, let session = await webFeatureSession(),
              let url = AwardWebService.moreCommentsURL(subreddit: subreddit, postID: postID, sort: sort,
                                                        position: position),
              let found = try? await AwardWebService.fetchFragment(url: url, session: session)
        else { return }
        await AwardStore.shared.merge(found, thread: Self.awardThreadKey(postID, sort: sort))
    }

    /// A thread is listed per sort: another sort brings other comments in.
    static func awardThreadKey(_ postID: String, sort: String) -> String {
        (postID.hasPrefix("t3_") ? String(postID.dropFirst(3)) : postID) + "|" + (AwardWebService.shredditSort(sort) ?? "")
    }

    /// The award dialog of a post or comment: the catalogue, the user's Gold
    /// and the leaderboard link.
    public func awardDialog(thingID: String) async throws -> AwardDialog {
        guard let session = await webFeatureSession() else { throw AwardError.requiresWebSession }
        return try await AwardWebService.fetchDialog(thingID: thingID, session: session)
    }

    /// The breakdown of `dialog`'s thing.
    public func awardLeaderboard(dialog: AwardDialog) async throws -> AwardLeaderboard {
        guard let session = await webFeatureSession() else { throw AwardError.requiresWebSession }
        guard let url = dialog.leaderboardURL else { throw AwardError.unreadable }
        return try await AwardWebService.fetchLeaderboard(url: url, session: session)
    }

    /// Gives a free award, or a paid one out of the user's own Gold. Gold is
    /// never bought here.
    public func giveAward(thingID: String, awardID: String, isAnonymous: Bool) async throws -> AwardOrderResult {
        guard let session = await webFeatureSession() else { throw AwardError.requiresWebSession }
        return try await AwardWebService.giveAward(thingID: thingID, awardID: awardID,
                                                   isAnonymous: isAnonymous, session: session)
    }
}
