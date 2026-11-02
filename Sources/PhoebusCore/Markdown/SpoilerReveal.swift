import Foundation

/// Which inline spoilers of a body are open. A tap on a spoiler's label or on
/// its revealed text toggles it, so a second tap hides it again; the state is
/// local to the view that draws the body and is never stored.
///
/// A body drawn as several pieces (`BodyParagraphs`) shares one value: each
/// piece numbers its spoilers from 0, and `bases` places them in the body's own
/// numbering, where a spoiler cut across two pieces is one.
public struct SpoilerReveal: Equatable, Sendable {
    public private(set) var open: Set<Int> = []

    public init() {}

    public func isOpen(_ number: Int) -> Bool { open.contains(number) }

    /// Opens a hidden spoiler and hides an open one.
    public mutating func toggle(_ number: Int) {
        if open.contains(number) { open.remove(number) } else { open.insert(number) }
    }

    /// The open spoilers of a piece whose first spoiler is `base` in the body's
    /// numbering, in the piece's own numbers.
    public func revealing(base: Int, count: Int) -> Set<Int> {
        Set((0..<max(count, 0)).filter { open.contains(base + $0) })
    }

    /// Each piece's `base`: the body-wide number of its first spoiler.
    /// `counts[i]` is how many spoilers piece `i` renders and `continues[i]`
    /// whether its first one is the one piece `i - 1` ended inside.
    public static func bases(counts: [Int], continues: [Bool]) -> [Int] {
        var bases: [Int] = []
        var next = 0
        for (index, count) in counts.enumerated() {
            let joins = index < continues.count && continues[index] && count > 0 && index > 0
            let base = joins ? max(next - 1, 0) : next
            bases.append(base)
            next = base + count
        }
        return bases
    }

    /// The VoiceOver action that toggles spoiler `number` of `total`: a body
    /// with several numbers them, so the actions can be told apart.
    public func actionName(for number: Int, total: Int) -> String {
        let verb = isOpen(number) ? "Hide spoiler" : "Reveal spoiler"
        return total > 1 ? "\(verb) \(number + 1)" : verb
    }
}
