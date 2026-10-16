import Foundation

/// A run of a body's lines at one quote depth, with the `>` markers removed.
public struct QuoteBlock: Equatable, Sendable {
    /// 0 for ordinary text, 1 for `>`, 2 for `>>`.
    public let depth: Int
    public let text: String

    public init(depth: Int, text: String) {
        self.depth = depth
        self.text = text
    }
}

/// Splits a Reddit body into its quoted and unquoted runs so each can be drawn
/// with the quote's bar and indent. The Markdown parser records a quote only as
/// a presentation intent on flattened text, so without this a quote reads as
/// plain paragraphs.
public enum QuoteBlocks {
    /// Bodies with no quote come back as one depth-0 block holding the original text.
    public static func split(_ body: String) -> [QuoteBlock] {
        guard body.contains(">") || body.contains("&gt;") else { return [QuoteBlock(depth: 0, text: body)] }
        var runs: [(depth: Int, lines: [String])] = []
        var inFence = false
        var previousDepth = 0

        for line in body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            var depth = 0
            var content = line
            if isFence(line) {
                inFence.toggle()
            } else if !inFence {
                (depth, content) = parse(line)
                // A line without a marker right under a quote line is part of it.
                if depth == 0, previousDepth > 0, !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    depth = previousDepth
                }
            }
            previousDepth = depth
            if let last = runs.last, last.depth == depth {
                runs[runs.count - 1].lines.append(content)
            } else {
                runs.append((depth, [content]))
            }
        }

        let blocks = runs.compactMap { run -> QuoteBlock? in
            let text = run.lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
            return text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : QuoteBlock(depth: run.depth, text: text)
        }
        guard blocks.contains(where: { $0.depth > 0 }) else { return [QuoteBlock(depth: 0, text: body)] }
        return blocks
    }

    /// A line's quote depth and what follows its markers. Up to three spaces
    /// may precede a marker (four is code); `&gt;` is the spelling the API
    /// returns, and the space after a marker is optional.
    static func parse(_ line: String) -> (depth: Int, content: String) {
        var rest = Substring(line)
        var indent = 0
        while rest.first == " ", indent < 4 { rest.removeFirst(); indent += 1 }
        guard indent < 4 else { return (0, line) }
        var depth = 0
        while true {
            if rest.hasPrefix("&gt;") {
                rest.removeFirst(4)
            } else if rest.first == ">" {
                rest.removeFirst()
            } else {
                break
            }
            depth += 1
            if rest.first == " " { rest.removeFirst() }
        }
        return depth == 0 ? (0, line) : (depth, String(rest))
    }

    private static func isFence(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }
}
