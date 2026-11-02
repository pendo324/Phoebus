import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

/// Marks the text of an inline spoiler in a rendered body; the value is the
/// spoiler's number within that body, from 0.
public enum SpoilerAttribute: AttributedStringKey {
    public typealias Value = Int
    public static let name = "phoebusSpoiler"
}

/// Reddit's inline spoiler, `>!hidden!<` (or `&gt;!hidden!&lt;` when the API
/// escapes a body). Apollo draws a hidden spoiler as a "SPOILER" label that a
/// tap expands in place; the text itself is not in the drawn string until then.
public enum SpoilerMarkup {
    /// Private-use markers that carry a spoiler's ends through the Markdown
    /// parser, so emphasis and links inside one are parsed as usual.
    static let opener: Character = "\u{E000}"
    static let closer: Character = "\u{E001}"

    /// The scheme of the link a hidden spoiler's label carries.
    public static let scheme = "phoebus-spoiler"

    /// The label a hidden spoiler is drawn as.
    static let label = "\u{A0}SPOILER\u{A0}"

    /// A spoiler runs to its `!<` within one paragraph, and the closest `!<` wins,
    /// so `>!a!< b >!c!<` is two.
    private static let pattern = try! NSRegularExpression(
        pattern: #"(?:>|&gt;)!((?:(?!\n[ \t]*\n)[\s\S])+?)!(?:<|&lt;)"#
    )
    private static let inlineCode = try! NSRegularExpression(
        pattern: #"(?<!`)(`+)(?!`)[\s\S]*?[^`]\1(?!`)"#
    )

    /// Rewrites each spoiler's `>!` and `!<` to the private-use markers. Code
    /// spans and blocks, escaped openers and unclosed `>!` stay literal.
    public static func fence(_ text: String) -> String {
        var source = text
        if source.contains(opener) || source.contains(closer) {
            source.removeAll { $0 == opener || $0 == closer }
        }
        let found = matches(in: source)
        guard !found.isEmpty else { return source }
        let ns = NSMutableString(string: source)
        for match in found.reversed() {
            let tail = closerLength(match, in: source)
            ns.replaceCharacters(in: NSRange(location: match.location + match.length - tail, length: tail), with: String(closer))
            ns.replaceCharacters(in: NSRange(location: match.location, length: openerLength(match, in: source)), with: String(opener))
        }
        return ns as String
    }

    /// `text` with each spoiler replaced by `placeholder`, for plain-text
    /// summaries (VoiceOver, snippets) that must not carry the hidden words.
    public static func redacted(_ text: String, placeholder: String = "spoiler") -> String {
        let found = matches(in: text)
        guard !found.isEmpty else { return text }
        let ns = NSMutableString(string: text)
        for match in found.reversed() { ns.replaceCharacters(in: match, with: placeholder) }
        return ns as String
    }

    /// The whole-match ranges (UTF-16) of the spoilers in `text`, outside code.
    public static func spans(in text: String) -> [NSRange] { matches(in: text) }

    /// Whether `text`, cut off where it ends, has more `>!` openers than `!<`
    /// closers: a cut there would split a spoiler.
    public static func endsInsideSpoiler(_ text: String) -> Bool {
        func count(_ tokens: [String]) -> Int {
            tokens.reduce(0) { $0 + text.components(separatedBy: $1).count - 1 }
        }
        return count([">!", "&gt;!"]) > count(["!<", "!&lt;"])
    }

    /// Whether `text` holds at least one spoiler.
    public static func contains(_ text: String) -> Bool {
        (text.contains("!<") || text.contains("!&lt;")) && !matches(in: text).isEmpty
    }

    /// Whether the `>!` at the first opener of `lines[index]` is closed by a
    /// `!<` later in that line or in the lines below it, up to a blank line. A
    /// line that opens a spoiler this way is not a quote.
    public static func closes(in lines: [String], from index: Int) -> Bool {
        guard lines.indices.contains(index) else { return false }
        var line = Substring(lines[index])
        guard let open = firstOpener(in: line) else { return false }
        line = line[open...]
        var cursor = index
        while true {
            if line.contains("!<") || line.contains("!&lt;") { return true }
            cursor += 1
            guard lines.indices.contains(cursor),
                  !lines[cursor].trimmingCharacters(in: .whitespaces).isEmpty else { return false }
            line = Substring(lines[cursor])
        }
    }

    private static func firstOpener(in line: Substring) -> Substring.Index? {
        let candidates = [">!", "&gt;!"].compactMap { line.range(of: $0)?.upperBound }
        return candidates.min()
    }

    private static func openerLength(_ match: NSRange, in text: String) -> Int {
        let ns = text as NSString
        return ns.substring(with: NSRange(location: match.location, length: 1)) == ">" ? 2 : 5
    }

    private static func closerLength(_ match: NSRange, in text: String) -> Int {
        let ns = text as NSString
        return ns.substring(with: NSRange(location: match.location + match.length - 1, length: 1)) == "<" ? 2 : 5
    }

    /// The whole-match ranges of the spoilers in `text`, outside code.
    private static func matches(in text: String) -> [NSRange] {
        guard text.contains("!<") || text.contains("!&lt;") else { return [] }
        let whole = NSRange(text.startIndex..., in: text)
        let code = codeRanges(in: text)
        let ns = text as NSString
        return pattern.matches(in: text, range: whole).map(\.range).filter { match in
            if match.location > 0, ns.character(at: match.location - 1) == 0x5C { return false }
            let last = match.location + match.length - 1
            return !code.contains { NSLocationInRange(match.location, $0) || NSLocationInRange(last, $0) }
        }
    }

    /// Fenced blocks, indented code and inline code spans.
    private static func codeRanges(in text: String) -> [NSRange] {
        let ns = text as NSString
        var ranges: [NSRange] = []
        var inFence = false
        var previousBlank = true
        var previousIndented = false
        var location = 0
        for line in text.components(separatedBy: "\n") {
            let length = (line as NSString).length
            let range = NSRange(location: location, length: length)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                ranges.append(range)
                previousIndented = false
            } else if inFence {
                ranges.append(range)
            } else {
                let indented = (line.hasPrefix("    ") || line.hasPrefix("\t")) && (previousBlank || previousIndented)
                if indented { ranges.append(range) }
                previousIndented = indented
            }
            previousBlank = trimmed.isEmpty
            location += length + 1
        }
        let whole = NSRange(location: 0, length: ns.length)
        ranges += inlineCode.matches(in: text, range: whole).map(\.range)
        return ranges
    }

    // MARK: Rendered text

    /// Strips the markers from a parsed body and tags what lay between each
    /// pair with `SpoilerAttribute`. Returns the number of spoilers.
    public static func tag(_ text: AttributedString) -> (text: AttributedString, count: Int) {
        var out = text
        var offsets: [(open: Int, close: Int)] = []
        var open: Int?
        for (offset, character) in out.characters.enumerated() {
            if character == opener {
                open = offset
            } else if character == closer, let start = open {
                if offset > start + 1 { offsets.append((start, offset)) }
                open = nil
            }
        }
        func index(_ offset: Int) -> AttributedString.Index {
            out.characters.index(out.characters.startIndex, offsetBy: offset)
        }
        // Back to front, so earlier offsets stay valid.
        for (number, pair) in offsets.enumerated().reversed() {
            out[index(pair.open + 1)..<index(pair.close)][SpoilerAttribute.self] = number
            out.removeSubrange(index(pair.close)..<index(pair.close + 1))
            out.removeSubrange(index(pair.open)..<index(pair.open + 1))
        }
        // Any marker left over has no partner (the parser consumed its other end).
        while let stray = out.characters.firstIndex(where: { $0 == opener || $0 == closer }) {
            out.removeSubrange(stray..<out.characters.index(after: stray))
        }
        return (out, offsets.count)
    }

    /// `full` (as `tag` returns it) with each spoiler hidden behind its label,
    /// except those in `revealing`, whose text stays, set off by a tint. In an
    /// `interactive` body the label, and the text of a revealed spoiler that is
    /// not already a link, carries a link that `index(of:)` reads back: a tap on
    /// it toggles that spoiler, and being a link run, never reaches the row.
    public static func apply(_ full: AttributedString, revealing: Set<Int> = [], interactive: Bool = false) -> AttributedString {
        var spans: [Int: (lower: Int, upper: Int)] = [:]
        var offset = 0
        for run in full.runs {
            let length = full.characters.distance(from: run.range.lowerBound, to: run.range.upperBound)
            if let number = run[SpoilerAttribute.self] {
                let span = spans[number] ?? (offset, offset)
                spans[number] = (min(span.lower, offset), max(span.upper, offset + length))
            }
            offset += length
        }
        guard !spans.isEmpty else { return full }

        var out = full
        func index(_ offset: Int) -> AttributedString.Index {
            out.characters.index(out.characters.startIndex, offsetBy: offset)
        }
        for (number, span) in spans.sorted(by: { $0.key > $1.key }) {
            let range = index(span.lower)..<index(span.upper)
            if revealing.contains(number) {
                #if canImport(SwiftUI)
                out[range].swiftUI.backgroundColor = Color.gray.opacity(0.2)
                #endif
                if interactive, let url = link(number) {
                    // A link inside the spoiler keeps its own destination.
                    let plain = out[range].runs.filter { $0.link == nil }.map(\.range)
                    for part in plain { out[part].link = url }
                }
            } else {
                out.replaceSubrange(range, with: hiddenLabel(number, interactive: interactive))
            }
        }
        return out
    }

    private static func hiddenLabel(_ number: Int, interactive: Bool) -> AttributedString {
        var chip = AttributedString(label)
        #if canImport(Darwin)
        chip.inlinePresentationIntent = .stronglyEmphasized
        #endif
        #if canImport(SwiftUI)
        chip.swiftUI.foregroundColor = Color.secondary
        chip.swiftUI.backgroundColor = Color.gray.opacity(0.35)
        #endif
        if interactive { chip.link = link(number) }
        return chip
    }

    private static func link(_ number: Int) -> URL? { URL(string: "\(scheme)://spoiler/\(number)") }

    /// The spoilers a rendered body's links point at, in order, once each.
    public static func numbers(in text: AttributedString) -> [Int] {
        var seen: [Int] = []
        for run in text.runs {
            if let url = run.link, let number = index(of: url), !seen.contains(number) { seen.append(number) }
        }
        return seen
    }

    /// The spoiler a label's or revealed text's link toggles.
    public static func index(of url: URL) -> Int? {
        url.scheme == scheme ? Int(url.lastPathComponent) : nil
    }
}
