import Foundation

/// Splits a post/comment body into paragraphs.
///
/// Lives in `PhoebusCore` so the smoke test can reach it. A single SwiftUI
/// `Text` inside a `List` row silently stops drawing past a certain rendered
/// height while still reporting its full height, so a long body leaves a
/// blank row that pushes the action row and comments off-screen (2400
/// characters was already blank). See `LongBodyText`.
public enum BodyParagraphs {
    /// Splits on blank lines, as `RedditMarkdown` separates the blocks it emits.
    /// Never returns an empty array: a body with no paragraph breaks (or no
    /// content) comes back as itself.
    public static func split(_ body: String) -> [String] {
        let parts = body
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .newlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? [body] : parts
    }
}
