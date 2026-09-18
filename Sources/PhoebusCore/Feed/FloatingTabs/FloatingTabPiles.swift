import Foundation

/// Magnetic Stacking's piles of floating post tabs: each pile is an
/// ordered list of tab IDs, front first. A tab in no pile is free.
public struct FloatingTabPiles: Equatable, Sendable {
    public private(set) var piles: [String: [String]] = [:]

    public init() {}

    public func stackID(of id: String) -> String? {
        piles.first { $0.value.contains(id) }?.key
    }

    /// The whole pile a tab is in, front first; just the tab when free.
    public func members(of id: String) -> [String] {
        stackID(of: id).flatMap { piles[$0] } ?? [id]
    }

    /// 0 for the front (or a free tab), then 1, 2, … behind it.
    public func order(of id: String) -> Int {
        members(of: id).firstIndex(of: id) ?? 0
    }

    public func isStacked(_ id: String) -> Bool { stackID(of: id) != nil }

    /// The dragged group lands at the front of the target's pile, or forms a
    /// new one with it.
    public mutating func join(_ group: [String], onto target: String) {
        let existing = members(of: target)
        let id = stackID(of: target) ?? UUID().uuidString
        for member in group { removeFromPiles(member) }
        piles[id] = group + existing.filter { !group.contains($0) }
    }

    /// Breaks a pile apart, returning its members front first.
    @discardableResult
    public mutating func disband(_ stackID: String) -> [String] {
        piles.removeValue(forKey: stackID) ?? []
    }

    /// Spring the given tabs back into one pile, in this order.
    public mutating func regather(_ ids: [String]) {
        guard ids.count >= 2 else { return }
        for id in ids { removeFromPiles(id) }
        piles[UUID().uuidString] = ids
    }

    /// Drops tabs that are no longer open; a pile of one is no pile.
    public mutating func prune(keeping open: Set<String>) {
        for (id, members) in piles {
            let kept = members.filter { open.contains($0) }
            piles[id] = kept.count >= 2 ? kept : nil
        }
    }

    private mutating func removeFromPiles(_ id: String) {
        guard let stack = stackID(of: id) else { return }
        let rest = piles[stack]?.filter { $0 != id } ?? []
        piles[stack] = rest.count >= 2 ? rest : nil
    }
}
