import SwiftUI
import PhoebusCore

/// Renders a post/comment body that may be arbitrarily long. A single
/// SwiftUI `Text` stops drawing past a certain rendered height inside a
/// `List` row while still reporting its full height, so a very long body
/// (seen with ~11,590 characters) pushes everything below it off-screen.
///
/// The body is split on blank lines and rendered as one `Text` per paragraph
/// in a `VStack`. `AttributedString` styling is preserved since
/// `RedditMarkdown` already separates blocks with blank lines.
public struct LongBodyText: View {
    let text: String
    let lineLimit: Int?

    public init(_ text: String, lineLimit: Int? = nil) {
        self.text = text
        self.lineLimit = lineLimit
    }

    /// Paragraph splitting is skipped below this length, so short bodies render
    /// as exactly one `Text`. Well under the ~1200-2400 char range where the
    /// failure appears.
    private static let splitThreshold = 800

    public var body: some View {
        // A collapsed body (`lineLimit` set) must stay ONE `Text`:
        // splitting it would apply the limit to each paragraph
        // separately and show N times as many lines as asked for.
        if let lineLimit {
            Text(RedditMarkdown.render(text)).lineLimit(lineLimit)
        } else if text.count < Self.splitThreshold {
            // Its full height, so a list row never squeezes it to its
            // first lines when something below it grows.
            Text(RedditMarkdown.render(text))
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(BodyParagraphs.split(text).enumerated()), id: \.offset) { _, paragraph in
                    Text(RedditMarkdown.render(paragraph))
                        // Each paragraph takes its full height; without
                        // this, a list row squeezes some to one "..." line.
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Blockquotes render as indented blocks,
                        // matching Apollo's composer preview and
                        // Reddit's upright (not italic) blockquote
                        // style. Applied here rather than in
                        // `RedditMarkdown`, which is Foundation-only
                        // and can't use `NSParagraphStyle` indents.
                        .apolloBlockQuoteIndent(RedditMarkdown.isBlockQuote(paragraph))
                }
            }
        }
    }
}


private extension View {
    /// Indents a blockquote paragraph with a 2pt leading rule, approximating
    /// Apollo's grey indented block.
    @ViewBuilder
    func apolloBlockQuoteIndent(_ isQuote: Bool) -> some View {
        if isQuote {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 2)
                self
            }
            .padding(.leading, 4)
        } else {
            self
        }
    }
}
