import Foundation

/// Press-and-hold on a tab bar item: Reborn "Settings Shortcuts" (#1150) on
/// the Settings tab and, on the Posts tab, the subreddit switcher sheet
/// (`Apollo-Reborn#1387`).
public enum TabLongPressPolicy {
    /// How long the finger must rest on the item.
    public static let minimumPressDuration: TimeInterval = 0.45

    /// Reborn counts the Posts tab first.
    public static let postsTab = 0

    /// The item under `x` when `count` items share a bar `width` points wide;
    /// nil outside the bar.
    public static func slot(atX x: Double, width: Double, count: Int) -> Int? {
        guard count > 0, width > 0, x >= 0, x < width else { return nil }
        return Int(x / (width / Double(count)))
    }

    /// Picking a subreddit from the Posts-tab switcher shows that feed straight
    /// under the Subreddits list, so a feed or post already open on the tab is
    /// popped first.
    public enum SwitchPlan: Equatable, Sendable {
        /// The tab is at the Subreddits list: open the feed now.
        case openFeed
        /// Pop the tab to the list, then open the feed once the pop has run.
        case popToRootThenOpenFeed(delay: TimeInterval)
    }

    /// Time for the pop to finish before the feed is pushed; a push in the
    /// same turn as the pop is dropped.
    public static let popSettleDelay: TimeInterval = 0.35

    public static func switchPlan(hasPushedScreens: Bool) -> SwitchPlan {
        hasPushedScreens ? .popToRootThenOpenFeed(delay: popSettleDelay) : .openFeed
    }
}

/// Remembers that a long press on a tab is (or just was) in progress, so the
/// re-tap UIKit or the glass bar's selection lens reports when the finger
/// lifts is not taken for a second tap (`TabReselectScrollPolicy` would scroll
/// the list to the top, or go back a page, under the sheet that just opened).
public struct TabLongPressGate: Equatable, Sendable {
    /// How long after the finger lifts a re-selection still counts as part of
    /// the press.
    public static let releaseGrace: TimeInterval = 0.5

    private var tab: Int?
    private var pressing = false
    private var releasedAt: Date?

    public init() {}

    public mutating func began(tab: Int) {
        self.tab = tab
        pressing = true
        releasedAt = nil
    }

    public mutating func ended(now: Date) {
        guard pressing else { return }
        pressing = false
        releasedAt = now
    }

    public func suppressesReselect(tab: Int, now: Date) -> Bool {
        guard self.tab == tab else { return false }
        if pressing { return true }
        guard let releasedAt else { return false }
        return now.timeIntervalSince(releasedAt) < Self.releaseGrace
    }
}
