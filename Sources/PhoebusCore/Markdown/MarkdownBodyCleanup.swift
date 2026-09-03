import Foundation

/// Reborn's markdown body cleanup, in two parts:
///
///  1. **#405**: Reddit's editor encodes a deliberately blank line as a
///     paragraph holding only a zero-width space, written as the HTML
///     entity `&#x200B;` (or `&#8203;`, or the raw U+200B character), which
///     would otherwise show up as literal text in the body.
///
///  2. **#482 / #1050**: simply deleting the entity leaves the empty
///     paragraph behind, so the body ends up with three blank lines where
///     the site shows one. The now-blank line is removed together with one
///     separator, restoring the normal paragraph gap.
///
/// Applied to the raw markdown source rather than an attributed string.
public enum MarkdownBodyCleanup {
    /// The three spellings stripped, in order. `&#x200b;` is matched
    /// case-insensitively.
    static let zeroWidthEntities = ["&#x200b;", "&#8203;", "\u{200B}"]

    /// Strips zero-width spaces and collapses the empty paragraphs they
    /// leave, then trims trailing whitespace.
    public static func clean(_ body: String) -> String {
        // Cheap bail-out: no allocation when the body has neither an entity nor a
        // raw zero-width character.
        guard body.contains("&#") || body.contains("\u{200B}") else { return body }

        var text = body
        for needle in zeroWidthEntities {
            text = deleteAllOccurrences(of: needle, in: text)
        }
        return trimTrailingWhitespace(text)
    }

    /// Removes every occurrence of `needle`, collapsing any paragraph a
    /// deletion leaves blank.
    static func deleteAllOccurrences(of needle: String, in text: String) -> String {
        var scalars = Array(text)
        let target = Array(needle.lowercased())
        guard !target.isEmpty else { return text }

        var index = 0
        while index + target.count <= scalars.count {
            let slice = scalars[index..<(index + target.count)]
            guard String(slice).lowercased() == needle.lowercased() else {
                index += 1
                continue
            }
            scalars.removeSubrange(index..<(index + target.count))
            collapseEmptyParagraph(&scalars, at: index)
            // The collapse can delete text before `index`; clamp.
            index = min(index, scalars.count)
        }
        return String(scalars)
    }

    /// After a zero-width deletion at `location`, drops the paragraph it
    /// leaves behind when nothing else sits on that line.
    ///
    /// Only paragraph-level blanks are collapsed. A zero-width space on a
    /// hard-line-break line (`"A\nZWSP\nB"`) just loses the character, so a
    /// blank line the author forced that way survives as `"A\n\nB"` (#482).
    static func collapseEmptyParagraph(_ scalars: inout [Character], at location: Int) {
        let length = scalars.count
        guard location <= length else { return }

        // Bounds of the line that held the entity, excluding newlines.
        var start = location
        while start > 0 && scalars[start - 1] != "\n" { start -= 1 }
        var end = location
        while end < length && scalars[end] != "\n" { end += 1 }

        // The line must now be blank (spaces/tabs only).
        for i in start..<end where scalars[i] != " " && scalars[i] != "\t" { return }

        let atStart = (start == 0)
        let atEnd = (end == length)
        let separatorBefore = start >= 2 && scalars[start - 1] == "\n" && scalars[start - 2] == "\n"
        let separatorAfter = end + 1 < length && scalars[end] == "\n" && scalars[end + 1] == "\n"

        let deletion: Range<Int>
        if separatorAfter && (separatorBefore || atStart) {
            // "A\n\n<blank>\n\nB" -> "A\n\nB"   /   "<blank>\n\nB" -> "B"
            deletion = start..<(end + 2)
        } else if separatorBefore && atEnd {
            // "A\n\n<blank>" -> "A"
            deletion = (start - 2)..<end
        } else if atStart && atEnd {
            // The whole body was just the entity.
            deletion = 0..<length
        } else {
            // Bounded by single newlines (hard breaks): keep the blank.
            return
        }
        scalars.removeSubrange(deletion)
    }

    /// Trims trailing whitespace/newlines, so whitespace a stripped
    /// entity exposed at the end does not survive.
    static func trimTrailingWhitespace(_ text: String) -> String {
        var scalars = Array(text)
        while let last = scalars.last, last.isWhitespace || last.isNewline {
            scalars.removeLast()
        }
        return String(scalars)
    }
}
