import SwiftUI
import PhoebusCore

/// The Action Menus preview: a sample row whose ••• opens the same menu the
/// app shows, built by the same view, in the layout being edited with the
/// hidden actions gone. Touching and holding the row opens it too, for the
/// menus that open on hold. Phoebus-only; neither Apollo nor Reborn previews
/// a menu.
///
/// Every action in the menu does nothing: the menus are drawn with a handler
/// that ignores what is chosen, and the rows that act on their own (Share,
/// the marks, the moderator screens) are drawn inert, so nothing is sent,
/// saved or opened. The row is the real `PostRow` or `CommentRow`, inert like
/// the other previews' rows; a menu button laid over its ••• (whose frame the
/// row reports) and a hold layer are the only live parts. The feed and
/// Moderator (Subreddit) menus hang off a nav bar, so their card shows a bar
/// with that button instead of a row.
///
/// "Your post" and "Moderator" show the rows that only appear in those cases.
struct ActionMenuPreview: View {
    let context: ActionMenuContext
    let repository: RedditRepository

    @Setting(GeneralSettings.self) private var general
    @Setting(ApolloAISettingsStore.storage) private var aiSettings
    @Setting(FloatingPostTabsSettingsStore.storage) private var floatingTabsSettings
    @State private var yourItem = false
    @State private var moderator = false
    /// Bumped when a layout changes, so the open menu is built again.
    @State private var revision = 0
    @State private var post = SettingsPreviewSample.post(imageURL: SettingsPreviewImage.url)
    @State private var node = SettingsPreviewSample.thread().flatMap { $0.flattenedAll() }[1]
    @State private var depthColors = CommentsThemeStore.effectiveHexes(theme: ThemeStore.load()).map(Color.init(hex:))

    private var isModerator: Bool { ActionMenuPreviewPolicy.isModerator(context, moderator: moderator) }
    private var signedInUsername: String { ActionMenuPreviewPolicy.signedInUsername(yourItem: yourItem) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toggles
            sample
            Text("Tap ••• to open the menu" + (ActionMenuPreviewPolicy.opensOnHold(context) ? ", or touch and hold the row" : "")
                 + ". Nothing you choose here does anything.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .onReceive(NotificationCenter.default.publisher(for: .apolloActionMenuLayoutsChanged)) { _ in revision += 1 }
        .accessibilityIdentifier("actionMenus.preview")
    }

    // MARK: - Switches

    @ViewBuilder
    private var toggles: some View {
        let kinds = ActionMenuPreviewPolicy.toggles(for: context)
        if !kinds.isEmpty {
            HStack(spacing: 16) {
                ForEach(kinds, id: \.self) { kind in
                    Toggle(ActionMenuPreviewPolicy.title(of: kind, in: context), isOn: binding(kind))
                        .toggleStyle(.switch)
                        .font(.system(size: 13))
                        .fixedSize()
                        .accessibilityIdentifier(kind == .yourItem ? "actionMenus.preview.yourItem" : "actionMenus.preview.moderator")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private func binding(_ kind: ActionMenuPreviewPolicy.Toggle) -> Binding<Bool> {
        switch kind {
        case .yourItem: return $yourItem
        case .moderator: return $moderator
        }
    }

    // MARK: - The sample

    @ViewBuilder
    private var sample: some View {
        switch context {
        case .feed, .moderatorSubreddit:
            navBar
        case .post, .postDetail, .moderatorPost:
            let large = general.postDisplayStyle == .large
            live(PostRow(post: post, repository: repository, displayStyle: general.postDisplayStyle,
                         onSubredditTap: {}, onAuthorTap: {})
                    .environment(\.postRowHeroHeight, 110)
                    .padding(large ? EdgeInsets() : EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)),
                 label: "Preview: a sample post.")
        case .comment, .moderatorComment:
            live(CommentRow(node: node, depthColors: depthColors, repository: repository, isNew: false,
                            onToggleCollapse: {}, onReplyTapped: {}, onQuoteTapped: {})
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(EdgeInsets(top: 10, leading: CommentRowMetrics.leadingInset(depth: 0), bottom: 11, trailing: 16)),
                 label: "Preview: a sample comment.")
        }
    }

    /// The row, inert, with the menu button over its ••• and the hold layer
    /// over the row.
    private func live<Row: View>(_ row: Row, label: String) -> some View {
        row
            .inertSettingsPreview(label: label)
            .coordinateSpace(name: SettingsPreviewMenuFrame.space)
            .overlayPreferenceValue(SettingsPreviewMenuFrame.self) { frame in
                ZStack(alignment: .topLeading) {
                    if ActionMenuPreviewPolicy.opensOnHold(context) {
                        Color.clear
                            .contentShape(Rectangle())
                            .contextMenu { menu }
                            .accessibilityHidden(true)
                    }
                    if let frame {
                        Menu { menu } label: {
                            Color.clear.frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .frame(width: 44, height: 44)
                        .offset(x: frame.midX - 22, y: frame.midY - 22)
                        .accessibilityLabel("Open the menu")
                        .accessibilityIdentifier("actionMenus.preview.menuButton")
                    }
                }
                .id(revision)
            }
    }

    /// The feed's and the subreddit moderator menu's bar, with its •••.
    private var navBar: some View {
        HStack {
            Text("r/\(SettingsPreviewSample.subreddit)")
                .font(.system(size: 17, weight: .semibold))
            Spacer()
            Group {
                if context == .feed {
                    ApolloOverflowMenu(systemImage: "option-more",
                                       composerRow: FeedOverflowMenu.composerRow(feedState) { _ in },
                                       rows: FeedOverflowMenu.rows(feedState) { _ in })
                } else {
                    Menu { menu } label: { Image(systemName: "ellipsis.circle").font(.system(size: 22)) }
                }
            }
            .id(revision)
            .accessibilityIdentifier("actionMenus.preview.menuButton")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - The menus

    @ViewBuilder
    private var menu: some View {
        switch context {
        case .post:
            PostActionMenuContent(post: post, repository: repository, signedInUsername: signedInUsername,
                                  isModerator: isModerator, isPreview: true) { _ in }
        case .postDetail:
            PostDetailActionMenuContent(facts: detailFacts, repository: repository, isPreview: true) { _ in }
        case .comment, .moderatorComment:
            CommentActionMenuContent(facts: commentFacts, isPreview: true, showsMain: context == .comment) { _ in }
        case .moderatorPost:
            PostModeratorMenuContent(
                ids: ActionMenuPlan.moderatorPost(author: post.author, signedInUsername: signedInUsername,
                                                  isModerator: true, includesNotes: true),
                post: post, repository: repository, state: PostModeratorMenuState(distinguished: false, stickied: false, locked: false),
                markIdentifierPrefix: "postDetail.moderator", isPreview: true) { _ in }
        case .moderatorSubreddit:
            ModeratorSubredditMenuContent(subreddit: SettingsPreviewSample.subreddit, repository: repository, isPreview: true) { _ in }
        case .feed:
            EmptyView()
        }
    }

    private var feedState: FeedOverflowState {
        FeedOverflowState(subreddit: SettingsPreviewSample.subreddit, multiredditPath: nil, isSubscribed: false,
                          isFavorite: false, isCompact: general.postDisplayStyle == .compact,
                          canLeaveQuarantine: false, isModerator: isModerator, canCopyMultireddit: false)
    }

    private var detailFacts: PostDetailMenuFacts {
        PostDetailMenuFacts(
            post: post, markedPost: post, signedInUsername: signedInUsername, isModerator: isModerator,
            isOwnPost: yourItem, isPostDeleted: false, summariesEnabled: aiSettings.summariesEnabled,
            floatingTabsEnabled: floatingTabsSettings.enabled, isSaved: false, isMuted: false,
            anyChildCollapsed: false, isKeptInFloatingTab: false, liveActivityRunning: false,
            deletedCommentsRecoveryActive: false,
            moderator: PostModeratorMenuState(distinguished: false, stickied: false, locked: false))
    }

    private var commentFacts: CommentMenuFacts {
        CommentMenuFacts(comment: node.comment, policy: CommentInteractionPolicy(comment: node.comment, isOwn: yourItem),
                         canShareAsImage: true, isModerator: isModerator, isSaved: false,
                         isMuted: false, isDistinguished: false, isStickied: false)
    }
}
