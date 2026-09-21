import SwiftUI
import PhoebusCore

// Conformance is declared here rather than in PhoebusCore, like
// `VoteStateStore` in `PostVoting.swift`, so the controller stays
// Combine-free and its state machine can be smoke-tested on Linux.
extension AISummaryController: @MainActor ObservableObject {}

/// One inline AI summary card, as Apollo draws it in a thread.
///
/// Apollo shows a "Discussion so far" card under the post and another
/// above the comments, each collapsed to a single tappable line that
/// expands in place.
///
/// Structure follows Apollo's attributed-text builder: a single text node
/// (title, "  ·  " plus a status subtitle, trailing chevron, then the body
/// once expanded). See `AISummaryCard` for the per-state strings.
struct AISummaryCardView: View {
    let kind: AISummaryCard.Kind
    let state: AISummaryCard.State
    let provider: AIProvider
    /// Number of comments the discussion summary read; 0 for a post
    /// card, which omits it from the caption.
    var sourceCount: Int = 0
    @Binding var expanded: Bool
    let onTap: () -> Void

    @Environment(\.apolloTheme) private var apolloTheme

    private var accent: Color { apolloTheme.color(.accent) ?? .accentColor }

    var body: some View {
        if state != .none {
            Button(action: handleTap) {
                VStack(alignment: .leading, spacing: 8) {
                    titleLine
                    if expanded {
                        let body = AISummaryCard.expandedBody(kind: kind, state: state)
                        if !body.isEmpty {
                            Text(body)
                                .font(.callout)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        // The trust caption, shown only for a ready summary: it stops the summary
                        // being "mistaken for the author's own words" and says whether the text
                        // left the device.
                        if case .ready = state {
                            Text(AISummaryCard.attribution(for: provider, sourceCount: sourceCount))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                // Apollo's card insets: inner (12,14,12,14) and outer (8,12,8,12), a 12pt
                // radius, an accent fill at 10% and a 0.5pt accent border at 24%. The card
                // spans the list's 15pt inset plus a 12pt outer margin.
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(0.10)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(accent.opacity(0.24), lineWidth: 0.5))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(state == .empty ? "" : "Double tap to expand or collapse")
            .accessibilityIdentifier("aiSummary.\(kind.accessibilitySuffix)")
        }
    }

    /// Title + "  ·  " subtitle, as one attributed line.
    ///
    /// Glyph, two spaces, the `.headline` (17pt semibold) title in the accent,
    /// then "  ·  " and the status in `.footnote` (13pt) secondary. The idle card
    /// has no chevron and no spread. The discussion card's glyph is
    /// `text.bubble.fill`, the post card's `sparkles`.
    private var glyphName: String {
        kind == .discussion ? "text.bubble.fill" : "sparkles"
    }

    private var titleLine: some View {
        HStack(spacing: 0) {
            (
                Text(Image(systemName: glyphName))
                + Text("  ")
                + Text(kind.title).font(.headline)
                + subtitleText
            )
            .foregroundStyle(accent)
            Spacer(minLength: 0)
        }
        // Collapsed idle/loading/empty cards clamp to one line so a
        // long title plus subtitle cannot wrap.
        .lineLimit(AISummaryCard.clampsToOneLine(state: state, expanded: expanded) ? 1 : nil)
    }

    /// The "  ·  <status>" tail, empty when the card is expanded or
    /// the state carries no subtitle.
    private var subtitleText: Text {
        guard let subtitle = AISummaryCard.collapsedSubtitle(for: state), !expanded else {
            return Text("")
        }
        return Text("  ·  \(subtitle)")
            .font(.footnote)
            .foregroundColor(.secondary)
    }

    private func handleTap() {
        // A terminal "Nothing to summarize" card is not interactive.
        guard state != .empty else { return }
        if case .tapToSummarize = state {
            onTap()
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
    }

    /// VoiceOver reads the title plus the current body and announces
    /// the collapsed state, rather than the title glyphs alone.
    private var accessibilityLabel: String {
        if state == .empty {
            return "\(kind.title). Nothing to summarize."
        }
        let spoken: String
        switch state {
        case .ready(let summary): spoken = summary
        case .error(let message): spoken = message
        case .loading: spoken = "Summarizing"
        default: spoken = ""
        }
        return expanded ? "\(kind.title). \(spoken)" : "\(kind.title), collapsed"
    }
}

private extension AISummaryCard.Kind {
    var accessibilitySuffix: String {
        switch self {
        case .post: return "post"
        case .link: return "link"
        case .postAndLink: return "postAndLink"
        case .discussion: return "discussion"
        }
    }
}
