import Foundation

/// Identifies the screen whose list saved a reading position. Each screen
/// keeps one for its lifetime and hands it to its scroll view and its Return
/// arrow, so an arrow only ever shows for the position its own list saved.
public final class ScrollReturnOwner: Sendable {
    public let id = UUID()

    public init() {}
}

/// Which screens have a saved reading position to offer the Return Button
/// for. Reborn "Return Button": the arrow belongs to the view controller that
/// scrolled, so a position saved in a thread is never offered on the feed
/// behind it, and survives while that screen stays in the stack.
public struct ScrollReturnOffers<Owner: Hashable & Sendable>: Sendable {
    public private(set) var owners: Set<Owner> = []

    public init() {}

    /// True when `owner` has a position a return would restore.
    public func canReturn(_ owner: Owner) -> Bool {
        owners.contains(owner)
    }

    public mutating func offer(_ owner: Owner) {
        owners.insert(owner)
    }

    /// Returns whether `owner` had an offer to withdraw.
    @discardableResult
    public mutating func withdraw(_ owner: Owner) -> Bool {
        owners.remove(owner) != nil
    }
}
