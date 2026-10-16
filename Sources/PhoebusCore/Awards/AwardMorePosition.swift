import Foundation

extension Array where Element == CommentTreeNode {
    /// Where `stub` sits in this tree, in the terms of Shreddit's
    /// more-comments partial: the thread's own trailing stub (`rootStub`), or
    /// the stub among a comment's replies. Nil when the stub isn't in the tree.
    public func awardMorePosition(of stub: MoreStub, rootStub: MoreStub?) -> AwardWebService.MorePosition? {
        if stub.id == rootStub?.id {
            return AwardWebService.MorePosition(parentPath: [], loaded: count, remaining: stub.count)
        }
        for (index, node) in enumerated() {
            if let path = node.awardParentPath(of: stub.id, path: [index]) {
                return AwardWebService.MorePosition(parentPath: path.path, loaded: path.loaded, remaining: stub.count)
            }
        }
        return nil
    }
}

extension CommentTreeNode {
    fileprivate func awardParentPath(of stubID: String, path: [Int]) -> (path: [Int], loaded: Int)? {
        if moreStub?.id == stubID { return (path, children.count) }
        for (index, child) in children.enumerated() {
            if let found = child.awardParentPath(of: stubID, path: path + [index]) { return found }
        }
        return nil
    }
}
