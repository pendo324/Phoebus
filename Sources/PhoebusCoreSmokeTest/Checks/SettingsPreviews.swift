import Foundation
import PhoebusCore

// MARK: - Settings preview samples

// The sample post and thread the Posts, Comments and Thread Colours previews
// draw with the real rows. Built from Reddit-shaped JSON through the live
// decoders, with ages relative to a fixed `now`.

@MainActor func checkSettingsPreviewSampleDecodesLikeALiveListing() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let image = URL(fileURLWithPath: "/tmp/sample-preview.png")
    let post = SettingsPreviewSample.post(imageURL: image, now: now)

    check("the sample post is a self post in the sample subreddit",
          post.isSelf && post.subreddit == SettingsPreviewSample.subreddit && post.name == SettingsPreviewSample.postFullname)
    check("the sample post carries a score, a comment count and an age of three hours",
          post.score == 842 && post.numComments == 87 && now.timeIntervalSince(post.created) == 3 * 3600)
    check("the sample post has post flair, user flair and awards",
          post.linkFlairText == "Question" && post.authorFlairText == "Baker" && post.totalAwardsReceived == 3)
    check("the sample post's flair colours are valid hex, so Color Flairs shows",
          RedditFlairColor.validHex(from: post.linkFlairBackgroundColor) != nil
            && RedditFlairColor.validHex(from: post.authorFlairBackgroundColor) != nil)
    check("the sample post has an open two-option poll",
          post.pollData?.options.count == 2 && post.pollData?.hasEnded == false)
    check("the sample post's picture is the local file, as its text-post thumbnail",
          post.derivedSelfPostThumbnailURL == image)
    check("the sample post has no remote image to fetch",
          post.thumbnail == "self" && post.previewImageURL(displayWidth: 430) == nil && post.url == nil)
    check("the sample post is not NSFW, spoilered, stickied or a crosspost",
          !post.over18 && !post.spoiler && !post.stickied && !post.isCrosspost)
}

@MainActor func checkSettingsPreviewSampleThreadFollowsTheCollapseSettings() async throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let roots = SettingsPreviewSample.thread(now: now)
    let all = roots.flatMap { $0.flattenedAll() }

    check("the sample thread is five comments on one chain below two roots",
          all.count == 5 && roots.count == 2 && all.map(\.depth) == [0, 0, 1, 2, 3])
    check("the sample comments have distinct ids and fullnames",
          Set(all.map(\.id)).count == 5 && Set(all.map(\.comment.name)).count == 5)
    check("nothing starts collapsed under the default settings",
          all.allSatisfy { !$0.isCollapsed })
    check("the new comment is one of the thread's",
          SettingsPreviewSample.newCommentIDs.isSubset(of: Set(all.map(\.id))))
    check("the thread has a pinned AutoModerator comment, a new account, a followed user and the account's own",
          all[0].comment.author == "AutoModerator" && all[0].comment.stickied
            && all[1].comment.author == SettingsPreviewSample.newAccountUsername
            && SettingsPreviewSample.followedUsernames.contains(all[2].comment.author.lowercased())
            && all[3].comment.author == SettingsPreviewSample.ownUsername)
    check("the followed user's reply is edited and flaired",
          all[2].comment.edited?.isEdited == true && all[2].comment.authorFlairText == "Fan")
    check("the last comment is Reddit's removed placeholder, and the archive holds its copy",
          DeletedCommentsClassifier.bodyLooksDeletedOrRemoved(all[4].comment.body)
            && SettingsPreviewSample.archivedComments[all[4].comment.name]?.reason == .moderatorRemoved
            && all[4].comment.name == SettingsPreviewSample.removedCommentFullname)
    check("the comments' ages are offsets from now",
          all.map { Int(now.timeIntervalSince($0.comment.created) / 60) } == [175, 40, 25, 12, 6])

    check("Collapse AutoModerator folds the first comment",
          SettingsPreviewSample.thread(collapseAutoModerator: true, now: now).first?.isCollapsed == true)
    check("Collapse Pinned Comments folds the first comment",
          SettingsPreviewSample.thread(collapsePinned: true, now: now).first?.isCollapsed == true)
    let folded = SettingsPreviewSample.thread(autoCollapseChildren: true, now: now)
    check("Auto Collapse Child Comments folds the reply to a root and hides what is under it",
          folded.flatMap { $0.visibleFlattened() }.map(\.depth) == [0, 0, 1]
            && folded[1].children.first?.isCollapsed == true)
}

@MainActor func checkSettingsPreviewSampleStandsInForTheAccount() async throws {
    var settings = GeneralSettings.default
    settings.highlightOwnUsername = true
    settings.highlightFollowedUsers = true
    func highlight(_ author: String) -> AuthorHighlight {
        AuthorHighlight.sample(author: author, distinguished: nil, settings: settings)
    }
    check("the sample's own comment is highlighted as the signed-in user's",
          highlight(SettingsPreviewSample.ownUsername) == .own)
    check("the sample's followed user is highlighted as followed",
          highlight("Sample_Pal") == .followed)
    check("any other sample commenter is not highlighted",
          highlight(SettingsPreviewSample.newAccountUsername) == .none)
    settings.highlightOwnUsername = false
    settings.highlightFollowedUsers = false
    check("switching the highlights off clears them",
          highlight(SettingsPreviewSample.ownUsername) == .none && highlight("sample_pal") == .none)

    let now = Date(timeIntervalSince1970: 1_800_000_000)
    check("only the sample's new commenter is a new account",
          AccountAgeCache.isNewAccount(createdAt: SettingsPreviewSample.accountCreated(for: SettingsPreviewSample.newAccountUsername, now: now), referenceDate: now)
            && !AccountAgeCache.isNewAccount(createdAt: SettingsPreviewSample.accountCreated(for: "sample_pal", now: now), referenceDate: now))
}
