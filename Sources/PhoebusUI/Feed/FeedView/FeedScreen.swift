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
    @State var flairTargetPost: RedditPost?
    @State var signedInUsername: String?
    @State var showingTimeframeSheet = false
    /// A size just picked for this subreddit under Post Size Per Subreddit.
    @State var localPostSize: PostDisplayStyle?
    @State var showingCompose = false
    @State var isModerator = false
    /// Whether this screen's one-time setup fetches have already run.
    /// Separate from `posts.isEmpty`: an empty subreddit must still
    /// not refetch highlights/moderator status/identity on every pop back.
    @State var hasLoadedOnce = false

    /// Identifies this feed in `FeedSnapshotCache`. A multireddit and a
    /// subreddit of the same name are different feeds, so the path is
    /// part of the key.
    var snapshotKey: String {
        if let multiredditPath { return "m:\(multiredditPath)" }
        return "r:\(subreddit)"
    }
    @Setting(SwipeActionStore.storage(for: .posts)) private var swipeSettings
    @Setting(ReadPostStore.settingsStorage) var markReadSettings
    @State var reportTarget: RedditPost?
    @Setting(GeneralSettingsStore.storage) var generalSettings
    /// Bumped by each `load()`; a response for an older one is dropped.
    /// Reborn "Show Page Endings" - see `pageBoundaryPostIDs`'s doc
    /// comment for the divider this drives.
    @Setting(AppearanceSettingsStore.storage) var appearanceSettings
    @State var selectedPost: RedditPost?
    /// Swipe-action targets for Reply and Share.
    @State var replyTarget: RedditPost?
    @State var shareTarget: RedditPost?
    /// Reborn "Info Row" tap action (`UDKeyInfoRowTapComments`): set
    /// right before `selectedPost` when the comments count itself was
    /// tapped, so the pushed `PostDetailScreen` auto-scrolls to comments.
    @State var jumpToCommentsOnOpen = false
    /// Reborn "Forget Forward Swipe After Scrolling" - see
    /// `GeneralSettings.forwardSwipeForgetAfterScrolling`. `forwardTarget`
    /// is the post most recently popped back from, standing in for a
    /// browser-style forward stack. `forwardAnchorRowIndex` records the
    /// row index at that time, for row-count-based expiry.
    @State var forwardTarget: RedditPost?
    @State var forwardAnchorRowIndex: Int?
    /// Reborn "Center Title Between Buttons" offset. Screen-owned
    /// `@State` rather than read from a shared store: a `.toolbar` item
    /// does not observe an external `ObservableObject`, so the title
    /// would not re-render on a store-driven value.
    @State var titleCenteringOffset: CGFloat = 0
    // See `JumpDestination`'s doc comment: SwiftUI dispatches
    // `.navigationDestination(item:)` by VALUE TYPE not binding identity,
    // so two `String?` destinations on one stack would collide.
    @State var jumpDestination: JumpDestination?
    @State var showingSidebarSheet = false
    /// Feed-level "•••" rows.
    @State var editingMultireddit: EditingMultireddit?
    @State var sharingFeedURL: ShareableURL?
    @State var showingAddToMultireddit = false
    @State var showingModeratorsSheet = false
    @State var showingSubredditNotifications = false
    /// Which composer the post-type icon row asked for.
    @State var composeKind: ComposePostScreen.PostType = .text
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
    /// Community Highlights (Reborn). See `CommunityHighlights` for the
    /// rules; the mode lives in `SubredditLayoutSettings.communityHighlights`.
    @State var highlightPosts: [RedditPost] = []
    /// Rows on screen, for Mark Read on Scroll.
    @State var scrollPastTracker = ScrollPastTracker()
    /// Full-mode scrape results, which supplement the REST cards.
    @State var scrapedHighlights: [ScrapedHighlight] = []
    @State var highlightsWebFetch: CommunityHighlightsWebFetch?
    /// A scraped card has only a permalink, so opening it routes
    /// through the same loader deep links use.
    @State var scrapedDestination: ScrapedHighlight?
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

    /// Shows a multireddit's combined feed instead of a single subreddit.
    public init(multireddit: RedditMultireddit, repository: RedditRepository) {
        self.subreddit = ""
        self.multiredditPath = multireddit.path
        self.multiredditDisplayName = multireddit.displayName
        self.repository = repository
        // Multireddits don't support the "best" sort (home-feed only),
        // so this uses "hot" regardless of subreddit being empty.
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
        crashTrackedBody.onAppear { CrashRecorder.record(.openedFeed) }
    }

    @ViewBuilder private var crashTrackedBody: some View {
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
            // The carousel is the feed's table header, so it scrolls away with
            // the content.
            if !carouselPosts.isEmpty || !scrapedHighlights.isEmpty {
                CommunityHighlightsCarousel(
                    posts: carouselPosts,
                    // Only supplement when the scrape genuinely found
                    // more than the REST pair.
                    scraped: carouselScrape,
                    knownPosts: posts + highlightPosts,
                    // Keys the remembered collapsed state. See
                    // `HighlightsCollapseStore`.
                    subreddit: subreddit
                ) { post in
                    selectedPost = post
                } onSelectScraped: { highlight in
                    // Prefer a post the feed has already loaded:
                    // highlights are the subreddit's stickied posts, so
                    // it is almost always already in `posts`, avoiding
                    // a slow full `/comments` round trip.
                    if let existing = CommunityHighlights.matchingPost(
                        forPermalink: highlight.permalink,
                        in: posts + highlightPosts
                    ) {
                        selectedPost = existing
                    } else {
                        scrapedDestination = highlight
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
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
            ForEach(feedPosts) { post in
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
        // Reserve room for the floating Liquid Glass tab bar so the
        // last row is reachable at the bottom of the scroll.
        .apolloPostSwipePresenters(replyTarget: $replyTarget, shareTarget: $shareTarget,
                                   repository: repository)
        // Tapping the status bar a second time returns to where you were
        // reading.
        .restoresPositionOnSecondScrollToTop()
        .overlay(alignment: .bottomTrailing) {
            if markReadSettings.showHideReadButton, !posts.isEmpty {
                HideReadPostsButton { hideReadPosts() }
                    .padding(.trailing, 16)
                    .padding(.bottom, 24)
            }
        }
        .apolloScrollReturnButton()
        // iOS 26's `List` (even with `.listStyle(.plain)`) wraps its
        // scrollable content in a rounded "Liquid Glass" card by
        // default. `.scrollContentBackground(.hidden)` disables that
        // automatic system card so rows render flat and full-bleed.
        .scrollContentBackground(.hidden)
        // Stock dark surface + Pure Black tiers (see `ApolloStockSurface`).
        .apolloStockSurface()
        // Browser-style forward navigation: swiping back from a post
        // can be undone by a right-edge forward swipe.
        .apolloTracksForwardNavigation($selectedPost)
        .apolloOpensRedditTargetsHere()
        // A scraped highlight pushes through its own binding, so it is
        // registered with the forward-swipe machinery explicitly.
        .apolloTracksForwardNavigation($scrapedDestination)
        .apolloForwardSwipe()
        // Re-tapping Posts unwinds this whole stack, not just its root.
        // Each pushed screen clears its own destination because these
        // stacks are item-driven per screen rather than one shared
        // path; see `apolloPopsOnTabReselection`.
        .apolloPopsOnTabReselection(item: $selectedPost)
        .apolloPopsOnTabReselection(item: $replyTarget)
        .apolloPopsOnTabReselection(item: $scrapedDestination)
        .apolloPopsOnTabReselection(item: $jumpDestination)
        .apolloPopsOnTabReselection(isPresented: $showingGallerySheet)
        // A scraped highlight has only a permalink, so it is resolved
        // into a real post the same way a deep link is: fetch first,
        // then present. `/r/<sub>/comments/<id>/<slug>` is the shape
        // Reddit's own carousel links use.
        .navigationDestination(item: $scrapedDestination) { highlight in
            if let ids = CommunityHighlights.identifiers(fromPermalink: highlight.permalink) {
                PostPermalinkLoader(
                    subreddit: ids.subreddit,
                    postID: ids.postID,
                    repository: repository,
                    // The card already knows the title, so the pushed
                    // screen can show it immediately rather than a
                    // spinner on an empty black screen.
                    placeholderTitle: highlight.title
                )
            } else {
                Text("Couldn't open this highlight.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationDestination(item: $selectedPost) { post in
            PostDetailScreen(post: post, repository: repository, startScrolledToComments: jumpToCommentsOnOpen)
                .onAppear {
                    // Honours the "Mark Posts Read on Open" toggle.
                    if markReadSettings.markReadOnOpen {
                        ReadPostStore.markRead(post.name)
                    }
                    RecentlyReadStore.recordView(
                        fullname: post.name,
                        title: post.title,
                        subreddit: post.subreddit,
                        author: post.author,
                        permalink: post.permalink,
                        isNSFW: post.over18,
                        thumbnailURL: post.thumbnail
                    )
                }
                // "Forget Forward Swipe After Scrolling": see `forwardTarget`.
                // `.onDisappear` records the forward-swipe target when popping back
                // to the feed.
                .onDisappear {
                    guard selectedPost == nil else { return }
                    forwardTarget = post
                    forwardAnchorRowIndex = posts.firstIndex { $0.id == post.id }
                }
        }
        // Apollo's toolbar title is a "Jump Bar": an inline transformation of
        // the title into a full-width text field docked in the nav bar, with
        // ghost-text autocomplete.
        .navigationTitle(navigationTitleText)
        //
        // It lives in the inline nav bar, never a large title: in `.large`
        // mode SwiftUI drops the whole `.principal` toolbar item.
        .navigationBarTitleDisplayMode(.inline)
        .apolloMeasuresTitleCentering(key: "feed", offset: $titleCenteringOffset)
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
                    // Reborn "Center Title Between Buttons"; see
                    // `CenterTitleBetweenButtonsModifier`. Inert unless the setting is on.
                    .offset(x: titleCenteringOffset)
                    .accessibilityIdentifier("feed.titleJumpBarButton")
                .apolloGlassBarTint()
            }
        }
        .navigationDestination(item: $jumpDestination) { destination in
            switch destination {
            case .subreddit(let name):
                FeedScreen(subreddit: name, repository: repository)
            case .user(let username):
                UserProfileScreen(username: username, repository: repository)
            }
        }
        .apolloTracksForwardNavigation($jumpDestination)
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
            // The feed toolbar shows two trailing icons: sort and
            // "•••". The sort icon changes with the active sort; tapping
            // it opens "Sort by…" as a sheet or UIMenu depending on
            // Liquid Glass.
            ToolbarItem(placement: .primaryAction) {
                ApolloOverflowMenu(title: "Sort by…",
                                   systemImage: sortIconName,
                                   rows: sortSheetRows)
                .accessibilityIdentifier("feed.sortButton")
                .apolloGlassBarTint()
            }
            // Per-subreddit "•••" overflow sheet. Search, Gallery, Compose,
            // Sidebar and Mod Queue are reached through it rather than their own
            // icons. "Set User Flair" is omitted: no endpoint is wired up.
            ToolbarItem(placement: .primaryAction) {
                // Two real shapes, one menu: a compact anchored menu on
                // the Liquid Glass path, the full-width sheet
                // everywhere else. See `ApolloOverflowMenu`.
                ApolloOverflowMenu(systemImage: "option-more", composerRow: composerIconRow, rows: overflowRows)
                .accessibilityIdentifier("feed.overflowButton")
                .apolloGlassBarTint()
            }
        }
        .apolloTracksForwardNavigation($showingGallerySheet)
        .navigationDestination(isPresented: $showingGallerySheet) {
            // Hand over everything that identifies THIS feed.
            //
            // A multireddit's `subreddit` is "", so passing only
            // `subreddit` falls through to the signed-in user's home
            // listing instead of the multireddit; the sort must be
            // passed too or a subreddit gallery silently resets to Hot.
            GalleryViewScreen(
                subreddit: subreddit,
                multiredditPath: multiredditPath,
                feedTitle: navigationTitleText,
                sort: sort,
                timeframe: topTimeframe,
                // The feed already holds these, so the gallery opens
                // populated rather than refetching what is on screen.
                posts: posts,
                repository: repository
            )
        }
        .sheet(isPresented: $showingAddToMultireddit) {
            AddToMultiredditSheet(subredditName: subreddit, repository: repository) {
                showingAddToMultireddit = false
            }
        }
        .sheet(item: $editingMultireddit) { editing in
            MultiredditEditSheet(path: editing.path, repository: repository) {
                editingMultireddit = nil
                // A rename changes what the Subreddits list shows, so
                // the cached copy would otherwise keep the old name
                // until the next cold start.
                Task { await SubscribedSubredditsCache.shared.invalidate() }
            }
        }
        .sheet(item: $sharingFeedURL) { shareable in
            ActivityShareSheet(items: [shareable.url.absoluteString])
        }
        .sheet(isPresented: $showingCompose) {
            NavigationStack {
                ComposePostScreen(subreddit: subreddit, repository: repository, initialType: composeKind) {
                    showingCompose = false
                    Task { await load() }
                }
            }
        }
        .sheet(item: $reportTarget) { target in
            ReportSheet(fullname: target.name, repository: repository) {
                reportTarget = nil
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
        .apolloFlairActionSheet(
            isPresented: $flairTargetPost.isPresent(),
            subreddit: flairTargetPost?.subreddit ?? subreddit,
            repository: repository,
            linkFullname: flairTargetPost?.name,
            isModerator: isModerator,
            onChanged: { Task { await load() } }
        )
        .apolloFlairActionSheet(
            isPresented: $showingUserFlair,
            subreddit: subreddit,
            repository: repository,
            username: signedInUsername ?? "",
            isModerator: isModerator
        )
        .task {
            // SwiftUI re-runs `.task` on reappear, not only on first
            // creation, so without a guard a swipe back would refetch
            // and flash/reset the list. Loading only when nothing is
            // shown makes a pop feel instant; every deliberate reload
            // path (pull-to-refresh, sort/timeframe/subreddit/sign-in
            // change) calls `load()` directly and is unaffected. Every
            // fetch here is guarded, including highlights and identity.
            // A forward swipe builds a new instance, so `@State` alone
            // can't tell us we were just here; see `FeedSnapshotCache`.
            // Restore first, then only fetch what the restore did not
            // provide.
            if !hasLoadedOnce, posts.isEmpty,
               let cached = FeedSnapshotCache.shared.snapshot(for: snapshotKey) {
                listing.restore(posts: cached.posts, afterToken: cached.afterToken, reachedEnd: cached.reachedEnd)
                highlightPosts = cached.highlights
                scrapedHighlights = cached.scrapedHighlights
                subredditInfo = cached.subredditInfo
                isModerator = cached.isModerator
                signedInUsername = cached.signedInUsername
                hasLoadedOnce = true
            }
            if posts.isEmpty {
                await load()
            }
            if !hasLoadedOnce {
                hasLoadedOnce = true
                await checkModeratorStatus()
                await loadCommunityHighlights()
                signedInUsername = try? await repository.fetchIdentity().name
            } else {
                // A restored or re-shown feed takes the highlights cache, which
                // also holds a Full-mode scrape that finished after the snapshot.
                await loadCommunityHighlights()
            }
            storeSnapshot()
        }
        .refreshable {
            async let highlights: Void = loadCommunityHighlights(force: true)
            await load()
            await highlights
        }
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

    /// The carousel's cards.
    private var carouselPosts: [RedditPost] { highlightPosts }

    private var carouselScrape: [ScrapedHighlight] {
        scrapedHighlights.count > carouselPosts.count ? scrapedHighlights : []
    }

    /// The feed without the pinned rows the carousel already shows, as Reborn
    /// collapses them while Community Highlights is on.
    private var feedPosts: [RedditPost] {
        let carousel = carouselPosts
        let scrape = carouselScrape
        guard !carousel.isEmpty || !scrape.isEmpty else { return posts }
        let shown = CommunityHighlights.feedRowIDsShownInCarousel(
            carouselPosts: scrape.isEmpty ? carousel : [], scrapedPermalinks: scrape.map(\.permalink))
        return posts.filter { !CommunityHighlights.feedHides($0, shownInCarousel: shown) }
    }

    @ViewBuilder
    func feedRow(for post: RedditPost) -> some View {
        PostRow(
            post: post,
            repository: repository,
            displayStyle: effectivePostDisplayStyle,
            isAggregateFeed: isAggregateFeed,
            onSubredditTap: { jumpDestination = .subreddit(post.subreddit) },
            onAuthorTap: { jumpDestination = .user(post.author) },
            onCommentsTap: {
                jumpToCommentsOnOpen = true
                selectedPost = post
            },
            moreMenu: { AnyView(postContextMenu(for: post)) }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // Releasing the info-row magnifier isn't a tap on the row.
            guard !InfoRowHoldRecognizer.tapFollowsHold else { return }
            jumpToCommentsOnOpen = false
            selectedPost = post
        }
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
        .apolloSwipeActions(settings: swipeSettings, subject: SwipeSubject(post: post)) { action in
            Task { await handleSwipeAction(action, on: post) }
        }
        .contextMenu {
            postContextMenu(for: post)
        } preview: {
            // "3D Touch Marks Read" (`threeDTouchMarksRead`): the
            // context-menu preview is the modern equivalent of
            // Apollo's 3D Touch peek.
            PostPeekPreview(post: post, markRead: generalSettings.threeDTouchMarksRead)
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

    /// Reborn Action Menus (#1131, context `feed`): the nav-bar •••
    /// rows keyed by their accessibility identifiers.
    static let feedMenuItemIDs: [String: String] = [
        "feed.overflow.galleryView": "spec.GalleryView",
        "feed.overflow.subscribeToggle": "subscribe",
        "feed.overflow.favoriteToggle": "favorite",
        "feed.overflow.hideReadToggle": "hide-read",
        "feed.overflow.sidebar": "sidebar",
        "feed.overflow.rules": "rules",
        "feed.overflow.filterSubreddit": "filter-subreddit",
        "feed.overflow.addToMultireddit": "multireddit",
        "feed.overflow.compactToggle": "post-size",
        "feed.overflow.setUserFlair": "user-flair",
        "feed.overflow.viewModerators": "moderators",
        "feed.overflow.share": "share",
        "feed.overflow.subredditNotifications": "notifications",
    ]

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

    /// The feed's own URL, for the "•••" menu's Share row. Honors
    /// `shareLinkHost` like every other share in the app.
    var feedShareURL: ShareableURL {
        let path: String
        if let multiredditPath {
            path = multiredditPath
        } else if subreddit.isEmpty {
            path = "/"
        } else {
            path = "/r/\(subreddit)"
        }
        return ShareableURL(ShareLinkBuilder.url(
            forPermalinkPath: path,
            host: generalSettings.effectiveShareLinkHost))
    }

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

    /// Backs the "Save GIFs as…" (ask each time) context-menu rows:
    /// bypasses `GIFSaveService.save(format:)`'s automatic/always
    /// branching and calls the concrete saver directly.
    func saveGIF(_ gifURL: URL, asVideo: Bool) async {
        downloadTitle = "Save GIF"
        do {
            if asVideo {
                try await GIFSaveService.saveAsVideo(gifURL: gifURL, useApolloAlbum: generalSettings.saveToApolloAlbum)
            } else {
                try await GIFSaveService.saveAsGIF(gifURL: gifURL, useApolloAlbum: generalSettings.saveToApolloAlbum)
            }
            downloadMessage = "Saved to your photo library."
        } catch {
            downloadMessage = error.localizedDescription
        }
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

/// The context-menu (Haptic Touch "peek") preview for a feed row.
/// Its own view so "3D Touch Marks Read" fires exactly once when the
/// peek appears, rather than on every row re-render.
private struct PostPeekPreview: View {
    let post: RedditPost
    let markRead: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(post.title)
                .font(.headline)
                .multilineTextAlignment(.leading)
            if let selftext = post.selftext, !selftext.isEmpty {
                Text(selftext)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(12)
            }
            Text("r/\(post.subreddit) · u/\(post.author)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: 340, alignment: .leading)
        .onAppear {
            guard markRead else { return }
            ReadPostStore.markRead(post.name)
        }
    }
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
