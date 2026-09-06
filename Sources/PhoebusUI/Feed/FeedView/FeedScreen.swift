import SwiftUI
import PhoebusCore

/// Feed screen: Apollo's subreddit listing view.
public struct FeedScreen: View {
    #if canImport(UIKit)
    /// Re-renders the header when a custom banner/icon is set or removed.
    @ObservedObject var customArt = SubredditCustomArtStore.shared
    #endif
    @Environment(\.colorScheme) var colorScheme
    /// The posts, paging and load state (`FeedListingModel`); the
    /// properties below forward to it.
    @StateObject var listing = FeedListingModel()
    var posts: [RedditPost] {
        get { listing.posts }
        nonmutating set { listing.posts = newValue }
    }
    var isLoading: Bool { listing.isLoading }
    var afterToken: String? { listing.afterToken }
    var isLoadingMore: Bool { listing.isLoadingMore }
    var reachedEnd: Bool { listing.reachedEnd }
    var pageBoundaryPostIDs: Set<String> { listing.pageBoundaryPostIDs }
    var errorMessage: String? { listing.errorMessage }
    @State var sort: String
    @State var topTimeframe = "day"
    /// Result of the "Download Video…" action, surfaced as an alert so a
    /// save success/failure isn't silent.
    @State var downloadMessage: String?
    @State var downloadTitle = "Download Video"
    @State var showingUserFlair = false
    @State var signedInUsername: String?
    @State var showingTimeframeSheet = false
    /// A size just picked for this subreddit under Post Size Per Subreddit.
    @State var localPostSize: PostDisplayStyle?
    @State var isModerator = false
    /// Whether this screen's one-time setup fetches have already run.
    /// Separate from `posts.isEmpty`: an empty subreddit must still
    /// not refetch highlights/moderator status/identity on every pop back.
    @State var hasLoadedOnce = false
    @Setting(ReadPostStore.settingsStorage) var markReadSettings
    @Setting(GeneralSettingsStore.storage) var generalSettings
    /// Bumped by each `load()`; a response for an older one is dropped.
    /// Reborn "Show Page Endings" - see `pageBoundaryPostIDs`'s doc
    /// comment for the divider this drives.
    @Setting(AppearanceSettingsStore.storage) var appearanceSettings
    /// Reborn "Forget Forward Swipe After Scrolling" - see
    /// `GeneralSettings.forwardSwipeForgetAfterScrolling`. `forwardTarget`
    /// is the post most recently popped back from, standing in for a
    /// browser-style forward stack. `forwardAnchorRowIndex` records the
    /// row index at that time, for row-count-based expiry.
    @State var forwardTarget: RedditPost?
    @State var forwardAnchorRowIndex: Int?
    // See `JumpDestination`'s doc comment: SwiftUI dispatches
    // `.navigationDestination(item:)` by VALUE TYPE not binding identity,
    // so two `String?` destinations on one stack would collide.
    @State var jumpDestination: JumpDestination?
    @State var showingSidebarSheet = false
    @State var showingModeratorsSheet = false
    @State var showingSubredditNotifications = false
    /// Expandable description band, collapsed to
    /// `SubredditLayoutSettings.aboutCollapsedLines` (3) until tapped. See
    /// `subredditLayoutHeader`.
    @State var headerDescriptionExpanded = false
    @State var showingRulesSheet = false
    @State var showingGallerySheet = false
    @State var showingModQueueSheet = false
    /// Reborn "Subreddit Layout" wiring: fetched once per subreddit so
    /// the header can show live banner/subscriber data and a working Join
    /// button.
    @Setting(SubredditLayoutSettingsStore.storage) var subredditLayoutSettings
    @State var subredditInfo: RedditSubreddit?
    /// Rows on screen, for Mark Read on Scroll.
    @State var scrollPastTracker = ScrollPastTracker()
    @State var isSubscribedOverride: Bool?
    let subreddit: String
    let multiredditPath: String?
    let multiredditDisplayName: String?
    let repository: RedditRepository

    /// "best" is a distinct Reddit sort but meaningful only for the
    /// personalized home feed, so subreddit feeds omit it and default
    /// to "hot". `/r/apple/best` and `/r/apple/hot` return identical
    /// id order, i.e. Reddit aliases best to hot for a subreddit.
    static let sorts = ["best", "hot", "top", "new", "rising", "controversial"]
    static let subredditSorts = ["hot", "top", "new", "rising", "controversial"]

    public init(subreddit: String, repository: RedditRepository) {
        self.subreddit = subreddit
        self.multiredditPath = nil
        self.multiredditDisplayName = nil
        self.repository = repository
        let (initialSort, initialTimeframe) = Self.initialSortAndTimeframe(subreddit: subreddit, isMultireddit: false)
        _sort = State(initialValue: initialSort)
        _topTimeframe = State(initialValue: initialTimeframe)
    }

    /// Shows a multireddit's combined feed from its path/name alone -
    /// used by the Subreddits root, whose rows carry only those two.
    public init(multiredditPath: String, displayName: String, repository: RedditRepository) {
        self.subreddit = ""
        self.multiredditPath = multiredditPath
        self.multiredditDisplayName = displayName
        self.repository = repository
        let (initialSort, initialTimeframe) = Self.initialSortAndTimeframe(subreddit: "", isMultireddit: true)
        _sort = State(initialValue: initialSort)
        _topTimeframe = State(initialValue: initialTimeframe)
    }
    /// `GeneralSettings.defaultPostsSort`/`defaultPostsTimeSort`
    /// drive the initial sort, layering `PostSortMemoryStore` ahead of
    /// the global default. Priority: remembered per-subreddit sort,
    /// then the global default (with "best" falling back to "hot"
    /// outside the home feed).
    static func initialSortAndTimeframe(subreddit: String, isMultireddit: Bool) -> (sort: String, timeframe: String) {
        let settings = GeneralSettingsStore.load()
        let isHomeFeed = subreddit.isEmpty && !isMultireddit
        if !isHomeFeed, !isMultireddit, let remembered = PostSortMemoryStore.rememberedSort(subreddit: subreddit) {
            let timeframe = PostSortMemoryStore.rememberedTimeframe(subreddit: subreddit) ?? "day"
            return (remembered, timeframe)
        }
        var sort = settings.defaultPostsSort.rawValue
        if sort == "best", !isHomeFeed {
            sort = "hot"
        }
        return (sort, settings.defaultPostsTimeSort)
    }

    /// "Post Size Per Subreddit" (`AppearanceSettings.rememberPostSizePerSubreddit`):
    /// a real subreddit's remembered display style wins over the
    /// global `GeneralSettings.postDisplayStyle`. Not consulted for
    /// Home/aggregate feeds or multireddits.
    var effectivePostDisplayStyle: PostDisplayStyle {
        localPostSize ?? PostSizeMemoryStore.rememberedStyle(subreddit: subreddit) ?? generalSettings.postDisplayStyle
    }

    public var body: some View {
        // `JumpBarResultsList` is a ZStack sibling of `feedBody`, not an
        // `.overlay` on the List: an `.overlay` anchored to a `List`
        // can resolve to a zero-size overlay in some SwiftUI/List
        // content-size timing cases, silently dropping its content.
        ZStack(alignment: .top) {
        feedBody
        }
    }

    @ViewBuilder
    var feedBody: some View {
        // Apollo's feed is a plain, edge-to-edge list with thin
        // hairline separators, not SwiftUI's default
        // `.insetGrouped`-style List which draws each row in a card.
        List {
            // Reborn "Subreddit Layout" header: only renders for a real subreddit
            // feed with the setting on, not Home/Popular/All/Moderator or a
            // multireddit.
            if !subreddit.isEmpty, subredditLayoutSettings.showSubredditHeaders, let subredditInfo {
                subredditLayoutHeader(subredditInfo)
            }
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("feed.errorMessage")
            } else if posts.isEmpty && !isLoading {
                Text(emptyStateText)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("feed.emptyState")
            } else if posts.isEmpty && isLoading {
                // First-page spinner: the footer spinner below only
                // covers `isLoadingMore`, leaving the screen blank
                // while the first page loads.
                ApolloLoadingCell()
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("feed.loadingFirstPage")
            }
            ForEach(posts) { post in
                // Apollo's feed rows have no trailing disclosure
                // chevron, which a plain `NavigationLink` always draws.
                // A plain view with `.onTapGesture` plus
                // `navigationDestination(item:)` avoids the chevron,
                // keeps the row hit-testable, and lets the subreddit
                // label's nested `.highPriorityGesture` tap win, unlike
                // wrapping the row in a `Button` which swallows all
                // taps inside its label.
                feedRow(for: post)
                    // Infinite scroll: uses `.onAppear` on the row
                    // near the end of the loaded page, since a List
                    // only materializes rows actually scrolled into view.
                    .onAppear { loadMoreIfNeeded(currentPost: post) }
                    // No separator above the first row: a `List` draws
                    // one on both edges of every row, but Apollo's feed
                    // has the first post begin flush under the chrome.
                    // Hiding only the top edge of row 0 keeps between-
                    // row separators intact.
                    .listRowSeparator(.hidden)
                // "Show Page Endings" - see `pageBoundaryPostIDs`. A
                // subtle divider row, not a full section break.
                if appearanceSettings.showPageEndings, pageBoundaryPostIDs.contains(post.id) {
                    HStack {
                        Spacer()
                        Text("• • •")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("feed.pageEnding.\(post.id)")
                }
            }
            // Footer spinner while the next page loads, so the feed visibly
            // continues.
            if isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
                .accessibilityIdentifier("feed.loadingMore")
            }
            // The manual continuation Apollo shows when Infinite
            // Scrolling is off. See
            // `FeedPaginationPolicy.shouldOfferManualNextPage`.
            if FeedPaginationPolicy.shouldOfferManualNextPage(
                infiniteScrollingEnabled: generalSettings.infiniteScrollingEnabled,
                reachedEnd: reachedEnd,
                isLoadingMore: isLoadingMore,
                isLoading: isLoading,
                loadedCount: posts.count
            ) {
                Button {
                    Task { await loadMore() }
                } label: {
                    HStack(spacing: 6) {
                        Spacer()
                        Text("Load Page \(FeedPaginationPolicy.nextPageNumber(loadedCount: posts.count))")
                        Image(systemName: "chevron.down")
                        Spacer()
                    }
                    .font(.subheadline.weight(.medium))
                }
                .disabled(isLoadingMore)
                .accessibilityHint("Double tap to load next page")
                .accessibilityIdentifier("feed.loadNextPage")
                .listRowSeparator(.hidden)
            }
            // End-of-feed cell (see `ReachedEndCopy`). Rendered when
            // pagination has genuinely stopped because the feed ended,
            // with a message and, from the second visit onward, a beast.
            if reachedEnd, !posts.isEmpty, !isLoading {
                ReachedEndView(
                    // Reddit caps a listing at ~1000 items; a null
                    // `after` on a feed that long means the true end of
                    // everything loadable rather than a short listing
                    // simply running out.
                    likelyReachedEndOfLoadablePosts: posts.count >= FeedPaginationPolicy.longFeedThreshold
                )
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        // Tapping the status bar a second time returns to where you were
        // reading.
        .restoresPositionOnSecondScrollToTop()
        .apolloScrollReturnButton()
        // iOS 26's `List` (even with `.listStyle(.plain)`) wraps its
        // scrollable content in a rounded "Liquid Glass" card by
        // default. `.scrollContentBackground(.hidden)` disables that
        // automatic system card so rows render flat and full-bleed.
        .scrollContentBackground(.hidden)
        // Stock dark surface + Pure Black tiers (see `ApolloStockSurface`).
        .apolloStockSurface()
        .apolloOpensRedditTargetsHere()
        .apolloForwardSwipe()
        .apolloPopsOnTabReselection(item: $jumpDestination)
        // Apollo's toolbar title is a "Jump Bar": an inline transformation of
        // the title into a full-width text field docked in the nav bar, with
        // ghost-text autocomplete.
        .navigationTitle(navigationTitleText)
        //
        // It lives in the inline nav bar, never a large title: in `.large`
        // mode SwiftUI drops the whole `.principal` toolbar item.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                    Button {
                    } label: {
                        HStack(spacing: 4) {
                            // Width budget: see `navigationTitleMaxWidth`.
                            Text(navigationTitleDisplayText)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .frame(maxWidth: FeedScreen.navigationTitleMaxWidth)
                        .foregroundStyle(.primary)
                    }
                    .disabled(multiredditDisplayName != nil)
                    .accessibilityIdentifier("feed.titleJumpBarButton")
                .apolloGlassBarTint()
            }
        }
        // The back button is icon only: a bare circular chevron. Liquid Glass
        // collapses it to its glyph (44pt circle); older iOS shows the
        // "< Subreddits" text form.
        .navigationBarBackButtonHidden(multiredditDisplayName == nil)
        .toolbar {
            if multiredditDisplayName == nil {
                ToolbarItem(placement: .navigation) {
                    FeedBackButton()
                        .apolloGlassBarTint()
                }
            }
        }
        // Apollo's sort control is a full-width bottom action sheet titled
        // "Sort by…" with a per-sort icon, a trailing checkmark on the active
        // sort and a chevron on Top for the time-period sub-sheet.
        // `confirmationDialog` strips row icons and checkmarks, so this uses
        // the custom `ApolloActionSheet`.
        .apolloActionSheet(isPresented: $showingTimeframeSheet, title: "Time period", rows: timeframeSheetRows)
        // Titled by what was saved: this alert also reports GIF saves,
        // which read "Download Video".
        .alert(downloadTitle, isPresented: $downloadMessage.isPresent()) {
            Button("OK") { downloadMessage = nil }
        } message: {
            Text(downloadMessage ?? "")
        }
        .task {
            if posts.isEmpty {
                await load()
            }
            if !hasLoadedOnce {
                hasLoadedOnce = true
                await checkModeratorStatus()
                signedInUsername = try? await repository.fetchIdentity().name
            }
        }
        .refreshable { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .apolloSubscriptionsChanged)) { note in
            applySubscriptionChange(note)
        }

    }

    /// Home/Popular/All/Moderator and multireddits mix subreddits, so
    /// the real cell shows each post's subreddit icon there.

    /// The whole feed row plus its modifier chain, extracted from the
    /// `List`'s body because the inlined chain exceeds the type-checker's
    /// budget.
    private var isLargeLayout: Bool { effectivePostDisplayStyle == .large }

    @ViewBuilder
    func feedRow(for post: RedditPost) -> some View {
        PostRow(
            post: post,
            repository: repository,
            displayStyle: effectivePostDisplayStyle,
            isAggregateFeed: isAggregateFeed,
            onSubredditTap: { jumpDestination = .subreddit(post.subreddit) },
            onAuthorTap: { jumpDestination = .user(post.author) },
        )
        .contentShape(Rectangle())
        .accessibilityIdentifier("feed.postRow.\(post.id)")
        .listRowBackground(Color.clear)
        // Compact: 12pt sides, 10.7pt top, 12.7pt bottom, 20pt trailing to
        // clear the vote arrow column. Large: no side insets, so its media
        // runs edge to edge and its text sits at the 16pt margin.
        .listRowInsets(isLargeLayout
            ? EdgeInsets(top: 10.7, leading: 0, bottom: 12.7, trailing: 0)
            : EdgeInsets(top: 10.7, leading: 12, bottom: 12.7, trailing: 20))
        // Separator runs from x=16 to the right edge at 0.33pt, not
        // inset on both sides like the system default (1.0pt), so the
        // system separator is hidden and the hairline drawn by hand,
        // exactly as `apolloSettingsRowInsets` does.
        .listRowSeparator(.hidden)
        .overlay(alignment: .top) {
            if post.id != posts.first?.id {
                Rectangle()
                    .fill(Color.apolloSeparator(colorScheme: colorScheme))
                    .frame(height: 1.0 / 3.0)
                    .padding(.leading, isLargeLayout ? 16 : 4)
                    .padding(.trailing, isLargeLayout ? 0 : -20)
                    .offset(y: -10.7)
            }
        }
        // "Forget Forward Swipe After Scrolling" expiry - see
        // `forwardTarget` (row-count-based expiry, threshold ~3 posts).
        .onAppear {
            expireForwardTargetIfNeeded(forRowOf: post)
            scrollPastTracker.appeared(post.id, at: posts.firstIndex { $0.id == post.id } ?? 0)
        }
        // "Mark Read on Scroll": a post is read once it scrolls off the
        // top, past rows still on screen below it; not merely for having
        // been shown, nor when it leaves at the bottom.
        .onDisappear {
            if scrollPastTracker.disappearedAbove(post.id), markReadSettings.markReadOnScroll {
                ReadPostStore.markRead(post.name)
            }
        }
    }

    var isAggregateFeed: Bool {
        if multiredditPath != nil { return true }
        switch subreddit.lowercased() {
        case "", "popular", "all", "mod": return true
        default: return false
        }
    }
    /// Reddit's `t=` timeframe values for Top/Controversial sorts,
    /// matching the second-level sheet Apollo opens when "Top" is tapped.
    static let timeframes: [(label: String, value: String)] = [
        ("Hour", "hour"),
        ("Day", "day"),
        ("Week", "week"),
        ("Month", "month"),
        ("Year", "year"),
        ("All Time", "all"),
    ]
    var navigationTitleText: String {
        if let multiredditDisplayName {
            return multiredditDisplayName
        }
        switch subreddit.lowercased() {
        case "": return "Home"
        case "popular": return "Popular"
        case "all": return "All"
        case "mod": return "Moderator Posts"
        // Apollo's display casing: "r/Pics", not Reddit's "r/pics".
        default: return "r/\(SubredditCapitalization.display(subreddit))"
        }
    }

    /// Width budget for the jump-bar title button (name + chevron), so
    /// a centred title stays symmetric. 160pt covers a full
    /// 17-character subreddit name without ellipsis.
    static let navigationTitleMaxWidth: CGFloat = 160

    /// Same as `navigationTitleText` but without the "r/" prefix, used
    /// only for the jump-bar title button's own label to save
    /// horizontal space.
    var navigationTitleDisplayText: String {
        return navigationTitleText.hasPrefix("r/") ? String(navigationTitleText.dropFirst(2)) : navigationTitleText
    }
    /// "Forget Forward Swipe After Scrolling" - see `forwardTarget`.
    /// Called from every row's `.onAppear` (a real user-scroll signal
    /// in a `List`); drops the remembered forward-swipe target once
    /// the user has scrolled at least `forwardExpiryRowThreshold` rows
    /// past the post they popped back from.
    static let forwardExpiryRowThreshold = 3

    /// Infinite-scroll trigger. Fires from each row's `.onAppear`,
    /// starting the next fetch within `loadMoreThreshold` posts of the
    /// end so the next page is usually already loaded by the time the
    /// user gets there.
    static let loadMoreThreshold = 5
}

/// A Flair/Sidebar button from the subreddit header's action cluster.
/// Reborn builds these as icon-only buttons with an identical
/// square frame; sizing is a property of the button, not its content,
/// unlike labelled pills that sized differently per label.
struct SubredditSecondaryActionButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                // The glyph scales to 22pt.
                .font(.system(size: SubredditLayoutSettings.secondaryActionIconSide * 0.75,
                              weight: .semibold))
                .frame(width: SubredditLayoutSettings.secondaryActionSide,
                       height: SubredditLayoutSettings.secondaryActionSide)
                .background(
                    // Approximates the glass effect view behind each button.
                    Circle().fill(Color.secondary.opacity(0.18)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// The feed's back chevron. `dismiss` is read here, not in `FeedScreen`:
/// on iOS 17 the environment value changes on every navigation update, and
/// reading it in the feed's body re-rendered the whole list in a loop.
private struct FeedBackButton: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Button {
            dismiss()
        } label: {
            // Glyph only, matching Liquid Glass.
            Image(systemName: "chevron.left")
        }
        .accessibilityLabel("Subreddits")
        .accessibilityIdentifier("feed.backToSubreddits")
    }
}
