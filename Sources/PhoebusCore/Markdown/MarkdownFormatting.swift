import Foundation

/// The composer's markdown actions: the Quick Bar's buttons and its •••
/// menu (Preview aside, which only shows the text). Each works on the
/// selection, as Apollo's composer does, and returns the
/// new text with the range to select afterwards. Ranges are UTF-16
/// (`NSRange`), as `UITextView` reports them.
public enum MarkdownAction: String, CaseIterable, Sendable {
    case bold, italic, link, subreddit, user
    case superscript, quote, spoiler, strikethrough, header
    case unorderedList, orderedList, horizontalRule, code, spongeText
}

public enum MarkdownFormatting {
    public struct Edit: Equatable, Sendable {
        public let text: String
        public let selection: NSRange

        public init(text: String, selection: NSRange) {
            self.text = text
            self.selection = selection
        }
    }

    /// nil when the action can't apply (SpongeText with nothing selected).
    public static func apply(_ action: MarkdownAction, to text: String, selection: NSRange) -> Edit? {
        let ns = text as NSString
        let range = NSRange(location: min(max(selection.location, 0), ns.length),
                            length: min(max(selection.length, 0), ns.length - min(max(selection.location, 0), ns.length)))
        let selected = ns.substring(with: range)
        switch action {
        case .bold: return wrap(ns, range, "**", "**")
        case .italic: return wrap(ns, range, "*", "*")
        case .strikethrough: return wrap(ns, range, "~~", "~~")
        case .spoiler: return wrap(ns, range, ">!", "!<")
        case .superscript: return wrap(ns, range, "^(", ")")
        case .code:
            if selected.contains("\n") { return prefixLines(ns, range) { _ in "    " } }
            return wrap(ns, range, "`", "`")
        case .link:
            if range.length == 0 {
                return replace(ns, range, with: "[]()", select: NSRange(location: 1, length: 0))
            }
            if selected.hasPrefix("http://") || selected.hasPrefix("https://") {
                return replace(ns, range, with: "[](\(selected))", select: NSRange(location: 1, length: 0))
            }
            let inserted = "[\(selected)]()"
            return replace(ns, range, with: inserted, select: NSRange(location: (inserted as NSString).length - 1, length: 0))
        case .subreddit: return token(ns, range, "/r/")
        case .user: return token(ns, range, "/u/")
        case .quote: return prefixLines(ns, range) { _ in "> " }
        case .header: return prefixLines(ns, range) { _ in "# " }
        case .unorderedList: return prefixLines(ns, range) { _ in "- " }
        case .orderedList: return prefixLines(ns, range) { "\($0 + 1). " }
        case .horizontalRule:
            let before = ns.substring(to: range.location)
            let lead = before.isEmpty || before.hasSuffix("\n\n") ? "" : (before.hasSuffix("\n") ? "\n" : "\n\n")
            let inserted = lead + "---\n\n"
            return replace(ns, range, with: inserted, select: NSRange(location: (inserted as NSString).length, length: 0))
        case .spongeText:
            guard range.length > 0 else { return nil }
            let sponged = SpongeText.transform(selected)
            return replace(ns, range, with: sponged, select: NSRange(location: 0, length: (sponged as NSString).length))
        }
    }

    /// Wraps the selection, keeping it selected; with none, puts the
    /// cursor between the markers.
    private static func wrap(_ ns: NSString, _ range: NSRange, _ prefix: String, _ suffix: String) -> Edit {
        let selected = ns.substring(with: range)
        let p = (prefix as NSString).length
        return replace(ns, range, with: prefix + selected + suffix, select: NSRange(location: p, length: range.length))
    }

    /// "/r/" and "/u/", spaced from a preceding word.
    private static func token(_ ns: NSString, _ range: NSRange, _ token: String) -> Edit {
        let needsSpace = range.location > 0
            && !(ns.substring(with: NSRange(location: range.location - 1, length: 1)).first?.isWhitespace ?? true)
        let inserted = (needsSpace ? " " : "") + token + ns.substring(with: range)
        return replace(ns, range, with: inserted, select: NSRange(location: (inserted as NSString).length, length: 0))
    }

    /// Prefixes every line the selection touches (the cursor's line when
    /// nothing is selected), selecting the result.
    private static func prefixLines(_ ns: NSString, _ range: NSRange, _ prefix: (Int) -> String) -> Edit {
        let lines = ns.lineRange(for: range)
        var block = ns.substring(with: lines)
        let trailingNewline = block.hasSuffix("\n")
        if trailingNewline { block.removeLast() }
        let prefixed = block.components(separatedBy: "\n").enumerated()
            .map { prefix($0.offset) + $0.element }.joined(separator: "\n")
        let result = prefixed + (trailingNewline ? "\n" : "")
        let full = ns.replacingCharacters(in: lines, with: result)
        let selection = range.length == 0
            ? NSRange(location: lines.location + (prefixed as NSString).length, length: 0)
            : NSRange(location: lines.location, length: (prefixed as NSString).length)
        return Edit(text: full, selection: selection)
    }

    private static func replace(_ ns: NSString, _ range: NSRange, with inserted: String, select relative: NSRange) -> Edit {
        Edit(text: ns.replacingCharacters(in: range, with: inserted),
             selection: NSRange(location: range.location + relative.location, length: relative.length))
    }
}
