import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

/// Lightweight Reddit-markdown renderer for post selftext and comment
/// bodies. Swift's `AttributedString(markdown:)` handles standard
/// CommonMark well, but Reddit's dialect adds bare `/r/subreddit` and
/// `/u/username` mentions and `^superscript`, which CommonMark doesn't
/// parse. This pre/post-processes the source text for those before
/// handing off to AttributedString's parser for everything else.
///
/// `AttributedString.MarkdownParsingOptions` only exists in Apple's
/// full Foundation, not Linux's FoundationEssentials, so this is
/// `#if canImport(Darwin)`-gated: the real app gets full rendering,
/// the Linux smoke test falls back to a linkified-but-unparsed string.
public enum RedditMarkdown {
    /// Rendered bodies by source text. SwiftUI calls `render` from view
    /// bodies, so without this every redraw would re-parse every visible body.
    private static let cache = RenderCache()

    public static func render(_ raw: String) -> AttributedString {
        if let hit = cache.value(for: raw) { return hit }
        let rendered = renderUncached(raw)
        cache.store(rendered, for: raw)
        return rendered
    }

    private final class RenderCache: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String: AttributedString] = [:]
        private static let limit = 400

        func value(for key: String) -> AttributedString? {
            lock.lock(); defer { lock.unlock() }
            return entries[key]
        }

        func store(_ value: AttributedString, for key: String) {
            lock.lock(); defer { lock.unlock() }
            // Cleared wholesale rather than tracked LRU: the next
            // screenful refills it at the cost of one parse each.
            if entries.count >= Self.limit { entries.removeAll(keepingCapacity: true) }
            entries[key] = value
        }
    }

    static func renderUncached(_ raw: String) -> AttributedString {
        // Strip Reddit's zero-width-space blank lines before anything
        // else parses or measures them, and collapse the empty
        // paragraph each leaves behind. See `MarkdownBodyCleanup`.
        let cleaned = MarkdownBodyCleanup.clean(raw)
        let quoted = normalizeBlockquotes(cleaned)
        let tabled = rewriteTables(quoted)
        let expanded = expandRedditInlineSyntax(tabled)
        let preprocessed = linkifySubredditsAndUsers(expanded)
        #if canImport(Darwin)
        // `.full`, not `.inlineOnlyPreservingWhitespace`: `.inlineOnly*`
        // leaves block constructs (headings, lists, blockquotes) as
        // raw text, which Reddit comments use constantly. `.full`
        // understands blocks but discards the newlines between them,
        // so the structure is rebuilt from presentation intents by
        // `applyBlockFormatting` below.
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let parsed = try? AttributedString(markdown: preprocessed, options: options) {
            return applyBlockFormatting(parsed)
        }
        #endif
        return AttributedString(preprocessed)
    }

    #if canImport(Darwin)
    /// Rebuilds the visual structure `.full` parsing knows about but
    /// doesn't render: paragraph breaks, heading emphasis, list bullets.
    /// `AttributedString(markdown:)` records these as
    /// `presentationIntent` runs and flattens the text; each intent
    /// kind is mapped back to the formatting Apollo shows for it.
    static func applyBlockFormatting(_ input: AttributedString) -> AttributedString {
        var output = AttributedString()
        var previousBlockID: Int?
        var previousMarkedListItemID: Int?

        for run in input.runs {
            let intents = run.presentationIntent?.components ?? []
            let blockID = intents.first?.identity
            var piece = AttributedString(input[run.range])

            // Separate blocks with a blank line, matching how Reddit
            // renders paragraphs/headings/list items as distinct rows.
            if let blockID, blockID != previousBlockID, !output.characters.isEmpty {
                // List items are rows of one list, not separate
                // blocks: a blank line between each would look like
                // double-spaced paragraphs.
                let isListItem = intents.contains { component in
                    if case .listItem = component.kind { return true }
                    return false
                }
                output.append(AttributedString(isListItem ? "\n" : "\n\n"))
            }
            previousBlockID = blockID

            // Inline code: the parser marks these with the `.code`
            // inline intent but leaves them unanswered by default.
            let isCodeBlock = intents.contains { component in
                if case .codeBlock = component.kind { return true }
                return false
            }
            if run.inlinePresentationIntent?.contains(.code) == true || isCodeBlock {
                styleAsCode(&piece, trimTrailingNewline: isCodeBlock)
            }
            // Strikethrough (`~~text~~`), same story.
            if run.inlinePresentationIntent?.contains(.strikethrough) == true {
                piece.strikethroughStyle = .single
            }

            for component in intents {
                switch component.kind {
                case .header(let level):
                    // Bold reads as a heading at comment scale; the
                    // level is preserved in the parsed intent for any
                    // future size mapping.
                    piece.inlinePresentationIntent = .stronglyEmphasized
                    _ = level
                case .unorderedList, .orderedList:
                    break
                case .listItem(let ordinal):
                    // The list marker isn't part of the parsed text,
                    // so it's prepended, but only once per list item:
                    // a run boundary inside the item (bold/italic/link
                    // span) carries the same listItem intent, which
                    // naively emitted a bullet mid-sentence. Keyed on
                    // block identity so only the item's first run gets a marker.
                    guard blockID != previousMarkedListItemID else { break }
                    previousMarkedListItemID = blockID
                    let isOrdered = intents.contains { component in
                        if case .orderedList = component.kind { return true }
                        return false
                    }
                    piece = AttributedString(isOrdered ? "\(ordinal). " : "• ") + piece
                case .blockQuote:
                    // Styled, not re-prefixed with a literal "> ", as
                    // an indented grey block matching Apollo's own
                    // composer preview and Reddit's guide (explicitly
                    // not italic). `AttributedString` can't carry a
                    // leading rule or background band per paragraph or
                    // a paragraph indent (that needs
                    // `NSMutableParagraphStyle`, UIKit/AppKit-only);
                    // `LongBodyText` applies the indent per paragraph
                    // instead, where SwiftUI's own padding can do it.
                    // See `isBlockQuote`.
                    break
                case .codeBlock:
                    break
                default:
                    break
                }
            }
            output.append(piece)
        }
        return output.characters.isEmpty ? input : output
    }

    /// Apollo's code style: 14pt monospaced in #ACB2BF on a #282B33 band
    /// behind each line's text.
    static func styleAsCode(_ piece: inout AttributedString, trimTrailingNewline: Bool) {
        if trimTrailingNewline, piece.characters.last == "\n" {
            piece = AttributedString(piece.characters.dropLast().map(String.init).joined())
        }
        #if canImport(SwiftUI)
        piece.swiftUI.font = .system(size: 14, design: .monospaced)
        piece.swiftUI.foregroundColor = Color(red: 172 / 255, green: 178 / 255, blue: 191 / 255)
        piece.swiftUI.backgroundColor = Color(red: 40 / 255, green: 43 / 255, blue: 51 / 255)
        #endif
    }
    #endif


    /// Rewrites Reddit-only inline syntax the Markdown parser doesn't
    /// know about. The parser already handles bold, italic,
    /// bold-italic, partial-word emphasis, strikethrough, inline code,
    /// escapes, HTML entities, hard breaks, thematic breaks and
    /// ordered lists. Two leak raw syntax into the rendered body:
    ///
    ///   `^(text)` / `^word`  ->  rendered as literal carets
    ///   `>!text!<`           ->  rendered as literal `>!` and `!<`
    ///
    /// Superscript maps to Unicode superscript characters where they
    /// exist; the Unicode block has no superscript for most letters,
    /// so anything unmappable keeps its plain form.
    ///
    /// Spoilers are unwrapped to their text; Apollo hides them behind
    /// a tap, which needs a custom run attribute this doesn't have yet.
    public static func expandRedditInlineSyntax(_ text: String) -> String {
        var result = spoilerPattern.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: "$1"
        )
        result = superscriptParenPattern.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "$1"
        )
        // Bare `^word` form. Applied after the parenthesised one so a
        // `^(...)` is never half-consumed.
        result = superscriptWordPattern.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "$1"
        )
        return result
    }

    /// `>!spoiler!<`, Reddit's own spelling.
    private static let spoilerPattern = try! NSRegularExpression(
        pattern: #">!(.+?)!<"#, options: [.dotMatchesLineSeparators]
    )
    /// `^(superscript)`.
    private static let superscriptParenPattern = try! NSRegularExpression(
        pattern: #"\^\(([^)]*)\)"#
    )
    /// `^word`: a single word can be superscripted with just a caret.
    private static let superscriptWordPattern = try! NSRegularExpression(
        pattern: #"\^(\S+)"#
    )

    /// Rewrites a Markdown table into aligned monospaced rows. The
    /// parser has no table support and its pipe rows otherwise fall
    /// apart into separate paragraphs.
    ///
    /// Reddit's guide defines tables as pipe-separated columns with a
    /// dash marker row carrying per-column alignment (leading colon =
    /// left, trailing = right, both = centre).
    ///
    /// An approximation: Apollo draws a laid-out table, which needs a Grid
    /// view this string-to-AttributedString path can't express. Alignment
    /// markers are honoured in padding.
    public static func rewriteTables(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        var index = 0
        while index < lines.count {
            guard isTableRow(lines[index]),
                  index + 1 < lines.count,
                  isTableMarkerRow(lines[index + 1]) else {
                out.append(lines[index])
                index += 1
                continue
            }
            var block: [[String]] = [tableCells(lines[index])]
            let alignments = tableAlignments(lines[index + 1])
            var cursor = index + 2
            while cursor < lines.count, isTableRow(lines[cursor]) {
                block.append(tableCells(lines[cursor]))
                cursor += 1
            }
            out.append(contentsOf: renderTable(block, alignments: alignments))
            index = cursor
        }
        return out.joined(separator: "\n")
    }

    static func isTableRow(_ line: String) -> Bool {
        line.contains("|") && !line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The dashes-and-colons row directly under the header.
    public static func isTableMarkerRow(_ line: String) -> Bool {
        let cells = tableCells(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let t = cell.trimmingCharacters(in: .whitespaces)
            return !t.isEmpty && t.allSatisfy { $0 == "-" || $0 == ":" } && t.contains("-")
        }
    }

    static func tableCells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    enum ColumnAlignment { case left, right, centre }

    static func tableAlignments(_ markerRow: String) -> [ColumnAlignment] {
        tableCells(markerRow).map { cell in
            let t = cell.trimmingCharacters(in: .whitespaces)
            switch (t.hasPrefix(":"), t.hasSuffix(":")) {
            case (true, true): return .centre
            case (false, true): return .right
            default: return .left
            }
        }
    }

    static func renderTable(_ rows: [[String]], alignments: [ColumnAlignment]) -> [String] {
        let columnCount = rows.map(\.count).max() ?? 0
        guard columnCount > 0 else { return [] }

        // Not fenced as a code block: a fence renders verbatim, which stops
        // every cell's own markdown from being parsed (bold ledes, links). Each
        // row is emitted as its own markdown line instead (header cell bolded,
        // remaining cells joined by an en-dash), keeping links and emphasis live.
        var out: [String] = []
        for (index, row) in rows.enumerated() {
            let cells = (0..<columnCount).map { i -> String in
                i < row.count ? row[i].trimmingCharacters(in: .whitespaces) : ""
            }
            .filter { !$0.isEmpty }
            guard !cells.isEmpty else { continue }

            if index == 0 {
                // Header row: cells are column names, so labels rather
                // than content, bolded together on one line.
                let header = cells.joined(separator: " · ")
                // A header cell can itself contain emphasis; wrapping
                // already-bold text in ** would produce literal
                // asterisks, so only plain headers are bolded.
                out.append(header.contains("*") ? header : "**\(header)**")
            } else {
                // Body row: first cell is the subject, the rest its
                // detail, joined with an em-dash.
                out.append(cells.joined(separator: " — "))
            }
            // Blank line between rows so each becomes its own
            // paragraph; without it the parser folds consecutive lines
            // into one run-on block.
            out.append("")
        }
        if out.last == "" { out.removeLast() }
        return out
    }

    static func pad(_ text: String, to width: Int, alignment: ColumnAlignment) -> String {
        let deficit = max(0, width - text.count)
        switch alignment {
        case .left: return text + String(repeating: " ", count: deficit)
        case .right: return String(repeating: " ", count: deficit) + text
        case .centre:
            let left = deficit / 2
            return String(repeating: " ", count: left) + text
                + String(repeating: " ", count: deficit - left)
        }
    }

    /// Whether a source paragraph is a blockquote. Used by
    /// `LongBodyText` to indent it, since this Foundation-only module
    /// can't apply `NSParagraphStyle`. Checking the source line works
    /// since `normalizeBlockquotes` already canonicalized every
    /// Reddit spelling to a leading `>`.
    public static func isBlockQuote(_ paragraph: String) -> Bool {
        normalizeQuoteLine(paragraph.trimmingCharacters(in: .whitespaces))
            .hasPrefix(">")
    }

    /// Normalizes Reddit's blockquote spellings into ones the Markdown
    /// parser recognizes as `.blockQuote`.
    ///
    /// Two real spellings the strict parser rejects:
    ///
    ///  1. `&gt;` instead of `>`. Reddit's API returns comment bodies
    ///     HTML-escaped in several paths.
    ///  2. `>text` with no space. Reddit accepts it; CommonMark
    ///     requires the space before the content.
    ///
    /// Both are rewritten to canonical `> text`, per line. Nesting
    /// (`>>`) is preserved by only inserting a space after the last
    /// marker in a run.
    public static func normalizeBlockquotes(_ body: String) -> String {
        guard body.contains(">") || body.contains("&gt;") else { return body }
        return body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { normalizeQuoteLine(String($0)) }
            .joined(separator: "\n")
    }

    /// Rewrites one line's leading quote markers, if it has any.
    public static func normalizeQuoteLine(_ line: String) -> String {
        // Leading whitespace is allowed before a quote marker and must
        // be preserved, since an indented quote is still a quote.
        let leading = line.prefix { $0 == " " || $0 == "\t" }
        var rest = String(line.dropFirst(leading.count))

        var markers = 0
        while true {
            if rest.hasPrefix("&gt;") {
                rest.removeFirst(4); markers += 1
            } else if rest.hasPrefix(">") {
                rest.removeFirst(1); markers += 1
            } else {
                break
            }
            // A marker may be followed by a space that belongs to it.
            if rest.hasPrefix(" ") { rest.removeFirst() }
        }
        guard markers > 0 else { return line }
        // `>` on its own line is a legitimate empty quote line; do not
        // append a trailing space to it.
        let marker = String(repeating: ">", count: markers)
        return rest.isEmpty ? leading + marker : leading + marker + " " + rest
    }

    /// Turns arbitrary comment/post text into a markdown blockquote
    /// (`> ` prefix per line, including blank lines), with a trailing
    /// blank line so a reply typed after starts outside the quote.
    public static func asBlockquote(_ text: String) -> String {
        let quoted = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> \($0)" }
            .joined(separator: "\n")
        return quoted + "\n\n"
    }

    /// Turns bare `/r/name` and `/u/name` (and `r/name`/`u/name`)
    /// mentions into real markdown links to reddit.com, so
    /// AttributedString's markdown parser renders them as tappable
    /// links like Apollo does, instead of plain text. Mentions already
    /// inside a markdown link, as its text or its target (`[here](/r/x)`,
    /// common in sidebars and rules), are left alone so the link isn't
    /// wrapped again.
    public static func linkifySubredditsAndUsers(_ text: String) -> String {
        guard text.contains("r/") || text.contains("u/") else { return text }
        var result = text
        for (regex, prefix) in mentionPatterns {
            let whole = NSRange(result.startIndex..., in: result)
            let links = existingLink.matches(in: result, range: whole).map(\.range)
            // Back to front, so earlier ranges stay valid.
            for match in regex.matches(in: result, range: whole).reversed() {
                guard !links.contains(where: { NSIntersectionRange($0, match.range).length > 0 }),
                      let fullRange = Range(match.range, in: result),
                      let nameRange = Range(match.range(at: 1), in: result) else { continue }
                let name = String(result[nameRange])
                let display = String(result[fullRange])
                result.replaceSubrange(fullRange, with: "[\(display)](\(prefix)\(name))")
            }
        }
        return result
    }

    private static let mentionPatterns: [(NSRegularExpression, String)] = [
        (try! NSRegularExpression(pattern: #"(?<![\w/])/?r/([A-Za-z0-9_]+)"#), "https://reddit.com/r/"),
        (try! NSRegularExpression(pattern: #"(?<![\w/])/?u/([A-Za-z0-9_-]+)"#), "https://reddit.com/u/"),
    ]
    private static let existingLink = try! NSRegularExpression(pattern: #"\[[^\]]*\]\([^)]*\)"#)
}

#if DEBUG
public extension RedditMarkdown {
    /// Renders a spread of Reddit-spec samples and prints the result. Unused
    /// by shipping code: exercising the real parser means calling it from the
    /// app's `init` behind an env var, since `render()` only parses Markdown
    /// under `#if canImport(Darwin)`.
    static func dumpSpecProbe() {
        let cases: [(String, String)] = [
            ("superscript paren", "reddit ^(and be reddited)"),
            ("superscript word", "just to ^reddit and be"),
            ("spoiler", "just to >!reddit and be reddited!<."),
            ("strikethrough", "to ~~love~~ reddit"),
            ("inline code", "Curabitur: `gravida` molestie"),
            ("bold-italic", "Lorem ***dolor*** sit"),
            ("underscore bold", "Lorem __dolor__ sit"),
            ("partial word", "vul*pu*ta**te** ex"),
            ("table", "| a | b |\n|---|---|\n| 1 | 2 |"),
            ("thematic break", "before\n\n---\n\nafter"),
            ("ordered paren", "1) first\n2) second"),
            ("hard break spaces", "line one  \nline two"),
            ("escape", "Lorem\n\\- consectetur"),
            ("html entity", "a &amp; b &mdash; c"),
        ]
        for (name, src) in cases {
            let out = String(render(src).characters)
            print("SPEC \(name): [\(out.replacingOccurrences(of: "\n", with: "\\n"))]")
        }
    }
}
#endif
