import SwiftUI
import PhoebusCore

/// A message body as Reddit markdown, drawn as one `Text` per run of
/// paragraphs rather than a single `Text`.
///
/// A single `Text` is one layer, and a very long message (~10,000
/// characters) is taller than the largest layer the system will draw
/// and redraws as a whole on every scroll frame. Short bodies stay one
/// `Text`.
struct ChunkedMarkdownText: View {
    let chunks: [AttributedString]

    init(_ body: String) {
        chunks = Self.chunks(of: RedditMarkdown.render(body))
    }

    var body: some View {
        if chunks.count == 1, let only = chunks.first {
            Text(only)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(chunks.indices, id: \.self) { index in
                    Text(chunks[index])
                        // Each chunk at its full height so none draws over the next.
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Characters per chunk, roughly: split at the paragraph break
    /// after this many.
    static let chunkLength = 1200

    /// Splits at paragraph breaks (a blank line), keeping the break with
    /// the chunk before it so the spacing between paragraphs survives.
    static func chunks(of text: AttributedString) -> [AttributedString] {
        let characters = text.characters
        guard characters.count > chunkLength else { return [text] }
        var result: [AttributedString] = []
        var start = characters.startIndex
        var count = 0
        var index = characters.startIndex
        while index < characters.endIndex {
            let next = characters.index(after: index)
            count += 1
            if count >= chunkLength, characters[index] == "\n", next < characters.endIndex, characters[next] == "\n" {
                // Through the blank line, so the next chunk starts at
                // its paragraph rather than with an empty line.
                let end = characters.index(after: next)
                result.append(AttributedString(text[start..<end]))
                start = end
                index = end
                count = 0
                continue
            }
            index = next
        }
        if start < characters.endIndex {
            result.append(AttributedString(text[start..<characters.endIndex]))
        }
        return result
    }
}

