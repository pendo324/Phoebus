import Foundation

/// Date headers between chat messages.
///
/// Apollo uses exactly two chat date formats:
///
/// - `MMM d, yyyy, h:mm a`  - e.g. "Jan 3, 2025, 4:15 PM"
/// - `E, d MMM, h:mm a`     - e.g. "Fri, 3 Jan, 4:15 PM"
///
/// Both match Apollo, not invented. The rule that picks between them
/// is MessageKit's own: recent messages get the weekday form, older
/// ones get the full date including the year. The exact threshold
/// isn't known, so the standard one-week boundary is used and
/// labelled as such rather than presented as Apollo's.
public enum ChatDateFormatter {
    /// Format for older messages.
    public static let fullFormat = "MMM d, yyyy, h:mm a"
    /// Format for recent messages.
    public static let recentFormat = "E, d MMM, h:mm a"

    /// Header text for a message's date.
    public static func headerText(for date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }

        let formatter = DateFormatter()
        // Pinned, like every other fixed-format formatter in this project:
        // without it the parse and render shift under a non-Gregorian
        // device calendar.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // MessageKit's own boundary: within the last week, name the
        // weekday; beyond it, give the full date with the year.
        let week: TimeInterval = 7 * 24 * 60 * 60
        formatter.dateFormat = now.timeIntervalSince(date) < week ? recentFormat : fullFormat
        return formatter.string(from: date)
    }

    /// Whether a date header belongs between two messages.
    ///
    /// A header is shown when the day changes, which is why the first
    /// message in a room always gets one.
    public static func needsHeader(previous: Date?, current: Date) -> Bool {
        guard let previous else { return true }
        return !Calendar.current.isDate(previous, inSameDayAs: current)
    }
}
