import Foundation

/// Anything Reddit lets the user vote on and save: posts and comments.
/// `VoteStateStore` and `ContentActions` work on this, so both kinds share
/// one optimistic vote/save path.
public protocol Votable: Sendable {
    /// Reddit fullname (`t3_...`, `t1_...`).
    var name: String { get }
    /// The server's vote as of the fetch: true up, false down, nil none.
    var likes: Bool? { get }
    /// The server's saved flag as of the fetch.
    var saved: Bool { get }
}

extension RedditPost: Votable {}
extension RedditComment: Votable {}

/// A votable item known only by fullname, such as an inbox comment reply,
/// whose listing carries no vote or saved state.
public struct VotableRef: Votable {
    public let name: String
    public let likes: Bool?
    public let saved: Bool

    public init(name: String, likes: Bool? = nil, saved: Bool = false) {
        self.name = name
        self.likes = likes
        self.saved = saved
    }
}
