import Foundation
import PhoebusCore

// MARK: - Own edits, comments and submissions show when a thread or feed is reopened

@MainActor func checkOwnChangesShowWhenReopened() async throws {
    func post(_ json: String = "") -> RedditPost {
        let full = """
        {"id":"p1","name":"t3_p1","title":"t","author":"me","subreddit":"test",
         "permalink":"/r/test/comments/p1/t/","score":1,"num_comments":0,"created_utc":0,
         "is_self":true,"over_18":false,"spoiler":false,"stickied":false,"saved":false,
         "selftext":"old body"\(json)}
        """
        return try! JSONDecoder.reddit.decode(RedditPost.self, from: full.data(using: .utf8)!)
    }
    func comment(_ id: String, author: String, flair: String? = nil) -> RedditComment {
        let flairJSON = flair.map { ##","author_flair_text":"\##($0)","author_flair_background_color":"#ff0000""## } ?? ""
        let json = """
        {"id":"\(id)","name":"t1_\(id)","author":"\(author)","body":"b","score":0,"created_utc":0,
         "parent_id":"t3_p1","link_id":"t3_p1","saved":false,"score_hidden":false,"stickied":false\(flairJSON)}
        """
        return try! JSONDecoder.reddit.decode(RedditComment.self, from: json.data(using: .utf8)!)
    }

    // An edited post body shows on the copy a feed row still holds.
    let changes = OwnPostChanges.shared
    changes.reset()
    check("own changes: an untouched post is left as it was", changes.apply(to: post()).selftext == "old body")
    changes.recordEdit(fullname: "t3_p1", body: "new body")
    check("own changes: a reopened post shows its edited body", changes.apply(to: post()).selftext == "new body")
    check("own changes: another post keeps its body",
          changes.apply(to: post()).name == "t3_p1" && changes.isDeleted("t3_p1") == false)
    changes.recordDeletion(fullname: "t3_p1")
    check("own changes: a deleted post is remembered", changes.isDeleted("t3_p1") && !changes.isDeleted("t3_p2"))

    // The comment count follows what this device posted, until Reddit's own count moves on.
    changes.reset()
    check("comment count: starts at the listed count", changes.commentCount(for: "t3_p1", listed: 0) == 0)
    changes.recordCommentChange(fullname: "t3_p1", listed: 0, delta: 1)
    check("comment count: a posted comment shows at once", changes.commentCount(for: "t3_p1", listed: 0) == 1)
    changes.recordCommentChange(fullname: "t3_p1", listed: 0, delta: 1)
    check("comment count: a second comment adds to the first", changes.commentCount(for: "t3_p1", listed: 0) == 2)
    changes.observeCommentCount(fullname: "t3_p1", count: 0)
    check("comment count: a refetch Reddit hasn't caught up with keeps ours", changes.commentCount(for: "t3_p1", listed: 0) == 2)
    changes.observeCommentCount(fullname: "t3_p1", count: 2)
    check("comment count: a refetch that includes ours isn't counted twice", changes.commentCount(for: "t3_p1", listed: 0) == 2)
    check("comment count: nor is the stale listed copy", changes.apply(to: post()).numComments == 2)
    changes.observeCommentCount(fullname: "t3_p1", count: 5)
    check("comment count: Reddit's later count wins", changes.commentCount(for: "t3_p1", listed: 0) == 5)
    changes.recordCommentChange(fullname: "t3_p1", listed: 0, delta: 1)
    check("comment count: a comment after a refetch builds on Reddit's count", changes.commentCount(for: "t3_p1", listed: 0) == 6)
    changes.recordCommentChange(fullname: "t3_p1", listed: 0, delta: -9)
    check("comment count: never below zero", changes.commentCount(for: "t3_p1", listed: 0) == 0)
    changes.reset()

    // Edits and deletions reach a tree that is cached or rebuilt.
    let tree = [CommentTreeNode(comment: comment("a", author: "me"), depth: 0,
                                children: [CommentTreeNode(comment: comment("b", author: "me"), depth: 1)])]
    let edited = tree.settingBody(of: "b", to: "changed")
    check("edited comment: a nested reply takes the new body",
          edited.first?.children.first?.comment.body == "changed" && edited.first?.comment.body == "b")
    check("edited comment: an unknown id changes nothing", tree.settingBody(of: "zzz", to: "x").first?.comment.body == "b")
    let removed = tree.markingDeleted("a")
    check("deleted comment: shows what Reddit lists in its place",
          removed.first?.comment.body == "[deleted]" && removed.first?.comment.author == "[deleted]"
          && removed.first?.children.first?.comment.body == "b")

    // A comment you just posted carries the OP mark and your flair where they're known.
    let opPost = post(##","author_flair_text":"Mod","author_flair_background_color":"#00ff00""##)
    let mine = PostedCommentContext.decorate(comment("n", author: "me"), post: opPost, roots: [])
    check("posted comment: marked OP when its author wrote the post", mine.isSubmitter == true)
    check("posted comment: takes the post author's flair when they wrote the post",
          mine.authorFlairText == "Mod" && mine.authorFlairBackgroundColor == "#00ff00")
    let other = PostedCommentContext.decorate(comment("n", author: "Someone"), post: opPost, roots: [])
    check("posted comment: not OP and no flair for another author", other.isSubmitter != true && other.authorFlairText == nil)
    let earlier = [CommentTreeNode(comment: comment("e", author: "someone", flair: "Regular"), depth: 0)]
    let reuses = PostedCommentContext.decorate(comment("n", author: "Someone"), post: opPost, roots: earlier)
    check("posted comment: reuses the flair on the author's earlier comment",
          reuses.authorFlairText == "Regular" && reuses.isSubmitter != true)
    let kept = PostedCommentContext.decorate(comment("n", author: "me", flair: "Own"), post: opPost, roots: [])
    check("posted comment: a flair Reddit sent is kept", kept.authorFlairText == "Own" && kept.isSubmitter == true)
    check("posted comment: left alone when the post isn't known",
          PostedCommentContext.decorate(comment("n", author: "me"), post: nil, roots: []).isSubmitter == nil)

    // A submitted post shows at the top of a feed whose listing doesn't have it yet.
    let submittedAnswer = Data(#"{"json":{"errors":[],"data":{"url":"https://www.reddit.com/r/test/comments/p1/t/","id":"p1","name":"t3_p1"}}}"#.utf8)
    check("submit response: the new post's fullname", SubmittedPostResponse.fullname(from: submittedAnswer) == "t3_p1")
    check("submit response: a bare id gets its prefix",
          SubmittedPostResponse.fullname(from: Data(#"{"json":{"errors":[],"data":{"id":"p1"}}}"#.utf8)) == "t3_p1")
    check("submit response: errors and other shapes yield nothing",
          SubmittedPostResponse.fullname(from: Data(#"{"json":{"errors":[["RATELIMIT","x","y"]]}}"#.utf8)) == nil
          && SubmittedPostResponse.fullname(from: Data(#"{"json":{"errors":[],"data":{}}}"#.utf8)) == nil)
    let now = Date()
    let submitted = [SubmittedPost(post: post(), at: now)]
    let page = [makeTestPost(id: "x"), makeTestPost(id: "y")]
    check("submitted post: put first when the listing lacks it",
          page.restoringSubmitted(submitted, now: now).map(\.id) == ["p1", "x", "y"])
    check("submitted post: not repeated once the listing has it",
          (page + [post()]).restoringSubmitted(submitted, now: now).map(\.id) == ["x", "y", "p1"])
    check("submitted post: dropped once old enough that the listing should have it",
          page.restoringSubmitted(submitted, now: now.addingTimeInterval(SubmittedPost.lifetime + 1)).map(\.id) == ["x", "y"])
    check("submitted post: the newest of several comes first",
          page.restoringSubmitted([SubmittedPost(post: makeTestPost(id: "old"), at: now.addingTimeInterval(-5)),
                                   SubmittedPost(post: makeTestPost(id: "new"), at: now)], now: now).map(\.id)
            == ["new", "old", "x", "y"])
}
