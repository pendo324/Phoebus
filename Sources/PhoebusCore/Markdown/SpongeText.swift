import Foundation

/// Apollo's "SpongeText" composer option, titled "Highlight sOmE TeXt" (the
/// title is itself an example of the transform), with accessibility
/// identifier `option-spongetext` and analytics key `spongeText`.
///
/// It alternates letter case across the selection, the mocking-SpongeBob
/// meme, and refuses without a selection, with its own error copy.
public enum SpongeText {
    /// The menu title, which doubles as a worked example.
    public static let menuTitle = "Highlight sOmE TeXt"

    /// Verbatim error when nothing is selected.
    public static let noSelectionMessage =
        "The SpongeText option requires you to select some text beforehand so it has something to apply it to, so try selecting some text!"

    /// Alternates case across `text`.
    ///
    /// Alternation is by ABSOLUTE CHARACTER INDEX - spaces and
    /// punctuation advance it like any other character - starting
    /// lowercase at index 0.
    ///
    /// The menu title is its own worked example, so the rule reproduces it
    /// exactly:
    ///
    ///     "some text" -> "sOmE TeXt"
    ///
    /// Note the capital T at index 5, immediately after the space at index 4:
    /// skipping non-letters when advancing would yield "sOmE tExT", as would
    /// per-word resetting.
    public static func transform(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for (index, character) in text.enumerated() {
            result.append(contentsOf: index.isMultiple(of: 2)
                ? String(character).lowercased()
                : String(character).uppercased())
        }
        return result
    }
}
