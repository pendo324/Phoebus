import Foundation
import PhoebusCore

// --- Jump Button Navigation: New Comments mode (Reborn CommentNavigationMode) ---

@MainActor func checkNewCommentNavigation() async throws {
    typealias Nav = NewCommentNavigator
    func comment(_ id: String, by author: String = "someone") -> Nav.Row { .comment(id: id, author: author) }
    func step(_ rows: [Nav.Row], new: Set<String>, from anchor: Nav.Anchor, _ direction: Int = 1,
              me: String? = "reader", skipped: Set<String> = []) -> Nav.Step {
        Nav.step(rows: rows, newIDs: new, ownUsername: me, anchor: anchor, direction: direction, skippedStubs: skipped)
    }

    // The setting: Reborn's key, 0 = Threads (default), 1 = New Comments.
    check("Jump Button Navigation defaults to Threads", GeneralSettings.default.commentNavigationMode == .threads)
    check("Jump Button Navigation stores Reborn's 0 and 1",
          CommentNavigationMode.threads.stockValue == 0 && CommentNavigationMode.newComments.stockValue == 1)
    check("any other stock value reads as Threads",
          CommentNavigationMode(stockValue: 1) == .newComments && CommentNavigationMode(stockValue: 0) == .threads
          && CommentNavigationMode(stockValue: 7) == .threads && CommentNavigationMode(stockValue: -1) == .threads)
    check("Jump Button Navigation names its modes as Reborn does",
          CommentNavigationMode.allCases.map(\.displayName) == ["Threads", "New Comments"])
    check("New Comments mode relabels the jump button and hints at the hold",
          CommentNavigationMode.newComments.jumpButtonAccessibilityLabel == "Next New Comment"
          && CommentNavigationMode.newComments.jumpButtonAccessibilityHint == "Hold to jump to the previous new comment."
          && CommentNavigationMode.threads.jumpButtonAccessibilityLabel == "Next Comment")
    let oldBlob = Data(#"{"showJumpButton":false}"#.utf8)
    let decoded = try JSONDecoder().decode(GeneralSettings.self, from: oldBlob)
    check("settings saved before the mode existed decode as Threads", decoded.commentNavigationMode == .threads)
    var withMode = GeneralSettings.default
    withMode.commentNavigationMode = .newComments
    let roundTripped = try JSONDecoder().decode(GeneralSettings.self, from: JSONEncoder().encode(withMode))
    check("the mode survives a save and load", roundTripped.commentNavigationMode == .newComments)

    // Backups: the key is imported, an old backup leaves the setting alone.
    let general0 = GeneralSettingsStore.load()
    defer { GeneralSettingsStore.save(general0) }
    var general = general0
    general.commentNavigationMode = .threads
    GeneralSettingsStore.save(general)
    let imported = ApolloSettingsMigration.apply(.init(preferences: ["CommentNavigationMode": 1]))
    check("a backup with CommentNavigationMode 1 turns New Comments on",
          GeneralSettingsStore.load().commentNavigationMode == .newComments
          && imported.applied.contains("Jump Button Navigation"))
    _ = ApolloSettingsMigration.apply(.init(preferences: ["CommentNavigationMode": 0]))
    check("a backup with CommentNavigationMode 0 turns it back to Threads",
          GeneralSettingsStore.load().commentNavigationMode == .threads)
    general.commentNavigationMode = .newComments
    GeneralSettingsStore.save(general)
    let old = ApolloSettingsMigration.apply(.init(preferences: ["DefaultPostsSort": "hot"]))
    check("a backup without the key leaves the mode alone",
          GeneralSettingsStore.load().commentNavigationMode == .newComments
          && !old.applied.contains("Jump Button Navigation"))
    _ = ApolloSettingsMigration.apply(.init(preferences: ["CommentNavigationMode": true]))
    check("a boolean CommentNavigationMode is ignored", GeneralSettingsStore.load().commentNavigationMode == .newComments)
    check("CommentNavigationMode is no longer a skipped key",
          ApolloSettingsMigration.notImported["CommentNavigationMode"] == nil)

    // Stepping.
    let rows = [comment("a"), comment("b"), comment("c"), comment("d"), comment("e")]
    let new: Set<String> = ["b", "d"]
    check("next from the top lands on the first new comment",
          step(rows, new: new, from: .top) == .comment(id: "b", ordinal: 1, total: 2, wrapped: false))
    check("next skips the row the reader is on",
          step(rows, new: new, from: .row("b")) == .comment(id: "d", ordinal: 2, total: 2, wrapped: false))
    check("next from a row between lands on the following one",
          step(rows, new: new, from: .row("c")) == .comment(id: "d", ordinal: 2, total: 2, wrapped: false))
    check("next wraps from the last new comment to the first",
          step(rows, new: new, from: .row("d")) == .comment(id: "b", ordinal: 1, total: 2, wrapped: true))
    check("next wraps from below the last new comment",
          step(rows, new: new, from: .row("e")) == .comment(id: "b", ordinal: 1, total: 2, wrapped: true))
    check("previous from a row between lands on the earlier one",
          step(rows, new: new, from: .row("c"), -1) == .comment(id: "b", ordinal: 1, total: 2, wrapped: false))
    check("previous wraps from the first new comment to the last",
          step(rows, new: new, from: .row("b"), -1) == .comment(id: "d", ordinal: 2, total: 2, wrapped: true))
    check("previous from the top wraps to the last",
          step(rows, new: new, from: .top, -1) == .comment(id: "d", ordinal: 2, total: 2, wrapped: true))
    check("previous from the end lands on the last without wrapping",
          step(rows, new: new, from: .end, -1) == .comment(id: "d", ordinal: 2, total: 2, wrapped: false))
    check("a single new comment wraps onto itself",
          step(rows, new: ["c"], from: .row("c")) == .comment(id: "c", ordinal: 1, total: 1, wrapped: true))
    check("a thread with nothing new has no target", step(rows, new: [], from: .top) == .none)
    check("zero direction has no target", step(rows, new: new, from: .top, 0) == .none)
    check("an anchor that left the thread has no target", step(rows, new: new, from: .row("gone")) == .none)

    // The reader's own comments are not new to them.
    let mixed = [comment("a"), comment("b", by: "Reader"), comment("c", by: "other")]
    check("own comments are skipped, whatever the case of the name",
          step(mixed, new: ["b", "c"], from: .top) == .comment(id: "c", ordinal: 1, total: 1, wrapped: false))
    check("signed out, every new comment counts",
          step(mixed, new: ["b", "c"], from: .top, me: nil) == .comment(id: "b", ordinal: 1, total: 2, wrapped: false))
    check("an empty username does not hide deleted authors",
          step([comment("a", by: "")], new: ["a"], from: .top, me: "") == .comment(id: "a", ordinal: 1, total: 1, wrapped: false))
    check("only own comments new: nothing to jump to", step([comment("a", by: "reader")], new: ["a"], from: .top) == .none)

    // Collapsed branches: only the displayed rows are visited.
    let replyNew = CommentTreeNode(comment: makeComment(id: "reply"), depth: 1)
    let parent = CommentTreeNode(comment: makeComment(id: "parent"), depth: 0, children: [replyNew], isCollapsed: true)
    let sibling = CommentTreeNode(comment: makeComment(id: "sibling"), depth: 0)
    let collapsedRows = Nav.rows(roots: [parent, sibling], rootMoreStub: nil)
    check("a collapsed branch hides its replies from navigation",
          collapsedRows.map(\.id) == ["parent", "sibling"]
          && step(collapsedRows, new: ["reply"], from: .top) == .none)
    check("a new comment inside a collapsed branch is skipped for the next visible one",
          step(collapsedRows, new: ["reply", "sibling"], from: .top) == .comment(id: "sibling", ordinal: 1, total: 1, wrapped: false))
    check("a collapsed comment that is itself new is a stop",
          step(collapsedRows, new: ["parent"], from: .top) == .comment(id: "parent", ordinal: 1, total: 1, wrapped: false))
    let expanded = parent.togglingCollapse(id: "parent")
    check("expanding the branch brings its new reply into the walk",
          step(Nav.rows(roots: [expanded, sibling], rootMoreStub: nil), new: ["reply"], from: .top)
              == .comment(id: "reply", ordinal: 1, total: 1, wrapped: false))

    // "N more replies" rows are stops that the caller expands, then it asks again.
    let stub = MoreStub(id: "more1", count: 3, children: ["x", "y", "z"], parentID: "t1_a", depth: 1)
    let continueThread = MoreStub(id: "cont1", count: 0, children: [], parentID: "t1_a", depth: 8)
    let withStub = Nav.rows(roots: [CommentTreeNode(comment: makeComment(id: "a"), depth: 0, moreStub: stub),
                                    CommentTreeNode(comment: makeComment(id: "b"), depth: 0, moreStub: continueThread)],
                            rootMoreStub: MoreStub(id: "rootmore", count: 9, children: ["q"], parentID: "t3_x", depth: 0))
    check("replies stubs sit after the replies of their comment, root stub last",
          withStub.map(\.id) == ["a", "more1", "b", "cont1", "rootmore"])
    check("Continue thread is not expandable in place",
          withStub[3] == .more(id: "cont1", expandable: false) && withStub[1] == .more(id: "more1", expandable: true))
    check("an unloaded reply group is a stop before a later new comment",
          step(withStub, new: ["b"], from: .row("a")) == .expand(stubID: "more1"))
    check("a failed reply group is skipped",
          step(withStub, new: ["b"], from: .row("a"), skipped: ["more1"]) == .comment(id: "b", ordinal: 1, total: 1, wrapped: false))
    check("a backward search meets the group before the anchor",
          step(withStub, new: ["a"], from: .row("b"), -1) == .expand(stubID: "more1"))
    check("the root-level group is the last stop",
          step(withStub, new: [], from: .row("b"), skipped: ["more1"]) == .expand(stubID: "rootmore"))
    check("with nothing new and no groups, the walk ends",
          step([comment("a")], new: [], from: .top) == .none)

    // After the group loads its replies replace it; the walk resumes from the same anchor.
    let loaded = [comment("a"), comment("r1"), comment("r2"), comment("b")]
    check("resuming after a load lands on the first revealed new reply",
          step(loaded, new: ["r1", "r2"], from: .row("a")) == .comment(id: "r1", ordinal: 1, total: 2, wrapped: false))
    check("a load that reveals only old replies moves on to the next new comment",
          step(loaded, new: ["b"], from: .row("a")) == .comment(id: "b", ordinal: 1, total: 1, wrapped: false))

    // Where the reader is.
    let thread = [comment("a"), comment("b"), comment("c"), comment("d")]
    check("nothing on screen anchors at the top", Nav.anchor(rows: thread, onScreen: [], cursorID: nil) == .top)
    check("the topmost row on screen is the anchor",
          Nav.anchor(rows: thread, onScreen: ["c", "b"], cursorID: nil) == .row("b"))
    check("the landed comment stays the anchor while it is at the top of the screen",
          Nav.anchor(rows: thread, onScreen: ["b", "c"], cursorID: "c") == .row("c"))
    check("a landed comment scrolled well below the top is no longer the anchor",
          Nav.anchor(rows: thread, onScreen: ["a", "b", "c", "d"], cursorID: "d") == .row("a"))
    check("a landed comment that scrolled off falls back to the screen",
          Nav.anchor(rows: thread, onScreen: ["c"], cursorID: "a") == .row("c"))
    check("a list that cannot be inspected carries on from the last landing",
          Nav.anchor(rows: thread, onScreen: nil, cursorID: "c") == .row("c"))
    check("a list that cannot be inspected starts at the top before any landing",
          Nav.anchor(rows: thread, onScreen: nil, cursorID: nil) == .top
          && Nav.anchor(rows: thread, onScreen: nil, cursorID: "gone") == .top)
}
