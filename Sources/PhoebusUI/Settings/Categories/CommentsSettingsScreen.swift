import SwiftUI
import PhoebusCore

/// Comments: everything about reading a thread, in Apollo's own rows from
/// General's Comments section, Reborn's Comments and Deleted Comments
/// screens: sorting, collapsing, navigation, highlights, removed comments
/// and live threads. The colours and inline images are drill-downs
/// because each has a live preview.
public struct CommentsSettingsScreen: View {
    @Setting(GeneralSettingsStore.storage) private var settings
    @Setting(VoteCountSettings.self) private var voteCounts
    @Setting(OtherDiscussionsSettings.self) private var otherDiscussions
    @Setting(ThreadPositionSettings.self) private var threadPosition
    @Setting(DeletedCommentsSettingsStore.storage) private var deleted
    @State private var commentSortMemoryMode = CommentSortMemoryStore.loadMode()
    /// One-time warning alert when switching into Always mode, which can
    /// slow comment loading.
    @State private var showsSlowdownWarning = false
    /// Re-read on appear: the palette is chosen one screen down.
    @State private var commentsThemeName = ""
    @Environment(\.accountManager) private var accountManager
    @State private var depthColors = CommentsSettingsScreen.currentDepthColors()

    public init() {}

    private static func currentDepthColors() -> [Color] {
        CommentsThemeStore.effectiveHexes(theme: ThemeStore.load()).map(Color.init(hex:))
    }

    public var body: some View {
        SettingsPreviewScreenLayout(screen: .comments) {
            if let repository = accountManager?.repository {
                CommentsPreview(repository: repository, depthColors: depthColors)
            }
        } content: {
            sortingSection
            collapsingSection
            navigationSection
            highlightsSection
            removedCommentsSection
            liveCommentsSection
            displaySection
        }
        .apolloSettingsSearchScroll()
        .navigationTitle(SettingsCategory.comments.title)
        .navigationBarTitleDisplayModeIfAvailable()
        .onAppear {
            depthColors = Self.currentDepthColors()
            commentsThemeName = CommentsThemeStore.overridePaletteName
                ?? (ThemeStore.load().commentPaletteName ?? "Theme's Own")
        }
    }

    private var sortingSection: some View {
        Section {
            ApolloSettingsPicker("Default Sort", selection: $settings.defaultCommentSort,
                                 options: ["confidence", "top", "new", "controversial", "old", "qa"],
                                 display: { Self.commentSortName($0) })
                .apolloSearchRow("Default Comment Sort")
            // The two comment-sort memories are mutually exclusive;
            // both feed one store.
            Toggle("Remember Subreddit Sort", isOn: Binding(
                get: { commentSortMemoryMode == .subreddit },
                set: { commentSortMemoryMode = $0 ? .subreddit : .off; CommentSortMemoryStore.saveMode(commentSortMemoryMode) }))
                .apolloSearchRow("Remember Subreddit Sort (Comments)")
            Toggle("Remember Post Sort", isOn: Binding(
                get: { commentSortMemoryMode == .post },
                set: { commentSortMemoryMode = $0 ? .post : .off; CommentSortMemoryStore.saveMode(commentSortMemoryMode) }))
                .apolloSearchRow("Remember Post Sort")
            Toggle("Ignore Suggested Sort", isOn: $settings.ignoreSuggestedSort)
                .apolloSearchRow("Ignore Suggested Sort")
        } header: {
            Text("Sorting")
                .apolloSectionHeader()
        }
    }

    private var collapsingSection: some View {
        Section {
            // `AutoCollapseChildComments`: a Manually / Automatically value, not
            // a switch.
            ApolloSettingsPicker("Auto Collapse Child Comments", selection: $settings.autoCollapseChildComments,
                                 options: [false, true],
                                 display: { $0 ? "Automatically" : "Manually" })
                .apolloSearchRow("Auto Collapse Child Comments")
            ApolloSettingsPicker("Tap to Collapse...", selection: $settings.tapToCollapseType,
                                 options: TapToCollapseType.allCases.map { $0 },
                                 display: { $0.displayName })
                .apolloSearchRow("Tap to Collapse")
            Toggle("Collapse AutoModerator", isOn: $settings.autoCollapseAutoModeratorComments)
                .apolloSearchRow("Collapse AutoModerator")
            Toggle("Collapse Pinned Comments", isOn: $settings.autoCollapsePinnedComments)
                .apolloSearchRow("Collapse Pinned Comments")
        } header: {
            Text("Collapsing")
                .apolloSectionHeader()
        }
    }

    private var navigationSection: some View {
        Section {
            Toggle("Show Jump Button", isOn: $settings.showJumpButton)
                .apolloSearchRow("Show Jump Button")
            ApolloSettingsPicker("Jump Button Position", selection: $settings.jumpButtonPosition,
                                 options: JumpButtonPosition.allCases.map { $0 },
                                 display: { $0.displayName })
                .apolloSearchRow("Jump Button Position")
            // Phoebus-only: reopening a thread returns to the comment you'd reached.
            Toggle("Remember Thread Position", isOn: $threadPosition.rememberThreadPosition)
                .accessibilityIdentifier("settings.general.rememberThreadPosition")
                .apolloSearchRow("Remember Thread Position")
            if threadPosition.rememberThreadPosition {
                ApolloSettingsPicker("Threads to Remember", selection: $threadPosition.capacity,
                                     options: ThreadPositionSettings.capacityOptions,
                                     display: { "\($0)" })
                    .apolloSearchRow("Threads to Remember")
            }
            Toggle("Show Other Discussions", isOn: $otherDiscussions.showCountRow)
                .accessibilityIdentifier("settings.general.showOtherDiscussions")
                .apolloSearchRow("Show Other Discussions")
        } header: {
            Text("Navigation")
                .apolloSectionHeader()
        }
    }

    private var highlightsSection: some View {
        Section {
            Toggle("New Comments Highlightifier", isOn: $settings.newCommentsHighlightifier)
                .apolloSearchRow("New Comments Highlightifier")
            Toggle("New Account Highlightenator", isOn: $settings.highlightAccountAge)
                .apolloSearchRow("New Account Highlightenator")
            Toggle("Highlight My Username", isOn: $settings.highlightOwnUsername)
                .accessibilityIdentifier("settings.general.highlightOwnUsername")
                .apolloSearchRow("Highlight My Username")
            Toggle("Highlight Followed Users", isOn: $settings.highlightFollowedUsers)
                .accessibilityIdentifier("settings.general.highlightFollowedUsers")
                .apolloSearchRow("Highlight Followed Users")
            // Phoebus-only: what the byline age counts from.
            ApolloSettingsPicker("Comment Age", selection: $settings.commentAgeMode,
                                 options: CommentAgeMode.allCases.map { $0 },
                                 display: { $0.displayName })
                .accessibilityIdentifier("settings.general.commentAge")
                .apolloSearchRow("Comment Age")
            Toggle("Show Edited Marker", isOn: $settings.showEditedMarker)
                .accessibilityIdentifier("general.showEditedMarker")
                .apolloSearchRow("Show Edited Marker")
            Toggle("Hide Comment Scores", isOn: $voteCounts.hideCommentScores)
                .apolloSearchRow("Hide Comment Scores")
                .accessibilityIdentifier("general.hideCommentScores")
        } header: {
            Text("Highlights")
                .apolloSectionHeader()
        }
    }

    /// Reborn's Deleted Comments: recovers removed and deleted comment bodies.
    private var removedCommentsSection: some View {
        Section {
            // A `.navigationLink` `Picker` stands in for the push-to-choose
            // disclosure row ("Always Show ›").
            ApolloSettingsPicker("Show Deleted Comments", selection: $deleted.mode,
                                 options: DeletedCommentsMode.allCases.map { $0 },
                                 display: { $0.title },
                                 showsChevron: true)
                // search: item "Deleted Comments"
                .apolloSearchRow("Show Deleted Comments", lastBeforeFooter: deleted.mode != .alwaysShow)
                .accessibilityIdentifier("deletedComments.mode")
                .onChange(of: deleted.mode) { oldValue, newValue in
                    if oldValue != newValue, newValue == .alwaysShow { showsSlowdownWarning = true }
                }
                .alert("⚠️ WARNING", isPresented: $showsSlowdownWarning) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("This feature can slow down comment loading. If you notice comments loading slowly, turn this feature off.")
                }
            // Only shown in Always mode.
            if deleted.mode == .alwaysShow {
                Toggle("Tap to Show Deleted Comments", isOn: $deleted.tapToReveal)
                    .apolloSearchRow("Tap to Show Deleted Comments", lastBeforeFooter: true)
                    .accessibilityIdentifier("deletedComments.tapToReveal")
            }
        } header: {
            Text("Removed Comments")
                .apolloSectionHeader()
        } footer: {
            Text("Always Show recovers removed and deleted comments in every thread. Tap to Show hides each recovered comment behind its removal reason until you tap it. This can slow down comment loading.\n\nPassive leaves deleted comments off until you turn them on for a single thread from the ⋯ menu in the comments view; they turn off again when you leave that thread. The ⋯ menu always includes a Show/Hide Deleted Comments shortcut.")
                .apolloSectionFooter()
        }
    }

    private var liveCommentsSection: some View {
        Section {
            // `.apolloSearchRow` is `listRowInsets`-based, so it goes on the row
            // (this VStack), not on the inner `Toggle`.
            // The one blue switch in the set: RGB(75,150,247); every other toggle
            // is green RGB(103,206,103).
            SettingsDetailToggle("Follow New Live Comments",
                                 detail: "During Live Update comment sort, keep the newest at the top and show a jump button when you've scrolled down.",
                                 isOn: $settings.liveCommentsFollow,
                                 tint: Color(red: 75 / 255, green: 150 / 255, blue: 247 / 255))
                .apolloSearchRow("Follow New Live Comments")
        } header: {
            Text("Live Comments")
                .apolloSectionHeader()
        }
    }

    private var displaySection: some View {
        Section {
            SettingsDrillDownRow(destination: .commentsTheme, value: commentsThemeName)
            SettingsDrillDownRow(destination: .inlineMedia)
        } header: {
            Text("Display")
                .apolloSectionHeader()
        }
    }

    private static func commentSortName(_ raw: String) -> String {
        switch raw {
        case "confidence": return "Best"
        case "top": return "Top"
        case "new": return "New"
        case "controversial": return "Controversial"
        case "old": return "Old"
        case "qa": return "Q&A"
        default: return raw.capitalized
        }
    }
}
