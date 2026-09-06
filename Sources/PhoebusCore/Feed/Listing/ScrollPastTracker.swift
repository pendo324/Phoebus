import Foundation

/// Which feed rows are on screen, by index, so a row leaving can be told
/// to have gone off the top. A plain class: it changes on every scroll and
/// must not redraw the feed.
public final class ScrollPastTracker {
    public init() {}

    private var visible: [String: Int] = [:]

    public func appeared(_ id: String, at index: Int) { visible[id] = index }

    /// Whether the row left with a later row still showing.
    public func disappearedAbove(_ id: String) -> Bool {
        guard let index = visible.removeValue(forKey: id) else { return false }
        return visible.values.contains { $0 > index }
    }
}
