import Foundation
import PhoebusCore

// --- Where the list scrolls after a comment collapses ---

@MainActor func checkCollapseReveal() async throws {
    typealias Row = CollapseReveal.Row
    // A 844pt list under a 100pt bar with a 50pt bottom inset, 6000pt of comments.
    func viewport(offset: Double, content: Double = 6000) -> CollapseReveal.Viewport {
        CollapseReveal.Viewport(offsetY: offset, boundsHeight: 844, insetTop: 100, insetBottom: 50, contentHeight: content)
    }
    func target(_ row: Row, offset: Double, content: Double = 6000, settling: Bool = false) -> Double? {
        CollapseReveal.scrollTarget(collapsedID: row.id, rows: [Row(id: "next", minY: row.maxY, maxY: row.maxY + 90), row],
                                    viewport: viewport(offset: offset, content: content), settling: settling)
    }

    // Collapse Top from a deep reply: the thread's first comment is far above the screen.
    let root = Row(id: "root", minY: 1200, maxY: 1248)
    check("a collapsed comment above the screen comes back to just under the bar",
          target(root, offset: 4000) == 1100)
    check("the target puts the row's top at the top of the visible area",
          ListViewport.visibleArea(contentOffsetY: 1100, boundsHeight: 844, insetTop: 100, insetBottom: 50).top == root.minY)

    // A tall comment collapsed from its lower half: its top is off the screen too.
    check("a tall comment whose top is scrolled off is brought back by its top",
          target(Row(id: "tall", minY: 2000, maxY: 3400), offset: 2900) == 1900)
    check("a comment straddling the bar counts as above the screen",
          target(Row(id: "straddle", minY: 2000, maxY: 2300), offset: 1950) == 1900)

    check("a comment already on screen stays where it is",
          target(Row(id: "visible", minY: 2400, maxY: 2700), offset: 2000) == nil)
    check("a comment whose top sits at the top of the visible area stays",
          target(Row(id: "top", minY: 2100, maxY: 2400), offset: 2000) == nil)
    check("a comment near the bottom of the screen stays where it is",
          target(Row(id: "bottom", minY: 2700, maxY: 2750), offset: 2000) == nil)

    // Too little content below to put the comment at the top: as far as the list goes.
    check("a collapsed comment near the end of the thread scrolls as far as the content allows",
          target(Row(id: "last", minY: 5800, maxY: 5848), offset: 5000, content: 6000, settling: true) == 6000 + 50 - 844)
    check("a thread shorter than the screen does not scroll below its top",
          target(Row(id: "short", minY: 300, maxY: 348), offset: 500, content: 600) == -100)
    check("a comment above the top of a thread's first screen scrolls to the list's start",
          target(Row(id: "first", minY: 40, maxY: 90), offset: 400, content: 6000) == -60)

    // A far-off row's frame was an estimate: the passes after the first measure again and correct both ways.
    check("a settling pass that finds the row still above the bar scrolls up to it",
          target(Row(id: "short", minY: 3000, maxY: 3048), offset: 2800, settling: true) == 2900)
    check("a settling pass that finds the row below the bar scrolls back to it",
          target(Row(id: "over", minY: 3600, maxY: 3648), offset: 2900, settling: true) == 3500)
    check("a settling pass within a point of the target is done",
          target(Row(id: "done", minY: 3000.4, maxY: 3048), offset: 2900, settling: true) == nil)
    check("the first pass leaves a row below the bar alone, a settling pass does not",
          target(Row(id: "below", minY: 3600, maxY: 3648), offset: 2900) == nil
            && target(Row(id: "below", minY: 3600, maxY: 3648), offset: 2900, settling: true) == 3500)

    // The row a collapse names in the list, independent of how the list animates the change.
    let leafC = CommentTreeNode(comment: makeComment(id: "c"), depth: 2)
    let nodeB = CommentTreeNode(comment: makeComment(id: "b"), depth: 1, children: [leafC])
    let nodeD = CommentTreeNode(comment: makeComment(id: "d"), depth: 1,
                                moreStub: MoreStub(id: "more", count: 4, children: ["x"], parentID: "t1_d", depth: 2))
    let nodeA = CommentTreeNode(comment: makeComment(id: "a"), depth: 0, children: [nodeB, nodeD])
    let nodeE = CommentTreeNode(comment: makeComment(id: "e"), depth: 0)
    let rootMore = MoreStub(id: "rootmore", count: 9, children: ["q"], parentID: "t3_x", depth: 0)
    typealias Position = CollapseReveal.Position
    check("a comment's place counts the rows drawn before it, replies and more rows included",
          CollapseReveal.position(of: "e", roots: [nodeA, nodeE], rootMoreStub: rootMore) == Position(index: 5, count: 7)
            && CollapseReveal.position(of: "d", roots: [nodeA, nodeE], rootMoreStub: rootMore) == Position(index: 3, count: 7))
    check("a deep reply is found among its thread's rows",
          CollapseReveal.position(of: "c", roots: [nodeA, nodeE], rootMoreStub: nil) == Position(index: 2, count: 6))
    check("a comment the list does not hold has no place",
          CollapseReveal.position(of: "zz", roots: [nodeA, nodeE], rootMoreStub: nil) == nil)
    let collapsedA = [nodeA].map { $0.togglingCollapse(id: "a") }
    check("collapsing a thread's first comment leaves its row where it was and drops the rest",
          CollapseReveal.position(of: "a", roots: [nodeA, nodeE], rootMoreStub: nil)?.index == 0
            && CollapseReveal.position(of: "a", roots: collapsedA + [nodeE], rootMoreStub: nil) == Position(index: 0, count: 2))

    check("a collapse of a row the list does not hold scrolls nowhere",
          CollapseReveal.scrollTarget(collapsedID: "gone", rows: [root], viewport: viewport(offset: 4000), settling: false) == nil)
    check("an empty list scrolls nowhere",
          CollapseReveal.scrollTarget(collapsedID: "root", rows: [], viewport: viewport(offset: 0), settling: true) == nil)
}
