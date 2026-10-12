import SwiftUI
import PhoebusCore

/// A feed row's info row with the author's flair. Subviews: the author, the
/// flair, the stats, and optionally trailing controls pinned to the right
/// edge. The flair sits after the name when everything fits at its natural
/// width, else on its own line under the row (`FeedAuthorFlair.placement`),
/// so neither the name nor the stats give up room for it.
struct InfoRowFlairLayout: Layout {
    var spacing: CGFloat = 10
    /// Between the row and a flair moved below it.
    var lineSpacing: CGFloat = 4

    struct Measured {
        var author: CGSize
        var flair: CGSize
        var stats: CGSize
        var trailing: CGSize
        /// What follows the flair: the stats, and the trailing controls
        /// `spacing` after them.
        var restWidth: CGFloat
        var rowHeight: CGFloat
    }

    func makeCache(subviews: Subviews) -> Measured? { nil }

    func updateCache(_ cache: inout Measured?, subviews: Subviews) { cache = nil }

    /// Natural sizes, measured once per layout.
    private func measure(_ subviews: Subviews, _ cache: inout Measured?) -> Measured? {
        if let cache { return cache }
        guard subviews.count >= 3 else { return nil }
        let author = subviews[0].sizeThatFits(.unspecified)
        let flair = subviews[1].sizeThatFits(.unspecified)
        let stats = subviews[2].sizeThatFits(.unspecified)
        let trailing = subviews.count > 3 ? subviews[3].sizeThatFits(.unspecified) : .zero
        let measured = Measured(author: author, flair: flair, stats: stats, trailing: trailing,
                                restWidth: stats.width + (trailing.width > 0 ? spacing + trailing.width : 0),
                                rowHeight: max(author.height, stats.height, trailing.height))
        cache = measured
        return measured
    }

    private func placement(_ m: Measured, width: CGFloat) -> FeedAuthorFlair.Placement {
        FeedAuthorFlair.placement(authorWidth: m.author.width, flairWidth: m.flair.width, restWidth: m.restWidth,
                                  spacing: spacing, available: width)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Measured?) -> CGSize {
        guard let m = measure(subviews, &cache) else { return .zero }
        let width = proposal.width ?? (m.author.width + spacing + m.flair.width + spacing + m.restWidth)
        switch placement(m, width: width) {
        case .inline: return CGSize(width: width, height: max(m.rowHeight, m.flair.height))
        case .below: return CGSize(width: width, height: m.rowHeight + lineSpacing + m.flair.height)
        }
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Measured?) {
        guard let m = measure(subviews, &cache) else { return }
        let width = bounds.width
        let place = placement(m, width: width)
        let rowHeight = place == .inline ? max(m.rowHeight, m.flair.height) : m.rowHeight
        let midY = bounds.minY + rowHeight / 2
        let authorWidth = place == .inline ? m.author.width
            : FeedAuthorFlair.authorWidthBelow(authorWidth: m.author.width, restWidth: m.restWidth,
                                               spacing: spacing, available: width)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: midY), anchor: .leading,
                          proposal: Self.proposal(authorWidth, natural: m.author))
        var x = bounds.minX + authorWidth + spacing
        if place == .inline {
            subviews[1].place(at: CGPoint(x: x, y: midY), anchor: .leading, proposal: .unspecified)
            x += m.flair.width + spacing
        } else {
            // A flair wider than the row truncates at the row's width.
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY + rowHeight + lineSpacing), anchor: .topLeading,
                              proposal: Self.proposal(min(m.flair.width, width), natural: m.flair))
        }
        let trailingX = bounds.maxX - m.trailing.width
        let statsWidth = max(0, min(m.stats.width, (subviews.count > 3 ? trailingX - spacing : bounds.maxX) - x))
        subviews[2].place(at: CGPoint(x: x, y: midY), anchor: .leading,
                          proposal: Self.proposal(statsWidth, natural: m.stats))
        if subviews.count > 3 {
            subviews[3].place(at: CGPoint(x: trailingX, y: midY), anchor: .leading, proposal: .unspecified)
        }
    }

    /// A subview given its whole natural width is proposed nothing, so it
    /// takes its ideal size: proposing that same width as a number can
    /// still truncate its text on rounding.
    private static func proposal(_ width: CGFloat, natural: CGSize) -> ProposedViewSize {
        width >= natural.width - 0.01 ? .unspecified : ProposedViewSize(width: width, height: natural.height)
    }
}

/// The author's flair in a feed row: the comment header's pill, at the row's
/// size, opening the flair alert on a tap. The tap wins over the row's own
/// open-the-post tap, as the author's name does.
struct FeedAuthorFlairPill: View {
    let post: RedditPost
    let text: String
    let textColor: Color?
    let fill: Color?
    var size: CGFloat = 12.5
    @State private var shownFlair: FlairInfo?

    var body: some View {
        CommentFlairPill(text: text, parts: post.authorFlairRichtext, textColor: textColor, fill: fill,
                         size: size, role: .postMeta)
            .contentShape(Rectangle())
            .highPriorityGesture(TapGesture().onEnded {
                FlairAlert.present(FlairInfo(kind: .user, text: text, parts: post.authorFlairRichtext,
                                             subreddit: post.subreddit), in: $shownFlair)
            })
            .accessibilityIdentifier("feed.postRow.authorFlair")
            .flairAlert($shownFlair)
    }
}
