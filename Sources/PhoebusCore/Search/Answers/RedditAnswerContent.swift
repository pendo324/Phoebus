import Foundation

/// One element of the answer's rich text: Reddit's RTJSON (`par`, `text`,
/// `link`, `h`, `list`, `li`, `hr`, `raw`) plus the `ra:*` elements Answers
/// adds. Everything but `e` (the element name) and `c` (children) stays in
/// `attributes`, so an element Phoebus has never seen still decodes.
public struct RedditAnswerNode: Equatable, Sendable {
    public var element: String
    public var children: [RedditAnswerNode]
    public var attributes: [String: JSONValue]

    public init(element: String, children: [RedditAnswerNode] = [], attributes: [String: JSONValue] = [:]) {
        self.element = element
        self.children = children
        self.attributes = attributes
    }

    /// Nil unless `json` is an object.
    public init?(json: JSONValue) {
        guard case .object(var object) = json else { return nil }
        if case .string(let name)? = object.removeValue(forKey: "e") { element = name } else { element = "" }
        if case .array(let items)? = object.removeValue(forKey: "c") {
            children = items.compactMap(RedditAnswerNode.init(json:))
        } else {
            children = []
        }
        attributes = object
    }

    public func string(_ key: String) -> String? {
        if case .string(let value)? = attributes[key] { return value }
        return nil
    }

    public func int(_ key: String) -> Int? {
        if case .number(let value)? = attributes[key] { return Int(value) }
        return nil
    }

    public func bool(_ key: String) -> Bool? {
        if case .bool(let value)? = attributes[key] { return value }
        return nil
    }

    /// `text` and `raw` elements' string.
    public var text: String? { string("t") }

    /// A text element's formatting ranges, `[format, start, length]` in
    /// UTF-16 units.
    public var formatRanges: [(format: Int, start: Int, length: Int)] {
        guard case .array(let ranges)? = attributes["f"] else { return [] }
        return ranges.compactMap { range in
            guard case .array(let parts) = range, parts.count == 3,
                  case .number(let format) = parts[0], case .number(let start) = parts[1],
                  case .number(let length) = parts[2] else { return nil }
            return (Int(format), Int(start), Int(length))
        }
    }

    public static func == (lhs: RedditAnswerNode, rhs: RedditAnswerNode) -> Bool {
        lhs.element == rhs.element && lhs.children == rhs.children && lhs.attributes == rhs.attributes
    }
}

/// The patched document, decoded: the ids Reddit says the answer drew on,
/// the follow-up questions and the rich text.
public struct RedditAnswerDocument: Equatable, Sendable {
    public var commentIDs: [String] = []
    public var postIDs: [String] = []
    public var subredditIDs: [String] = []
    public var followUps: [String] = []
    public var nodes: [RedditAnswerNode] = []

    public init() {}

    public init(json: JSONValue) {
        guard case .object(let root) = json else { return }
        commentIDs = Self.ids(root["comments"])
        postIDs = Self.ids(root["posts"])
        subredditIDs = Self.ids(root["subreddits"])
        if case .array(let questions)? = root["followUps"] {
            followUps = questions.compactMap { question in
                if case .object(let object) = question, case .string(let query)? = object["query"], !query.isEmpty { return query }
                return nil
            }
        }
        if case .object(let richtext)? = root["richtext"], case .array(let items)? = richtext["document"] {
            nodes = items.compactMap(RedditAnswerNode.init(json:))
        }
    }

    private static func ids(_ value: JSONValue?) -> [String] {
        guard case .array(let items)? = value else { return [] }
        return items.compactMap { item in
            if case .object(let object) = item, case .string(let id)? = object["ID"] { return id }
            return nil
        }
    }
}

// MARK: - Render model

public struct AnswerTextStyle: OptionSet, Equatable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let bold = AnswerTextStyle(rawValue: 1)
    public static let italic = AnswerTextStyle(rawValue: 2)
    public static let strikethrough = AnswerTextStyle(rawValue: 4)
    public static let superscript = AnswerTextStyle(rawValue: 8)
    public static let code = AnswerTextStyle(rawValue: 16)
    /// Italic text from an inline quote.
    public static let quoted = AnswerTextStyle(rawValue: 32)

    /// RTJSON's format bit mask: 1 bold, 2 italic, 8 strikethrough,
    /// 32 superscript, 64 inline code. Other bits are ignored.
    static func fromFormat(_ format: Int) -> AnswerTextStyle {
        var style: AnswerTextStyle = []
        if format & 1 != 0 { style.insert(.bold) }
        if format & 2 != 0 { style.insert(.italic) }
        if format & 8 != 0 { style.insert(.strikethrough) }
        if format & 32 != 0 { style.insert(.superscript) }
        if format & 64 != 0 { style.insert(.code) }
        return style
    }
}

/// A numbered citation: an `ra:source` chip pointing at a post or comment.
public struct AnswerCitation: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case post, comment }

    public var number: Int
    /// `t3_…` or `t1_…`.
    public var id: String
    public var kind: Kind
    /// "r/name", when Reddit said.
    public var subreddit: String?
    /// The link just before the chip, when it was a reddit.com link: where the
    /// chip opens.
    public var permalink: URL?

    public init(number: Int, id: String, kind: Kind, subreddit: String? = nil, permalink: URL? = nil) {
        self.number = number
        self.id = id
        self.kind = kind
        self.subreddit = subreddit
        self.permalink = permalink
    }
}

public enum AnswerInline: Equatable, Sendable {
    case text(String, AnswerTextStyle)
    case link(text: String, url: URL?)
    case citation(AnswerCitation)
    case lineBreak
}

/// A post or comment drawn as a card, from a carousel or image card.
public struct AnswerReference: Equatable, Sendable {
    public var id: String
    public var imageURL: URL?

    public init(id: String, imageURL: URL? = nil) {
        self.id = id
        self.imageURL = imageURL
    }
}

public enum AnswerBlock: Equatable, Sendable {
    case paragraph([AnswerInline])
    case heading(level: Int, [AnswerInline])
    case list(ordered: Bool, items: [[AnswerBlock]])
    case quote([AnswerBlock])
    case code(String)
    case rule
    /// `t5_` ids, from `ra:subreddit` and subreddit grids.
    case subreddits([String])
    /// What carousels and image cards degrade to.
    case references(label: String?, [AnswerReference])
}

public struct AnswerThinkingStep: Equatable, Sendable {
    public var title: String
    public var isComplete: Bool

    public init(title: String, isComplete: Bool) {
        self.title = title
        self.isComplete = isComplete
    }
}

public struct AnswerSubreddit: Equatable, Sendable {
    /// `t5_…`.
    public var id: String
    /// "r/name", when the source bar named it.
    public var name: String?
    public var iconURL: URL?

    public init(id: String, name: String? = nil, iconURL: URL? = nil) {
        self.id = id
        self.name = name
        self.iconURL = iconURL
    }
}

/// The answer ready to draw: reasoning steps, blocks, citations and the
/// posts and communities Reddit consulted.
public struct RedditAnswerContent: Equatable, Sendable {
    public var steps: [AnswerThinkingStep] = []
    public var blocks: [AnswerBlock] = []
    public var citations: [AnswerCitation] = []
    /// `t3_` ids from the reasoning's post sources, then the document's posts.
    public var consultedPostIDs: [String] = []
    public var consultedSubreddits: [AnswerSubreddit] = []
    public var followUps: [String] = []

    public init() {}

    public init(document: RedditAnswerDocument) {
        var builder = Builder()
        builder.collectReasoning(document.nodes)
        blocks = builder.blocks(document.nodes)
        steps = builder.steps
        citations = builder.citations
        followUps = document.followUps
        for id in document.postIDs where !builder.postIDs.contains(id) { builder.postIDs.append(id) }
        consultedPostIDs = builder.postIDs
        var subreddits = builder.subreddits
        for id in document.subredditIDs where !subreddits.contains(where: { $0.id == id }) {
            subreddits.append(AnswerSubreddit(id: id))
        }
        consultedSubreddits = subreddits
    }

    /// The step line while streaming: the one in progress, else the last.
    public var thinkingTitle: String? {
        (steps.last(where: { !$0.isComplete }) ?? steps.last)?.title
    }

    public var isThinking: Bool { steps.contains { !$0.isComplete } }

    /// Whether any answer text has arrived.
    public var hasAnswer: Bool { !blocks.isEmpty }

    /// The answer as plain text, for Copy and Share.
    public var plainText: String {
        Self.plain(blocks).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func plain(_ blocks: [AnswerBlock], indent: String = "") -> String {
        var parts: [String] = []
        for block in blocks {
            switch block {
            case .paragraph(let inlines):
                parts.append(indent + plain(inlines))
            case .heading(_, let inlines):
                parts.append(indent + plain(inlines))
            case .list(let ordered, let items):
                var lines: [String] = []
                for (index, item) in items.enumerated() {
                    let marker = ordered ? "\(index + 1). " : "\u{2022} "
                    lines.append(indent + marker + plain(item, indent: "").replacingOccurrences(of: "\n\n", with: "\n"))
                }
                parts.append(lines.joined(separator: "\n"))
            case .quote(let inner):
                parts.append(plain(inner).split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n"))
            case .code(let text):
                parts.append(text)
            case .rule, .subreddits, .references:
                continue
            }
        }
        return parts.joined(separator: "\n\n")
    }

    private static func plain(_ inlines: [AnswerInline]) -> String {
        inlines.map { inline in
            switch inline {
            case .text(let text, _): return text
            case .link(let text, _): return text
            case .citation(let citation): return "[\(citation.number)]"
            case .lineBreak: return "\n"
            }
        }.joined()
    }

    // MARK: Builder

    private struct Builder {
        var steps: [AnswerThinkingStep] = []
        var citations: [AnswerCitation] = []
        var postIDs: [String] = []
        var subreddits: [AnswerSubreddit] = []

        static let inlineElements: Set<String> = ["text", "raw", "link", "ra:source", "ra:inline_quote", "br", ""]

        /// The reasoning block's steps and sources, wherever it sits.
        mutating func collectReasoning(_ nodes: [RedditAnswerNode]) {
            for node in nodes {
                switch node.element {
                case "ra:thinking_step":
                    steps.append(AnswerThinkingStep(title: node.string("title") ?? "", isComplete: node.string("state") == "complete"))
                case "ra:post_source":
                    if let id = node.string("id"), !postIDs.contains(id) { postIDs.append(id) }
                case "ra:subreddit_source_bar":
                    collectSubredditSources(node)
                    collectReasoning(node.children.filter { $0.element != "ra:subreddit_sources" })
                case "ra:reasoning", "ra:post_sources":
                    collectReasoning(node.children)
                default:
                    break
                }
            }
        }

        /// The bar's source ids pair, in order, with its `subreddit_info`.
        mutating func collectSubredditSources(_ bar: RedditAnswerNode) {
            var ids: [String] = []
            func walk(_ nodes: [RedditAnswerNode]) {
                for node in nodes {
                    if node.element == "ra:subreddit_source", let id = node.string("id") { ids.append(id) }
                    walk(node.children)
                }
            }
            walk(bar.children)
            var info: [[String: JSONValue]] = []
            if case .array(let items)? = bar.attributes["subreddit_info"] {
                for item in items { if case .object(let object) = item { info.append(object) } }
            }
            for (index, id) in ids.enumerated() where !subreddits.contains(where: { $0.id == id }) {
                var name: String?
                var icon: URL?
                if info.indices.contains(index) {
                    if case .string(let value)? = info[index]["name"] { name = value }
                    if case .string(let value)? = info[index]["icon_url"] { icon = URL(string: value) }
                }
                subreddits.append(AnswerSubreddit(id: id, name: name, iconURL: icon))
            }
        }

        // MARK: Blocks

        mutating func blocks(_ nodes: [RedditAnswerNode]) -> [AnswerBlock] {
            var result: [AnswerBlock] = []
            var pending: [RedditAnswerNode] = []
            func flush(_ builder: inout Builder) {
                guard !pending.isEmpty else { return }
                let inlines = builder.inlines(pending)
                pending = []
                if inlines.contains(where: { !$0.isBlank }) { result.append(.paragraph(inlines)) }
            }
            for node in nodes {
                if Self.inlineElements.contains(node.element) {
                    pending.append(node)
                    continue
                }
                flush(&self)
                result += block(node)
            }
            flush(&self)
            return result
        }

        private mutating func block(_ node: RedditAnswerNode) -> [AnswerBlock] {
            switch node.element {
            case "par":
                let inlines = inlines(node.children)
                return inlines.contains(where: { !$0.isBlank }) ? [.paragraph(inlines)] : []
            case "h":
                let inlines = inlines(node.children)
                return inlines.contains(where: { !$0.isBlank }) ? [.heading(level: min(max(node.int("l") ?? 3, 1), 6), inlines)] : []
            case "list":
                let items = node.children.map { blocks($0.element == "li" ? $0.children : [$0]) }
                return [.list(ordered: node.bool("o") ?? false, items: items)]
            case "li":
                return [.list(ordered: false, items: [blocks(node.children)])]
            case "blockquote", "ra:block_quote", "ra:block_quote_card":
                return [.quote(blocks(node.children))]
            case "code", "code_block", "codeblock":
                return [.code(Self.rawText(node))]
            case "hr":
                return [.rule]
            case "ra:reasoning", "ra:thinking_step", "ra:post_sources", "ra:post_source",
                 "ra:subreddit_sources", "ra:subreddit_source", "ra:subreddit_source_bar":
                return []
            case "ra:subreddit":
                return node.string("id").map { [.subreddits([$0])] } ?? []
            case "ra:grid":
                let ids = Self.descendants(node, "ra:subreddit").compactMap { $0.string("id") }
                if !ids.isEmpty { return [.subreddits(ids)] }
                return references(in: node, label: node.string("label"))
            case "ra:carousel":
                return references(in: node, label: node.string("label"))
            case "ra:imagecard", "ra:videocard", "ra:post", "ra:product":
                return references(in: node, label: nil)
            default:
                // An element Phoebus doesn't know: its children, never a crash.
                return blocks(node.children)
            }
        }

        /// The posts and comments a media element points at, or its text when
        /// it points at none.
        private mutating func references(in node: RedditAnswerNode, label: String?) -> [AnswerBlock] {
            var found: [AnswerReference] = []
            func walk(_ node: RedditAnswerNode) {
                let id = node.string("entity_id") ?? node.string("id")
                if let id, id.hasPrefix("t3_") || id.hasPrefix("t1_"), !found.contains(where: { $0.id == id }) {
                    found.append(AnswerReference(id: id, imageURL: node.string("src").flatMap(URL.init(string:))))
                }
                node.children.forEach(walk)
            }
            walk(node)
            if !found.isEmpty { return [.references(label: label, found)] }
            return blocks(node.children)
        }

        // MARK: Inlines

        mutating func inlines(_ nodes: [RedditAnswerNode]) -> [AnswerInline] {
            var result: [AnswerInline] = []
            for node in nodes {
                switch node.element {
                case "text", "":
                    result += Self.styledRuns(node.text ?? "", ranges: node.formatRanges)
                    if node.text == nil { result += inlines(node.children) }
                case "raw":
                    if let text = node.text { result.append(.text(text, [])) }
                case "br":
                    result.append(.lineBreak)
                case "link":
                    let label = node.text ?? Self.plainText(node.children)
                    let url = node.string("u").flatMap(URL.init(string:))
                    result.append(.link(text: label.isEmpty ? (url?.absoluteString ?? "") : label, url: url))
                case "ra:source":
                    guard let id = node.string("id"), !id.isEmpty else { continue }
                    result.append(.citation(citation(for: node, id: id, previous: result.last)))
                case "ra:inline_quote":
                    for inline in inlines(node.children) {
                        if case .text(let text, let style) = inline {
                            result.append(.text(text, style.union(.quoted)))
                        } else {
                            result.append(inline)
                        }
                    }
                case "ra:subreddit":
                    if let id = node.string("id") { result.append(.text(id, [])) }
                default:
                    result += inlines(node.children)
                }
            }
            return result
        }

        private mutating func citation(for node: RedditAnswerNode, id: String, previous: AnswerInline?) -> AnswerCitation {
            if let existing = citations.first(where: { $0.id == id }) {
                var repeated = existing
                if case .link(_, let url)? = previous, let url, Self.isReddit(url) { repeated.permalink = url }
                return repeated
            }
            var permalink: URL?
            if case .link(_, let url)? = previous, let url, Self.isReddit(url) { permalink = url }
            let kind: AnswerCitation.Kind = (node.string("type") == "comment" || id.hasPrefix("t1_")) ? .comment : .post
            let citation = AnswerCitation(number: citations.count + 1, id: id, kind: kind,
                                          subreddit: node.string("subreddit_name"), permalink: permalink)
            citations.append(citation)
            return citation
        }

        // MARK: Helpers

        static func isReddit(_ url: URL) -> Bool {
            guard let host = url.host?.lowercased() else { return false }
            return host == "reddit.com" || host.hasSuffix(".reddit.com")
        }

        static func descendants(_ node: RedditAnswerNode, _ element: String) -> [RedditAnswerNode] {
            node.children.flatMap { ($0.element == element ? [$0] : []) + descendants($0, element) }
        }

        static func plainText(_ nodes: [RedditAnswerNode]) -> String {
            nodes.map { ($0.text ?? "") + plainText($0.children) }.joined()
        }

        static func rawText(_ node: RedditAnswerNode) -> String {
            (node.text ?? "") + plainText(node.children)
        }

        /// Splits `text` at the format ranges' edges, each run carrying the
        /// union of the styles covering it.
        static func styledRuns(_ text: String, ranges: [(format: Int, start: Int, length: Int)]) -> [AnswerInline] {
            guard !text.isEmpty else { return [] }
            let utf16 = Array(text.utf16)
            var cuts: Set<Int> = [0, utf16.count]
            for range in ranges where range.length > 0 {
                cuts.insert(min(max(range.start, 0), utf16.count))
                cuts.insert(min(max(range.start + range.length, 0), utf16.count))
            }
            let points = cuts.sorted()
            var runs: [AnswerInline] = []
            for (from, to) in zip(points, points.dropFirst()) where to > from {
                var style: AnswerTextStyle = []
                for range in ranges where range.start <= from && range.start + range.length >= to {
                    style.formUnion(AnswerTextStyle.fromFormat(range.format))
                }
                let run = String(decoding: utf16[from..<to], as: UTF16.self)
                if case .text(let last, let lastStyle)? = runs.last, lastStyle == style {
                    runs[runs.count - 1] = .text(last + run, style)
                } else {
                    runs.append(.text(run, style))
                }
            }
            return runs
        }
    }
}

extension AnswerInline {
    /// Whitespace-only text, which alone doesn't make a paragraph.
    fileprivate var isBlank: Bool {
        if case .text(let text, _) = self { return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return false
    }
}
