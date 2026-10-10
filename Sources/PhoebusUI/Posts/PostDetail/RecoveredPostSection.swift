import SwiftUI
import PhoebusCore

/// Phoebus-only "Recover Removed Posts": a removed post's archived title,
/// body, link and author from Arctic Shift, gated by the Deleted Comments
/// mode (see `RemovedPostRecoveryTrigger`) and drawn in its recovered style.
struct RecoveredPostSection: View {
    let post: RedditPost

    @Setting(DeletedCommentsSettings.self) private var deletedComments
    @Environment(\.apolloTheme) private var apolloTheme
    @Environment(\.colorScheme) private var colorScheme

    private enum Phase: Equatable {
        case idle, loading, failed
        case loaded(RecoveredPostDisplay)
    }

    @State private var phase: Phase = .idle
    @State private var revealed = false

    private var trigger: RemovedPostRecoveryTrigger { RemovedPostRecoveryTrigger(mode: deletedComments.mode) }
    private var reason: DeletedCommentReason { RemovedPostClassifier.reason(for: post) }

    var body: some View {
        if trigger != .none, RemovedPostClassifier.isRemoved(post) {
            content
                .task(id: trigger == .automatic) {
                    if trigger == .automatic { await load() }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle, .loading:
            if trigger == .onTap {
                Button {
                    Task { await load() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                        Text("Show Original Post")
                        if phase == .loading { ProgressView().controlSize(.small) }
                    }
                    .apolloFont(size: 15, weight: .semibold)
                    .foregroundStyle(apolloTheme.color(.accent) ?? .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(phase == .loading)
                .accessibilityIdentifier("postDetail.showOriginalPost")
            }
        case .failed:
            // Silent in Always mode; Passive asked, so it says so.
            if trigger == .onTap {
                Text("Couldn't recover the original post")
                    .apolloFont(size: 13)
                    .foregroundStyle(Color.apolloSecondaryText(colorScheme: colorScheme, themeColors: apolloTheme))
                    .accessibilityIdentifier("postDetail.recoveredPostUnavailable")
            }
        case .loaded(let display):
            if trigger == .automatic, deletedComments.tapToReveal, !revealed {
                Button { revealed = true } label: {
                    DeletedReasonChip(label: reason.displayLabel)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("postDetail.recoveredPostReveal")
            } else {
                recovered(display)
            }
        }
    }

    private func recovered(_ display: RecoveredPostDisplay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label("Recovered from archive", systemImage: "clock.arrow.circlepath")
                    .apolloFont(size: 13, weight: .semibold)
                    .foregroundStyle(Color.apolloSecondaryText(colorScheme: colorScheme, themeColors: apolloTheme))
                Spacer(minLength: 0)
                DeletedReasonChip(label: reason.displayLabel)
            }
            if let title = display.title {
                Text(title)
                    .apolloFont(size: 17, weight: .semibold)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(Color.apolloPrimaryText(colorScheme: colorScheme, themeColors: apolloTheme))
            }
            if let author = display.author {
                Text("by \(author)")
                    .apolloFont(size: 13, weight: .semibold)
                    .foregroundStyle(Color.apolloSecondaryText(colorScheme: colorScheme, themeColors: apolloTheme))
            }
            if let body = display.body {
                InlineMediaBodyView(body, linkContext: .body)
                    .apolloFont(size: PostDetailHeader.bodyFontSize)
                    .foregroundStyle(Color.apolloPrimaryText(colorScheme: colorScheme, themeColors: apolloTheme))
            }
            if let url = display.url {
                LinkPreviewCard(url: url, context: .body, fallbackTitle: display.title ?? post.title)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(DeletedCommentHighlight.color(for: reason)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("postDetail.recoveredPost")
    }

    /// At most one request per post: the client caches every answer.
    private func load() async {
        guard phase == .idle || phase == .failed else { return }
        phase = .loading
        let archived = try? await ArcticShiftClient.fetchArchivedPost(id: post.id)
        if let archived, let display = RecoveredPostDisplay(archived: archived, live: post) {
            phase = .loaded(display)
        } else {
            phase = .failed
        }
    }
}
