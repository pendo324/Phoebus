import SwiftUI
import PhoebusCore
#if canImport(WebKit)
import WebKit
#endif

/// Apollo's General settings: every setting in `GeneralSettings` as a
/// toggle, picker or stepper, grouped by behaviour.
public struct GeneralSettingsScreen: View {
    @Setting(GeneralSettingsStore.storage) private var settings
    @State private var commentSortMemoryMode = CommentSortMemoryStore.loadMode()

    public init() {}

    @State private var didClearCache = false
    /// Top or Controversial just picked: Apollo follows up with "Sort by
    /// Top for…" / "Sort by Controversial for…".
    @State private var timeRangeSort: DefaultPostSort?
    @State private var showingDefaultRedditSheet = false
    /// The signed-in account moderates something (`is_mod`); remembered for
    /// the session so the section doesn't pop in on every visit.
    @State private var isModerator = GeneralSettingsScreen.knownModerator ?? false
    nonisolated(unsafe) private static var knownModerator: Bool?
    @State private var choosingSubreddit = false
    @State private var subredditName = ""
    @State private var multireddits: [RedditMultireddit] = []
    @State private var showingMultiredditSheet = false
    @State private var defaultRedditMessage: String?

    private func setDefaultReddit(_ choice: DefaultRedditToLoadChoice?) {
        $settings.update {
            $0.rememberSubredditToLoad = choice == nil
            if let choice { $0.defaultRedditToLoad = choice.stored }
        }
    }

    private func chooseMultireddit() async {
        guard let repository = ActiveRedditRepository.provider(),
              let multis = try? await repository.fetchMultireddits() else {
            defaultRedditMessage = "You need to be signed in to set a specific multireddit from your account."
            return
        }
        guard !multis.isEmpty else {
            defaultRedditMessage = "You haven’t created any multireddits! Why not create one then come back and set it?"
            return
        }
        multireddits = multis
        showingMultiredditSheet = true
    }

    public var body: some View {
        // Stock Apollo's General screen as it ships under Reborn:
        // Open Links / Posts / Comments / Safari / Media / Moderator /
        // Other. No section carries a footer. Reborn splices five
        // disclosure rows into it and hides five stock rows; both are
        // reflected here.
        List {
            openLinksSection
            postsSection
            commentsSection
            safariSection
            mediaSection
            // Stock shows this section to moderators only.
            if isModerator { moderatorSection }
            otherSection
            cacheSection
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .task {
            guard let repository = ActiveRedditRepository.provider(),
                  let me = try? await repository.fetchIdentity() else { return }
            Self.knownModerator = me.isMod
            isModerator = me.isMod
        }
        .apolloActionSheet(isPresented: $showingDefaultRedditSheet, title: "Default Reddit to Load…", rows: [
            ApolloActionSheetRow("Home") { setDefaultReddit(.home) },
            ApolloActionSheetRow("Popular Posts") { setDefaultReddit(.popular) },
            ApolloActionSheetRow("All Posts") { setDefaultReddit(.all) },
            ApolloActionSheetRow("Subreddits List") { setDefaultReddit(.redditsList) },
            ApolloActionSheetRow("Remember Subreddit") { setDefaultReddit(nil) },
            ApolloActionSheetRow("Subreddit…") { subredditName = ""; choosingSubreddit = true },
            ApolloActionSheetRow("Multireddit…") { Task { await chooseMultireddit() } },
        ])
        .apolloActionSheet(isPresented: $showingMultiredditSheet, title: "Multireddit", rows: multireddits.map { multi in
            ApolloActionSheetRow(multi.displayName) { setDefaultReddit(.multireddit(path: multi.path, name: multi.displayName)) }
        })
        .alert("Subreddit", isPresented: $choosingSubreddit) {
            TextField("Subreddit name", text: $subredditName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Set") {
                let name = subredditName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { setDefaultReddit(.subreddit(name.hasPrefix("r/") ? String(name.dropFirst(2)) : name)) }
            }
        }
        .alert("Default Reddit to Load", isPresented: $defaultRedditMessage.isPresent()) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(defaultRedditMessage ?? "")
        }
        .apolloActionSheet(isPresented: $timeRangeSort.isPresent(),
                           title: "Sort by \(timeRangeSort?.displayName ?? "Top") for…",
                           rows: FeedScreen.timeframes.map { option in
                               ApolloActionSheetRow(option.label) {
                                   let sort = timeRangeSort ?? .top
                                   $settings.update {
                                       $0.defaultPostsSort = sort
                                       $0.defaultPostsTimeSort = option.value
                                   }
                               }
                           })
        .navigationTitle("General")
    }

    // MARK: - Open Links

    @ViewBuilder private var openLinksSection: some View {
        Section {
            SettingsLink("Open in App") { OpenInAppSettingsScreen() }
                .apolloSearchRow("Open in App")
        } header: {
            Text("Open Links")
                .apolloSectionHeader()
        }
    }

    // MARK: - Posts

    @ViewBuilder private var postsSection: some View {
        Section {
            SettingsLink("Smart Rotation Lock") { PortraitLockSettingsScreen() }
                .apolloSearchRow("Smart Rotation Lock")
            SettingsLink("Mark Read / Hiding Posts") { MarkReadSettingsScreen() }
                .apolloSearchRow("Mark Read / Hiding Posts")
            Toggle("Upvote on Save", isOn: $settings.upvoteOnSave)
                .apolloSearchRow("Upvote on Save")
            ApolloSettingsPicker("Default Sort", selection: Binding(
                                     get: { settings.defaultPostsSort },
                                     set: { sort in
                                         if sort.supportsTimeRange { timeRangeSort = sort }
                                         else { $settings.defaultPostsSort.wrappedValue = sort }
                                     }),
                                 options: DefaultPostSort.allCases.map { $0 },
                                 display: { sort in
                                     guard sort.supportsTimeRange, sort == settings.defaultPostsSort,
                                           let range = FeedScreen.timeframes.first(where: { $0.value == settings.defaultPostsTimeSort })
                                     else { return sort.displayName }
                                     return "\(sort.displayName) (\(range.label))"
                                 })
                .apolloSearchRow("Default Sort")
            Toggle("Remember Subreddit Sort", isOn: $settings.rememberPostsSortPerSubreddit)
                .apolloSearchRow("Remember Subreddit Sort")
            ApolloSettingsPicker("Autoplay GIFs/Videos", selection: $settings.autoplayMode,
                                 options: AutoplayMode.allCases.map { $0 },
                                 display: { $0.displayName })
                .apolloSearchRow("Autoplay GIFs/Videos")
            Toggle("Infinite Scrolling", isOn: $settings.infiniteScrollingEnabled)
                .apolloSearchRow("Infinite Scrolling")
            Toggle("Share Includes Title", isOn: $settings.sharePostIncludesTitle)
                .apolloSearchRow("Share Includes Title")
        } header: {
            Text("Posts")
                .apolloSectionHeader()
        }
    }

    // MARK: - Comments

    @ViewBuilder private var commentsSection: some View {
        Section {
            ApolloSettingsPicker("Default Sort", selection: $settings.defaultCommentSort,
                                 options: ["confidence", "top", "new", "controversial", "old", "qa"],
                                 display: { Self.commentSortName($0) })
                .apolloSearchRow("Default Comment Sort")
            Toggle("New Comments Highlightifier", isOn: $settings.newCommentsHighlightifier)
                .apolloSearchRow("New Comments Highlightifier")
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
            Toggle("Show Jump Button", isOn: $settings.showJumpButton)
                .apolloSearchRow("Show Jump Button")
            ApolloSettingsPicker("Jump Button Position", selection: $settings.jumpButtonPosition,
                                 options: JumpButtonPosition.allCases.map { $0 },
                                 display: { $0.displayName })
                .apolloSearchRow("Jump Button Position")
            Toggle("New Account Highlightenator", isOn: $settings.highlightAccountAge)
                .apolloSearchRow("New Account Highlightenator")
            ApolloSettingsPicker("Blocked Users", selection: $settings.hideBlockedUserComments,
                                 options: [false, true],
                                 display: { $0 ? "Hide" : "Collapse" })
                .apolloSearchRow("Blocked Users")
        } header: {
            Text("Comments")
                .apolloSectionHeader()
        }
    }

    // MARK: - Safari

    @ViewBuilder private var safariSection: some View {
        Section {
            Toggle("Always Use Reader Mode", isOn: $settings.alwaysUseReaderMode)
                .apolloSearchRow("Always Use Reader Mode")
            Toggle("Show Comments Button", isOn: $settings.showCommentsButton)
                .apolloSearchRow("Show Comments Button")
        } header: {
            Text("Safari")
                .apolloSectionHeader()
        }
    }

    // MARK: - Media

    @ViewBuilder private var mediaSection: some View {
        Section {
            // Stock row: the fullscreen viewer's sound.
            ApolloSettingsPicker("Unmute Videos When Opened", selection: $settings.unmuteVideosWhenOpened,
                                 options: [UnmuteWhenOpenedSetting.remember, .always, .never],
                                 display: { $0.displayName })
                .apolloSearchRow("Unmute Videos When Opened")
            // Reborn injection.
            SettingsLink("Unmute Videos in Feed") { MediaSettingsScreen() }
                .apolloSearchRow("Unmute Videos in Feed")
            ApolloSettingsPicker("Download GIFs as...", selection: $settings.gifSaveFormat,
                                 options: GIFSaveFormat.allCases.map { $0 },
                                 display: { $0.displayName })
                .apolloSearchRow("Download GIFs as")
            Toggle("Video Deblurinator", isOn: $settings.videoDeblurinatorEnabled)
                .apolloSearchRow("Video Deblurinator")
            Toggle("Show Controls When Opened", isOn: $settings.showMediaViewerControlsWhenOpened)
                .apolloSearchRow("Show Controls When Opened")
            Toggle("Save to “Phoebus” Album", isOn: $settings.saveToApolloAlbum)
                .apolloSearchRow("Save to Phoebus Album")
            Toggle("Loop Videos with Audio", isOn: $settings.loopVideosWithAudio)
                .apolloSearchRow("Loop Videos with Audio")
            Toggle("Live Text Analyzer", isOn: $settings.liveTextAnalyzer)
                .apolloSearchRow("Live Text Analyzer")
            SettingsLink("Manage Uploads") { DeleteImgurUploadsScreen() }
                .apolloSearchRow("Manage Uploads")
            // Reborn injection.
            SettingsLink("Picture-in-Picture") { PictureInPictureSettingsScreen() }
                .apolloSearchRow("Picture-in-Picture")
        } header: {
            Text("Media")
                .apolloSectionHeader()
        }
    }

    // MARK: - Moderator

    @ViewBuilder private var moderatorSection: some View {
        Section {
            Toggle("Unify Modmail in Inbox", isOn: $settings.unifyModmailInInbox)
                .apolloSearchRow("Unify Modmail in Inbox")
        } header: {
            Text("Moderator")
                .apolloSectionHeader()
        }
    }

    // MARK: - Other

    @ViewBuilder private var otherSection: some View {
        Section {
            // Stock "Default Reddit to Load…": a picker of the feeds, the
            // Subreddits list, Remember Subreddit, a subreddit or one of
            // your multireddits.
            Button { showingDefaultRedditSheet = true } label: {
                HStack {
                    Text("Default Reddit to Load")
                    Spacer()
                    Text(settings.rememberSubredditToLoad ? "Remember Subreddit"
                         : DefaultRedditToLoadChoice(stored: settings.defaultRedditToLoad).displayName)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .apolloSearchRow("Default Reddit to Load")
            // Stock's own switch; a Share Link Host other than Reddit
            // still wins (`effectiveShareLinkHost`).
            Toggle("Share old.reddit Links", isOn: $settings.shareOldRedditLinks)
                .apolloSearchRow("Share old.reddit Links")
            // Reborn injection.
            SettingsLink("Translation") { TranslationSettingsScreen() }
                .apolloSearchRow("Translation")
            Toggle("No Subscribed in All/Popular", isOn: $settings.excludeSubscribedFromAllPopular)
                .apolloSearchRow("No Subscribed in All/Popular")
            Toggle("Allow Save Categories", isOn: $settings.allowSaveCategories)
                .apolloSearchRow("Allow Save Categories")
            // Reborn injection.
            SettingsLink("Saved Categories") { SavedCategoriesSettingsScreen() }
                .apolloSearchRow("Saved Categories")
            ApolloSettingsPicker("Open Tweets in", selection: $settings.openTwitterLinksIn,
                                 options: TwitterLinkDestination.allCases.map { $0 },
                                 display: { $0.displayName })
                .apolloSearchRow("Open Tweets in")
            Toggle("Haptic Feedback", isOn: $settings.hapticFeedbackEnabled)
                .apolloSearchRow("Haptic Feedback")
            Toggle("3D Touch Marks Read", isOn: $settings.threeDTouchMarksRead)
                .apolloSearchRow("3D Touch Marks Read")
            SettingsLink("Is Phoebus Still Taking up Storage?") { CacheExplainerScreen() }
                .apolloSearchRow("Is Phoebus Still Taking up Storage?")
        } header: {
            Text("Other")
                .apolloSectionHeader()
        }
    }

    // MARK: - Cache

    /// Stock's Cache section: one "Clear Cache" row whose menu offers the
    /// app's own cache or the in-app browser's.
    @ViewBuilder private var cacheSection: some View {
        Section {
            Menu {
                Button("Clear Cache") { Task { await CacheClearing.clearAppCache(); didClearCache = true } }
                Button("Clear Browser Cache") { Task { await CacheClearing.clearBrowserCache(); didClearCache = true } }
            } label: {
                Text(didClearCache ? "Cache Cleared" : "Clear Cache")
                    .foregroundStyle(Color.apolloAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .apolloSearchRow("Clear Cache", lastBeforeFooter: true)
        } header: {
            Text("Cache").apolloSectionHeader()
        } footer: {
            Text("Maximum of around 200 MB.").apolloSectionFooter()
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

/// What stock Clear Cache / Clear Browser Cache empty.
@MainActor
enum CacheClearing {
    /// Downloaded images, link previews, avatars and temporary files.
    static func clearAppCache() async {
        URLCache.shared.removeAllCachedResponses()
        await ImageCache.shared.removeAll()
        await DownsampleCache.shared.removeAll()
        await AvatarCache.shared.clear()
        await LinkPreviewCache.shared.clear()
        let temp = FileManager.default.temporaryDirectory
        for url in (try? FileManager.default.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// The in-app browser's cached pages (not its cookies or sign-ins).
    static func clearBrowserCache() async {
        #if canImport(WebKit)
        await WKWebsiteDataStore.default().removeData(
            ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache,
                      WKWebsiteDataTypeOfflineWebApplicationCache, WKWebsiteDataTypeFetchCache],
            modifiedSince: .distantPast)
        #endif
    }
}
