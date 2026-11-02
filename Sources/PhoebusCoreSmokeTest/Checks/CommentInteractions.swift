import Foundation
import PhoebusCore

// MARK: - Deleted and removed comments take no writes

@MainActor func checkCommentInteractionPolicy() async throws {
    typealias P = CommentInteractionPolicy
    func comment(author: String = "someone", body: String = "a real reply", locked: Bool = false) -> RedditComment {
        let json = """
        {"id":"c1","name":"t1_c1","author":"\(author)","body":"\(body)","score":4,"created_utc":0,
         "parent_id":"t3_p1","link_id":"t3_p1","saved":false,"score_hidden":false,"stickied":false,"locked":\(locked)}
        """
        return try! JSONDecoder.reddit.decode(RedditComment.self, from: json.data(using: .utf8)!)
    }
    let writes: [P.Interaction] = [.vote, .reply, .quote, .save, .award, .report, .shareAsImage, .moderate]
    let reads: [P.Interaction] = [.share, .copyLink, .collapse, .remindMe, .muteNotifications]
    let rowMenu = ["upvote", "downvote", "reply", "quote", "save", "edit", "delete", "vote-insights", "share", "copy-link",
                   "copy-text", "share-image", "copy-username", "tag-user", "translate", "award", "report", "remind-me",
                   "mute-notifications"]
    let moderatorMenu = ["mod-approve", "mod-remove", "mod-spam", "mod-distinguish", "mod-sticky", "mod-notes"]

    let live = P(comment: comment())
    check("a live comment is live and offers every write", live.status == .live && writes.allSatisfy { live.allows($0) })
    check("a live comment's text, links and username actions are offered",
          [.copyText, .copyUsername, .tagUser, .openProfile, .translate, .modNotes].allSatisfy { live.allows($0) } && reads.allSatisfy { live.allows($0) })
    check("a live comment of someone else offers no Edit, Delete or Vote Insights",
          ![.edit, .delete, .voteInsights].contains { live.allows($0) })
    let own = P(comment: comment(), isOwn: true)
    check("your own live comment offers Edit, Delete and Vote Insights", [.edit, .delete, .voteInsights].allSatisfy { own.allows($0) })
    check("a live comment's menu loses only the author-only rows", rowMenu.filter(live.allowsMenuItem) == rowMenu.filter { !["edit", "delete", "vote-insights"].contains($0) })
    check("a live comment's moderator menu is whole", moderatorMenu.filter(live.allowsMenuItem) == moderatorMenu)
    check("a live comment's swipes are unchanged",
          live.restricting(.commentsDefault) == .commentsDefault && live.restricting(.profileCommentsDefault) == .profileCommentsDefault
          && SwipeAction.allCases.allSatisfy { live.allows(swipe: $0) })

    // A locked comment keeps today's actions; Reddit's own refusal shows as an error.
    let locked = P(comment: comment(locked: true))
    check("a locked live comment keeps every action it had", locked.isLive && (writes + reads).allSatisfy { locked.allows($0) })

    // Reddit's placeholders.
    let userDeleted = P(comment: comment(author: "[deleted]", body: "[deleted]"))
    check("author [deleted] with body [deleted] is deleted by the user", userDeleted.status == .userDeleted)
    let removed = P(comment: comment(author: "[deleted]", body: "[removed]"))
    check("body [removed] is removed", removed.status == .removed)
    for (name, policy) in [("deleted", userDeleted), ("removed", removed)] {
        check("a \(name) comment takes no vote, reply, quote, save, award, report, image or moderator action", !writes.contains { policy.allows($0) })
        check("a \(name) comment keeps collapse, share, copy link, remind me and mute", reads.allSatisfy { policy.allows($0) })
        check("a \(name) comment has no text or username to copy, translate, tag or open",
              ![.copyText, .translate, .copyUsername, .tagUser, .openProfile, .modNotes].contains { policy.allows($0) })
        check("a \(name) comment's menu is only share, copy link, remind me and mute",
              rowMenu.filter(policy.allowsMenuItem) == ["share", "copy-link", "remind-me", "mute-notifications"])
        check("a \(name) comment's moderator menu is empty", moderatorMenu.filter(policy.allowsMenuItem).isEmpty)
        let swipes = policy.restricting(.commentsDefault)
        check("a \(name) comment's default swipes reveal only Collapse Top",
              swipes == SwipeActionSettings(leftShort: .none, leftLong: .none, rightShort: .collapseTop, rightLong: .none))
        check("a \(name) comment's profile swipes (Save, Reply, votes) all reveal nothing",
              policy.restricting(.profileCommentsDefault) == SwipeActionSettings(leftShort: .none, leftLong: .none, rightShort: .none, rightLong: .none))
        check("a \(name) comment allows the swipes that write nothing",
              [.collapse, .collapseTop, .hide, .parentComment, .share, .subreddit, .markRead, .none].allSatisfy { policy.allows(swipe: $0) }
              && ![.upvote, .downvote, .save, .reply, .author, .selectText].contains { policy.allows(swipe: $0) })
    }

    // Wording an archive uses is recovery's business, not a reason to lock a live comment.
    check("a live comment that only says removed keeps its actions", P(comment: comment(body: "removed")).isLive)
    check("an empty body is not Reddit's placeholder", P(author: "x", body: "").isLive)
    check("Reddit's placeholders are matched exactly",
          DeletedCommentsClassifier.bodyIsRedditPlaceholder("[deleted]") && DeletedCommentsClassifier.bodyIsRedditPlaceholder(" [Removed] ")
          && DeletedCommentsClassifier.bodyIsRedditPlaceholder("[ Removed by Reddit ]")
          && !DeletedCommentsClassifier.bodyIsRedditPlaceholder("deleted") && !DeletedCommentsClassifier.bodyIsRedditPlaceholder("[deleted] was here"))
    let goneAuthor = P(comment: comment(author: "[deleted]"))
    check("a deleted account's comment with its text intact is still voted on and replied to, with no profile to open",
          goneAuthor.isLive && goneAuthor.allows(.vote) && goneAuthor.allows(.reply) && !goneAuthor.allows(.openProfile)
          && !goneAuthor.allows(.tagUser) && !goneAuthor.allows(.copyUsername))

    // Restored from an archive: the live comment is still deleted.
    let archive = ArchivedComment(fullname: "t1_c1", author: "realuser", body: "the lost words", score: 9, reason: .moderatorRemoved)
    let restored = P(comment: comment(author: "[deleted]", body: "[removed]"), recovered: archive)
    check("a restored comment is removed on Reddit but shows the archive's text and author",
          restored.status == .removed && restored.isRecovered && restored.text == "the lost words" && restored.author == "realuser")
    check("a restored comment takes no vote, reply, quote, save, award, report, image or moderator action", !writes.contains { restored.allows($0) })
    check("a restored comment's recovered text can be copied, translated and selected",
          restored.allows(.copyText) && restored.allows(.translate) && restored.allows(swipe: .selectText))
    check("a restored comment's recovered author can be opened, copied and tagged",
          restored.allows(.openProfile) && restored.allows(.copyUsername) && restored.allows(.tagUser) && restored.allows(swipe: .author))
    check("a restored comment's menu adds Copy Text, Translate and the author rows",
          rowMenu.filter(restored.allowsMenuItem) == ["share", "copy-link", "copy-text", "copy-username", "tag-user", "translate",
                                                       "remind-me", "mute-notifications"])
    check("a restored comment's swipes still allow Select Text and Author but not votes or Reply",
          restored.restricting(SwipeActionSettings(leftShort: .selectText, leftLong: .author, rightShort: .upvote, rightLong: .reply))
          == SwipeActionSettings(leftShort: .selectText, leftLong: .author, rightShort: .none, rightLong: .none))
    let hidden = P(comment: comment(author: "[deleted]", body: "[deleted]"), recovered: archive, textRevealed: false)
    check("Tap to Show Deleted Comments keeps the text uncopyable until it is revealed",
          !hidden.allows(.copyText) && !hidden.allows(.translate) && !hidden.allows(swipe: .selectText) && hidden.allows(.copyLink))
    let userArchive = ArchivedComment(fullname: "t1_c1", author: "realuser", body: "oops", score: nil, reason: .userDeleted)
    check("a restored comment's reason follows the archive", P(comment: comment(body: "[deleted]"), recovered: userArchive).status == .userDeleted)
    let anonymous = P(comment: comment(author: "[deleted]", body: "[removed]"),
                      recovered: ArchivedComment(fullname: "t1_c1", author: nil, body: "words", score: nil, reason: .moderatorRemoved))
    check("an archive copy with no author leaves the author deleted", !anonymous.hasUsername && anonymous.author == "[deleted]" && anonymous.allows(.copyText))

    // Your own delete, before the tree reloads.
    let justDeleted = P(comment: comment(author: "me"), locallyDeleted: true, isOwn: true)
    check("a comment you just deleted offers no write, edit or delete", justDeleted.status == .userDeleted
          && !writes.contains { justDeleted.allows($0) } && ![.edit, .delete, .voteInsights, .copyText].contains { justDeleted.allows($0) })
    check("your own comment removed by a moderator can still be deleted but not edited",
          P(comment: comment(author: "me", body: "[removed]"), isOwn: true).allows(.delete)
          && !P(comment: comment(author: "me", body: "[removed]"), isOwn: true).allows(.edit))

    // Inbox rows build the policy from the message's author and text.
    check("an inbox reply whose text was deleted takes no vote, save or reply swipe",
          P(author: "[deleted]", body: "[deleted]").restricting(.inboxDefault)
          == SwipeActionSettings(leftShort: .none, leftLong: .none, rightShort: .markRead, rightLong: .none))
    check("an inbox reply with text keeps its swipes", P(author: "amy", body: "thanks!").restricting(.inboxDefault) == .inboxDefault)
}
