import SwiftUI
import PhoebusCore

/// A message body as Reddit markdown, drawn as one `Text` per run of
/// paragraphs rather than a single `Text`.
///
/// A single `Text` is one layer, and a very long message (~10,000
/// characters) is taller than the largest layer the system will draw
/// and redraws as a whole on every scroll frame. Short bodies stay one
/// `Text`. Quoted runs get a bar and indent (`QuotedBody`).
struct ChunkedMarkdownText: View {
    let text: String

    init(_ body: String) {
        text = body
    }

    var body: some View {
        QuotedBody(text) { ChunkedRun(text: $0) }
    }

    private struct ChunkedRun: View {
        let text: String
        @State private var reveal = SpoilerReveal()
        @Environment(\.bodyTextColor) private var textColor

        var body: some View {
            let count = RedditMarkdown.spoilerCount(in: text)
            if count > 0 {
                chunked(RedditMarkdown.render(text, codeScale: 1, revealing: reveal.revealing(base: 0, count: count), interactive: true)
                    .colouringRevealedSpoilers(textColor), spoilers: count)
                    .opensSpoilers($reveal)
            } else {
                chunked(RedditMarkdown.render(text), spoilers: 0)
            }
        }

        @ViewBuilder
        private func chunked(_ rendered: AttributedString, spoilers: Int) -> some View {
            let chunks = ChunkedMarkdownText.chunks(of: rendered)
            if chunks.count == 1, let only = chunks.first {
                Text(only).spoilerActions(for: only, reveal: $reveal, total: spoilers)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(chunks.indices, id: \.self) { index in
                        Text(chunks[index])
                            // Each chunk at its full height so none draws over the next.
                            .fixedSize(horizontal: false, vertical: true)
                            .spoilerActions(for: chunks[index], reveal: $reveal, total: spoilers)
                    }
                }
            }
        }
    }

    /// Characters per chunk, roughly: split at the paragraph break
    /// after this many.
    static let chunkLength = 1200

    /// The most a chunk holds when no paragraph break comes: a wall of text
    /// is cut at a line break or space instead.
    static let maxChunkLength = 2000

    /// Splits at paragraph breaks (a blank line), keeping the break with
    /// the chunk before it so the spacing between paragraphs survives.
    static func chunks(of text: AttributedString) -> [AttributedString] {
        let characters = text.characters
        guard characters.count > chunkLength else { return [text] }
        var result: [AttributedString] = []
        var start = characters.startIndex
        var offset = 0
        for end in BodyParagraphs.chunkEnds(of: String(characters), softLength: chunkLength, hardLength: maxChunkLength) {
            let endIndex = characters.index(start, offsetBy: end - offset)
            result.append(AttributedString(text[start..<endIndex]))
            start = endIndex
            offset = end
        }
        return result
    }
}

