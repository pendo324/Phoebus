import Foundation

/// Reddit's `edited` field on posts and comments: `false` when never
/// edited, otherwise the edit's Unix time (sometimes fractional). Very old
/// things carry a bare `true` with no time. Anything else decodes as
/// unedited rather than failing the whole listing.
public struct RedditEditedTime: Codable, Sendable, Equatable {
    public let isEdited: Bool
    /// Nil for unedited things and for a bare `true`.
    public let date: Date?

    public init(isEdited: Bool, date: Date? = nil) {
        self.isEdited = isEdited || date != nil
        self.date = date
    }

    public init(from decoder: Decoder) throws {
        let container = try? decoder.singleValueContainer()
        if let flag = try? container?.decode(Bool.self) {
            self.init(isEdited: flag)
        } else if let seconds = try? container?.decode(Double.self), seconds > 0 {
            self.init(isEdited: true, date: Date(timeIntervalSince1970: seconds))
        } else if let text = try? container?.decode(String.self), let seconds = Double(text), seconds > 0 {
            self.init(isEdited: true, date: Date(timeIntervalSince1970: seconds))
        } else {
            self.init(isEdited: false)
        }
    }

    /// Written back in Reddit's own shape so cached posts decode the same.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let date {
            try container.encode(date.timeIntervalSince1970)
        } else {
            try container.encode(isEdited)
        }
    }
}

/// Apollo's edited indicator (a pencil beside a comment's score and after
/// a post's age), and the edit time shown when it or the age is tapped.
public enum EditedMarker {
    public static func isShown(_ edited: RedditEditedTime?, enabled: Bool) -> Bool {
        enabled && edited?.isEdited == true
    }

    /// "Edited 2h Ago" over "Edited on October 10, 2026 at 3:00 PM", like
    /// the age's own detail. `condensed` gives the shorter date alone.
    public static func lines(_ edited: RedditEditedTime, now: Date = Date(), condensed: Bool = false,
                             timeZone: TimeZone = .current, locale: Locale = .current) -> (title: String, message: String?) {
        guard let date = edited.date else { return ("Edited", nil) }
        let interval = max(0, now.timeIntervalSince(date))
        let title = interval < 60 ? "Edited Just now" : "Edited \(compactAge(interval)) Ago"
        let formatted = format(date, dateStyle: condensed ? .medium : .long, timeZone: timeZone, locale: locale)
        return (title, condensed ? formatted : "Edited on \(formatted)")
    }

    /// The line a tapped age adds under its creation time:
    /// "Edited Oct 10, 2026 at 3:00 PM", or nil when unedited.
    public static func timestampLine(_ edited: RedditEditedTime?, timeZone: TimeZone = .current,
                                     locale: Locale = .current) -> String? {
        guard let edited, edited.isEdited else { return nil }
        guard let date = edited.date else { return "Edited" }
        return "Edited \(format(date, dateStyle: .medium, timeZone: timeZone, locale: locale))"
    }

    /// `message` with `timestampLine` appended on its own line.
    public static func appendingTimestamp(_ edited: RedditEditedTime?, to message: String?,
                                          timeZone: TimeZone = .current, locale: Locale = .current) -> String? {
        guard let line = timestampLine(edited, timeZone: timeZone, locale: locale) else { return message }
        guard let message, !message.isEmpty else { return line }
        return "\(message)\n\(line)"
    }

    static func compactAge(_ interval: TimeInterval) -> String {
        switch interval {
        case ..<3600: return "\(Int(interval / 60))m"
        case ..<86400: return "\(Int(interval / 3600))h"
        case ..<2_592_000: return "\(Int(interval / 86400))d"
        case ..<31_536_000: return "\(Int(interval / 2_592_000))mo"
        default: return "\(Int(interval / 31_536_000))y"
        }
    }

    private static func format(_ date: Date, dateStyle: DateFormatter.Style, timeZone: TimeZone, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = dateStyle
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
