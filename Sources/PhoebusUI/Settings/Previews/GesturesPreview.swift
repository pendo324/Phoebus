import SwiftUI
import PhoebusCore

/// The Gestures & Haptics preview: a sample row of the screen being edited,
/// wrapped in the app's own row swipe, with a strip under it that names each
/// side's actions. Phoebus-only; neither Apollo nor Reborn previews a swipe.
///
/// The row is the real cell (`PostRow`, `CommentRow`, `ProfileCommentRow` or
/// the inbox's `MessageRow`) and the swipe is the real
/// `ProgressiveSwipeRowModifier`, configured from the same settings, so it
/// reveals the short then the long action at the Long Swipe Trigger Point with
/// the real icons, colours and haptic ticks. Letting go runs nothing: the row
/// springs back and a label names the action that would have fired
/// (`SwipePreviewPolicy.release`). The swipe is confined to the row's area, so
/// the page swipes work everywhere else.
struct GesturesPreview: View {
    let repository: RedditRepository
    @Binding var screen: SwipeActionScreen
    let settings: SwipeActionSettings

    @Setting(NavigationGestureSettingsStore.storage) private var navigation
    @Setting(GeneralSettings.self) private var general
    @Environment(\.colorScheme) private var colorScheme
    @State private var post = SettingsPreviewSample.post(imageURL: SettingsPreviewImage.url)
    @State private var message = SettingsPreviewSample.message()
    @State private var node = SettingsPreviewSample.thread().flatMap { $0.flattenedAll() }[1]
    @State private var depthColors = CommentsThemeStore.effectiveHexes(theme: ThemeStore.load()).map(Color.init(hex:))
    @State private var releaseLabel: String?
    @State private var releaseToken = 0

    private var segment: Binding<SwipePreviewSegment> {
        Binding(get: { SwipePreviewSegment(screen: screen) },
                set: { screen = $0.screen(keeping: screen) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("Preview screen", selection: segment) {
                ForEach(SwipePreviewSegment.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .accessibilityIdentifier("gestures.preview.screen")

            VStack(alignment: .leading, spacing: 0) {
                row
                strip
                releaseCaption
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preview: a sample \(screen.displayName) row. "
                + SwipePreviewPolicy.summary(settings: settings, navigation: navigation))
        }
        .accessibilityIdentifier("gestures.preview")
    }

    // MARK: - The row

    /// Inert like the other previews' rows (no taps, holds or menus; they see
    /// `isSettingsPreview`), except for the swipe, which is the point.
    private var row: some View {
        rowContent
            .environment(\.isSettingsPreview, true)
            .allowsHitTesting(false)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Takes the touch, so the swipe has a hit view under it (and a drag that
            // starts on an unpinned card still scrolls the list).
            .contentShape(Rectangle())
            .onTapGesture {}
            .apolloConfinedSwipeActions(settings: settings) { released($0) }
            .clipped()
            .accessibilityIdentifier("gestures.preview.row")
    }

    @ViewBuilder
    private var rowContent: some View {
        switch screen {
        case .posts, .profilePosts:
            let large = general.postDisplayStyle == .large
            PostRow(post: post, repository: repository, displayStyle: general.postDisplayStyle,
                    onSubredditTap: {}, onAuthorTap: {})
                .environment(\.postRowHeroHeight, 110)
                .padding(large ? EdgeInsets() : EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        case .comments:
            CommentRow(node: node, depthColors: depthColors, repository: repository, isNew: false,
                       onToggleCollapse: {}, onReplyTapped: {}, onQuoteTapped: {})
                .fixedSize(horizontal: false, vertical: true)
                .padding(EdgeInsets(top: 10, leading: CommentRowMetrics.leadingInset(depth: 0), bottom: 11, trailing: 16))
        case .profileComments:
            ProfileCommentRow(comment: node.comment, repository: repository)
                .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        case .inbox:
            MessageRow(message: message, repository: repository, isNew: true)
                .padding(EdgeInsets(top: 10, leading: 11, bottom: 10, trailing: 17))
        }
    }

    private func released(_ action: SwipeAction) {
        releaseLabel = SwipePreviewPolicy.release(action)
        releaseToken += 1
        let token = releaseToken
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard token == releaseToken else { return }
            withAnimation(.easeOut(duration: 0.2)) { releaseLabel = nil }
        }
    }

    // MARK: - The strip

    private var strip: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(SwipeRowPolicy.Side.allCases, id: \.self) { side in
                sideBlock(side)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    private func sideBlock(_ side: SwipeRowPolicy.Side) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(side == .left ? "Left (drag right)" : "Right (drag left)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            switch SwipePreviewPolicy.strip(for: side, settings: settings, navigation: navigation) {
            case .actions(let short, let long):
                VStack(alignment: .leading, spacing: 4) {
                    chip(short)
                    chip(long)
                }
                triggerTrack(short: short, long: long)
            case .pageSwipe(let text):
                Label(text, systemImage: side == .left ? "chevron.left" : "chevron.right")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            case .none:
                Text("None")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ action: SwipeAction) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().fill(action == .none ? Color.gray.opacity(0.4) : ProgressiveSwipeRowModifier.color(for: action))
                if action != .none {
                    StockIcon(ProgressiveSwipeRowModifier.iconName(for: action, subject: nil, votes: VoteStateStore.shared),
                              size: CGSize(width: 13, height: 13))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 22, height: 22)
            Text(action.displayName)
                .font(.system(size: 13))
                .lineLimit(1)
        }
    }

    /// The drag distance as a bar: grey up to the commit point, the short
    /// action's colour up to the Long Swipe Trigger Point, then the long one's.
    private func triggerTrack(short: SwipeAction, long: SwipeAction) -> some View {
        let commit = SwipeCommitPolicy.shortThreshold
        let trigger = SwipeCommitPolicy.longThreshold(fraction: navigation.longSwipeTriggerPoint.fraction)
        let total = trigger + commit
        func tint(_ action: SwipeAction) -> Color {
            action == .none ? Color.gray.opacity(0.4) : ProgressiveSwipeRowModifier.color(for: action)
        }
        return GeometryReader { proxy in
            let scale = proxy.size.width / total
            HStack(spacing: 0) {
                Color.gray.opacity(0.3).frame(width: commit * scale)
                tint(short).frame(width: (trigger - commit) * scale)
                tint(long)
            }
            .clipShape(Capsule())
        }
        .frame(height: 5)
        .padding(.top, 2)
        .accessibilityHidden(true)
    }

    private var releaseCaption: some View {
        Text(releaseLabel ?? "Swipe the row to try it")
            .font(.system(size: 12, weight: releaseLabel == nil ? .regular : .semibold))
            .foregroundStyle(releaseLabel == nil ? Color.secondary : Color.apolloAccent)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
            .accessibilityIdentifier("gestures.preview.release")
    }
}
