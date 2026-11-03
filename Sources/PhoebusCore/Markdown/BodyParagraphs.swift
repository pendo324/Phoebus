import Foundation

/// One `Text`'s worth of a body. `continuesPrevious` marks a piece cut out of
/// the middle of a paragraph (or code block), which is drawn flush against the
/// piece before it instead of after a paragraph gap.
public struct BodyPiece: Equatable, Sendable {
    public let text: String
    public let continuesPrevious: Bool

    public init(text: String, continuesPrevious: Bool) {
        self.text = text
        self.continuesPrevious = continuesPrevious
    }
}

/// Splits a post/comment body into paragraphs.
///
/// Lives in `PhoebusCore` so the smoke test can reach it. A single SwiftUI
/// `Text` inside a `List` row silently stops drawing past a certain rendered
/// height while still reporting its full height, so a long body leaves a
/// blank row that pushes the action row and comments off-screen (2400
/// characters was already blank). See `LongBodyText`.
public enum BodyParagraphs {
    /// The longest piece, in characters. The height a `Text` can draw is
    /// fixed, so what matters is how tall this many characters get at the
    /// largest Text Size.
    public static let maxPieceLength = 1000

    /// Splits on blank lines, as `RedditMarkdown` separates the blocks it emits,
    /// and cuts a paragraph or code block longer than `maxLength` into pieces.
    /// Never returns an empty array: a body with no paragraph breaks (or no
    /// content) comes back as itself.
    public static func split(_ body: String, maxLength: Int = maxPieceLength) -> [String] {
        let parts = pieces(of: body, maxLength: maxLength).map(\.text)
        return parts.isEmpty ? [body] : parts
    }

    /// `split` with each piece's relation to the one before it.
    ///
    /// A blank line inside a fenced code block does not end the piece, and a
    /// block cut for length reopens its fence on the next piece, so the code
    /// keeps its styling. Cuts fall on a line break; a line longer than the
    /// limit is cut after a sentence, else at a space, and not inside a link,
    /// inline code or bold span when another spot is near.
    public static func pieces(of body: String, maxLength: Int = maxPieceLength) -> [BodyPiece] {
        let limit = max(maxLength, 40)
        var result: [BodyPiece] = []
        var lines: [String] = []
        var length = 0
        var startsParagraph = true
        var fence: Fence?

        func emit() {
            let text = lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
            lines = []
            length = 0
            guard !text.isEmpty else { return }
            result.append(BodyPiece(text: text, continuesPrevious: !startsParagraph))
            startsParagraph = false
        }
        func push(_ line: String) {
            lines.append(line)
            length += line.count + 1
        }
        func add(_ line: String) {
            for segment in wrap(line, limit: limit) {
                if !lines.isEmpty, length + segment.count > limit {
                    emit()
                    if let fence { push(fence.marker) }
                }
                push(segment)
            }
        }

        for line in body.components(separatedBy: "\n") {
            if let open = fence {
                if open.closes(line) {
                    fence = nil
                    push(line)
                } else {
                    add(line)
                }
            } else if line.isEmpty {
                emit()
                startsParagraph = true
            } else {
                add(line)
                fence = Fence(opening: line)
            }
        }
        emit()
        return result
    }

    /// Where to end each chunk of already-rendered text, as character offsets,
    /// the last being the text's length. A chunk ends after the first blank
    /// line once it holds `softLength` characters (so paragraphs stay whole),
    /// and at the last line break, else the last space, once it holds
    /// `hardLength`, for a wall of text with no blank line. Rendered text
    /// carries its styling in attributes, so any offset is safe to cut at.
    public static func chunkEnds(of text: String, softLength: Int, hardLength: Int) -> [Int] {
        let characters = Array(text)
        guard characters.count > softLength else { return [characters.count] }
        var ends: [Int] = []
        var start = 0
        var lastLineBreak: Int?
        var lastSpace: Int?
        var index = 0
        while index < characters.count {
            let character = characters[index]
            let count = index - start + 1
            if character == "\n" { lastLineBreak = index + 1 }
            if character == " " { lastSpace = index + 1 }
            var end: Int?
            if count >= softLength, character == "\n", index + 1 < characters.count, characters[index + 1] == "\n" {
                end = index + 2
            } else if count >= hardLength {
                let floor = start + softLength / 2
                end = [lastLineBreak, lastSpace].compactMap { $0 }.first { $0 >= floor } ?? index + 1
            }
            if let end, end < characters.count {
                ends.append(end)
                start = end
                index = end
                lastLineBreak = nil
                lastSpace = nil
                continue
            }
            index += 1
        }
        ends.append(characters.count)
        return ends
    }

    /// A line cut into segments of at most `limit` characters.
    private static func wrap(_ line: String, limit: Int) -> [String] {
        var rest = Array(line)
        guard rest.count > limit else { return [line] }
        var segments: [String] = []
        while rest.count > limit {
            let cut = cutIndex(in: rest, limit: limit)
            segments.append(String(rest[..<cut]))
            var next = cut
            while next < rest.count, rest[next] == " " { next += 1 }
            rest = Array(rest[next...])
        }
        segments.append(String(rest))
        return segments
    }

    /// Where to cut `characters` (longer than `limit`): after the last
    /// sentence end, else at the last space, in the second half of the limit,
    /// preferring a spot that does not open a link, code span or bold run.
    private static func cutIndex(in characters: [Character], limit: Int) -> Int {
        let floor = limit / 2
        let spaces = stride(from: limit, to: floor, by: -1).filter { characters[$0] == " " }
        let sentenceEnds = spaces.filter { characters[$0 - 1] == "." || characters[$0 - 1] == "!" || characters[$0 - 1] == "?" }
        for candidates in [sentenceEnds, spaces] {
            if let cut = candidates.first(where: { isBalanced(characters[..<$0]) }) { return cut }
        }
        return spaces.first ?? limit
    }

    /// No unclosed `[`, inline code or `**` in `prefix`.
    private static func isBalanced(_ prefix: ArraySlice<Character>) -> Bool {
        var brackets = 0
        var ticks = 0
        var stars = 0
        for character in prefix {
            switch character {
            case "[": brackets += 1
            case "]": brackets -= 1
            case "`": ticks += 1
            case "*": stars += 1
            default: break
            }
        }
        return brackets <= 0 && ticks % 2 == 0 && stars % 2 == 0
    }

    /// An open fenced code block (three or more backticks or tildes).
    private struct Fence {
        let character: Character
        let width: Int

        var marker: String { String(repeating: character, count: width) }

        init?(opening line: String) {
            let trimmed = line.drop { $0 == " " }
            guard line.count - trimmed.count <= 3, let first = trimmed.first, first == "`" || first == "~" else { return nil }
            let run = trimmed.prefix { $0 == first }.count
            guard run >= 3 else { return nil }
            // A backtick fence's info string cannot hold a backtick: that is inline code.
            if first == "`", trimmed.dropFirst(run).contains("`") { return nil }
            character = first
            width = run
        }

        func closes(_ line: String) -> Bool {
            let trimmed = line.drop { $0 == " " }
            guard line.count - trimmed.count <= 3 else { return false }
            let run = trimmed.prefix { $0 == character }.count
            return run >= width && trimmed.dropFirst(run).allSatisfy { $0 == " " }
        }
    }
}
