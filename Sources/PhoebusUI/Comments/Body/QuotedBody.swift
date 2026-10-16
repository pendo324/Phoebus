import SwiftUI
import PhoebusCore

/// A markdown body drawn one run at a time: ordinary text as `run` draws it,
/// each quoted run (`QuoteBlocks`) with a bar and indent. Bodies with no quote
/// are exactly `run(text)`, so a caller's font and layout carry over unchanged.
struct QuotedBody<Run: View>: View {
    private let blocks: [QuoteBlock]
    private let run: (String) -> Run

    init(_ text: String, @ViewBuilder run: @escaping (String) -> Run) {
        blocks = QuoteBlocks.split(text)
        self.run = run
    }

    var body: some View {
        if blocks.count == 1, blocks[0].depth == 0 {
            run(blocks[0].text)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    Group {
                        if block.depth == 0 {
                            run(block.text)
                        } else {
                            QuoteBar(depth: block.depth) { run(block.text) }
                        }
                    }
                    // Quotes inside quotes touch, so the outer bar runs on.
                    .padding(.top, index == 0 || (block.depth > 0 && blocks[index - 1].depth > 0) ? 0 : 10)
                }
            }
        }
    }
}

/// A quote's body: a thin grey bar per level of nesting down its left edge and
/// the text indented beside it in the secondary colour, as Apollo and Reddit
/// draw it. `RedditMarkdown` is Foundation-only and can't carry a paragraph
/// indent in the string, so the bar is laid out here.
struct QuoteBar<Content: View>: View {
    let depth: Int
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(0..<depth, id: \.self) { _ in
                Rectangle()
                    .fill(.secondary)
                    .frame(width: 2)
            }
            content
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .fixedSize(horizontal: false, vertical: true)
    }
}
