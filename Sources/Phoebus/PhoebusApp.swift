import SwiftUI
import PhoebusCore
import PhoebusUI

@main
struct PhoebusApp: App {
    @StateObject private var accountManager = AccountManager()
    @State private var isSignedIn = false
    /// Live copy of the selected theme so a change re-renders the app.
    @State private var theme = ThemeStore.load()
    @State private var themeRevision = 0
    @State private var checkedPersistedLogin = false
    init() {
        // Local crash recording first, so it covers everything after.
        CrashRecorder.start()

        // Applies user-configured Custom API settings before anything
        // else touches RedditOAuthConfig/RedditAPIClient.
        CustomAPISettingsStore.applyPersisted()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !checkedPersistedLogin {
                    ProgressView()
                        .task {
                            // Migrate the single legacy Keychain slot into AccountStore before
                            // checking isSignedIn.
                            await accountManager.migrateLegacyCredentialIfNeeded()
                            isSignedIn = await accountManager.isSignedIn
                            checkedPersistedLogin = true
                        }
                } else if isSignedIn {
                    MainTabView(
                        repository: accountManager.repository,
                        authClient: accountManager.authClient,
                        accountManager: accountManager,
                        onSignOut: { isSignedIn = false },
                    )
                    // Rebuilds MainTabView's whole subtree whenever
                    // the active account changes, matching Apollo's
                    // "switching accounts returns to the feed" behavior.
                    .id(accountManager.activeIndex)
                } else {
                    NavigationStack {
                        LoginScreen(auth: accountManager.authClient, accountManager: accountManager) {
                            isSignedIn = true
                        }
                    }
                }
            }
            .tint(Color(hex: theme.accentColorHex))
            // A theme's `isDark` sets the color scheme too, since
            // Apollo's themes are genuine light/dark appearances, not
            // just accent colours.
            .preferredColorScheme(theme.isDark ? .dark : .light)
            // A gallery theme's value is its 22 compiled surface
            // tokens, not just its accent.
            .environment(\.apolloTheme, ApolloThemeColors(
                // Read with the revision, so editing the active custom theme
                // recompiles it here at once.
                compiled: themeRevision >= 0 ? ThemeAppearance.compiledTheme(for: theme) : nil,
                mode: theme.isDark ? .dark : .light
            ))
            // A custom theme's font, app-wide.
            .fontDesign(ThemeAppearance.fontDesign(for: theme))
            .onReceive(NotificationCenter.default.publisher(for: CustomThemeStore.didChangeNotification)) { _ in
                guard CustomTheme.parse(themeID: theme.id) != nil else { return }
                NotificationCenter.default.post(name: ThemeStore.didChangeNotification, object: nil)
            }
            .onAppear {
                ThemeAppearance.apply(theme)
                // iPad "Move Tab Bar to Bottom" (dormant on iPhone).
                IPadTabBarBottom.install()
            }
            .onReceive(NotificationCenter.default.publisher(for: ThemeStore.didChangeNotification)) { _ in
                theme = ThemeStore.load()
                if CustomTheme.parse(themeID: theme.id) != nil { themeRevision &+= 1 }
                // Applied on every change, including back to a
                // built-in theme: the appearance proxies are global
                // and sticky.
                ThemeAppearance.apply(ThemeStore.load())
            }
            // Pure Black Dark Mode as a genuine app-wide background override.
            .apolloPureBlackBackground(PureBlackSettingsStore.load())
            // "Use System Text Size"/"Text Size": when off,
            // `textSizeScale` (0.8...1.4, default 1.0) maps onto
            // SwiftUI's `dynamicTypeSize`. When on (default), no
            // modifier is applied, so the OS's own setting governs.
            .apolloTextSizeOverride()
        }
    }
}

/// Root tab bar. Apollo's tab bar is exactly five tabs: "Posts", "Inbox",
/// the signed-in user's own username, "Search" and "Settings".
struct MainTabView: View {
    @State private var showingAccountsForReSignIn = false
    let repository: RedditRepository
    let authClient: RedditAuthClient
    let accountManager: AccountManager
    let onSignOut: () -> Void
    @State private var subredditsDestination: SubredditsRootDestination?
    /// The other tabs' stacks get a path too, so every `SettingsLink`
    /// push is tracked: a back snapshot for the page swipes, and refused
    /// while a back swipe is in progress (a tap as the finger lifts).
    @StateObject private var postsNavigation = SettingsNavigationModel(tab: 0)
    /// "Liquid Glass Tab Bar"; see `LiquidGlassTabBar`. Gated on the
    /// user's setting; `false` keeps stock `TabView` behavior.
    @Setting(GeneralSettingsStore.storage) private var generalSettings
    @State private var liquidGlassSelection = 0
    private static let tabBarSwipeNavigationAtLaunch = GeneralSettingsStore.load().tabBarSwipeNavigation
    /// "Remember Subreddit"/"Default Reddit to Load" push the launch
    /// destination onto the Posts tab's stack. Guards the one-time
    /// auto-push in `postsTab`'s `.task` so it only fires once per
    /// cold launch.
    @State private var appliedInitialFeedDestination = false
    var body: some View {
        // One tab bar, and it is the system's: a real `TabView`, not a
        // hand-drawn floating pill. See `LiquidGlassTabBar`.
        //
        // No enclosing `ZStack`: SwiftUI only bridges a `TabView` to a
        // real `UITabBarController` when it is the scene root; inside
        // a `ZStack` it degrades to a plain container with no tab bar.
        // The floating-post-tabs overlay is an `.overlay` instead.
        tabBar
            // Header Style, for every screen's scroll views.
            .applyHeaderStyle()
        // Live-apply General settings changes (e.g. the Liquid Glass toggle).
        .onReceive(NotificationCenter.default.publisher(
            for: GeneralSettingsStore.didChangeNotification)) { _ in
        }
        .sheet(isPresented: $showingAccountsForReSignIn) {
            NavigationStack { AccountManagerScreen(accountManager: accountManager) }
        }
        // Lets `PollView` run the one-time cookie harvest an OAuth
        // account needs before Reddit will accept a poll vote.
        .environment(\.accountManager, accountManager)
    }

    /// The five tabs, through the system tab bar. `LiquidGlassTabBar`
    /// is a thin wrapper over SwiftUI's own `TabView`/`Tab` plus
    /// `tabBarMinimizeBehavior`.
    private var tabBar: some View {
        LiquidGlassTabBar(
            tabs: [
                .init(id: 0, title: "Posts", systemImage: "doc.text", stockIcon: "tab-bar-posts") { postsTab },
            ],
            selection: $liquidGlassSelection,
            hideBarsOnScroll: generalSettings.hideBarsOnScroll,
            hideTopBarOnScroll: generalSettings.hideTopBarOnScroll,
            classicScrollBehavior: generalSettings.classicTabBarScrollBehavior,
            iconOnly: generalSettings.iconOnlyTabBar,
            hideStyle: generalSettings.tabBarHideStyle
        )
        .onChange(of: liquidGlassSelection) { _, tab in
            // Each tab keeps its own forward history.
            ForwardNavigationStore.shared.currentTab = tab
        }
        // "Swipe Tab Bar to Navigate" (#1075), read once per launch.
        .background {
            if Self.tabBarSwipeNavigationAtLaunch {
                TabBarSwipeNavigationProbe().frame(width: 0, height: 0)
            }
        }
    }

    private var postsTab: some View {
        NavigationStack(path: $postsNavigation.path) {
            SubredditsRootScreen(repository: repository) { destination in
                subredditsDestination = destination
            }
            .apolloSettingsNavigation(postsNavigation)
            // The Subreddits list is a real member of this stack, so a feed pushed
            // from it must be swipe-back-able to it, as in Apollo.
            //
            // The back pan refuses to begin unless a snapshot of the
            // covered screen exists, taken by `apolloTracksForwardNavigation`.
            .apolloTracksForwardNavigation($subredditsDestination)
            // Carries the forward swipe on the root itself: having
            // swiped back to this list, swiping forward redoes the push.
            .apolloForwardSwipe()
            .navigationDestination(item: $subredditsDestination) { destination in
                feedScreen(for: destination)
            }
            // Re-tapping Posts (#1153): first re-tap scrolls to top; a
            // re-tap already at the top goes back one page.
            .apolloScrollsThenPopsOnTabReselection(tab: 0)
            // Pushes the "Remember Subreddit"/"Default Reddit to Load"
            // launch destination once per cold launch; a deep link or
            // in-progress manual navigation always wins.
            .task {
                guard !appliedInitialFeedDestination else { return }
                appliedInitialFeedDestination = true
                if let destination = initialFeedDestination() {
                    subredditsDestination = destination
                }
            }
            // "Ability to swipe forward/back pages". Applied once per
            // root tab `NavigationStack`, where
            // `interactivePopGestureRecognizer` actually lives.
            .apolloInteractiveSwipeNavigation()
        }
    }

    /// Resolves the launch destination per
    /// `GeneralSettings.rememberSubredditToLoad`/`defaultRedditToLoad`.
    /// `nil` means "stay at the bare Subreddits root".
    private func initialFeedDestination() -> SubredditsRootDestination? {
        let settings = GeneralSettingsStore.load()
        if settings.rememberSubredditToLoad, let last = LastViewedSubredditStore.load() {
            return Self.rootDestination(for: last)
        }
        switch DefaultRedditToLoadChoice(stored: settings.defaultRedditToLoad) {
        case .redditsList: return nil
        case .home: return .home
        case .popular: return .popular
        case .all: return .all
        case .subreddit(let name): return Self.rootDestination(forSubredditName: name)
        case .multireddit(let path, let name): return .multireddit(path: path, name: name)
        }
    }

    private static func rootDestination(for stored: LastViewedSubredditStore.Destination) -> SubredditsRootDestination {
        switch stored {
        case .home: return .home
        case .popular: return .popular
        case .all: return .all
        case .moderator: return .moderator
        case .subreddit(let name): return .subreddit(name)
        case .multireddit(let path, let name): return .multireddit(path: path, name: name)
        }
    }

    /// Maps a bare typed-in name onto the same pseudo-feed
    /// destinations `SubredditsRootScreen`'s shortcut rows use, so
    /// typing "all"/"popular"/"mod" behaves like tapping those rows.
    private static func rootDestination(forSubredditName name: String) -> SubredditsRootDestination {
        switch name.lowercased() {
        case "all": return .all
        case "popular": return .popular
        case "mod", "moderator": return .moderator
        default: return .subreddit(name)
        }
    }
    /// Resolves a `SubredditsRootScreen` selection into the right
    /// pushed feed. "Popular"/"All"/"Moderator Posts" map to Reddit's
    /// well-known pseudo-subreddits (`r/popular`, `r/all`) or the
    /// moderator-posts multi-subreddit path (`r/mod`).
    ///
    /// Also records this destination as the "last viewed feed" every
    /// time one is shown, the one funnel point every tap-driven
    /// navigation into a feed passes through.
    @ViewBuilder
    private func feedScreen(for destination: SubredditsRootDestination) -> some View {
        Group {
            switch destination {
            case .home:
                FeedScreen(subreddit: "", repository: repository)
            case .popular:
                FeedScreen(subreddit: "popular", repository: repository)
            case .all:
                FeedScreen(subreddit: "all", repository: repository)
            case .moderator:
                FeedScreen(subreddit: "mod", repository: repository)
            case .subreddit(let name):
                FeedScreen(subreddit: name, repository: repository)
            case .multireddit(let path, let name):
                FeedScreen(multiredditPath: path, displayName: name, repository: repository)
            }
        }
        .onAppear { Self.recordLastViewed(destination) }
    }

    private static func recordLastViewed(_ destination: SubredditsRootDestination) {
        switch destination {
        case .home: LastViewedSubredditStore.record(.home)
        case .popular: LastViewedSubredditStore.record(.popular)
        case .all: LastViewedSubredditStore.record(.all)
        case .moderator: LastViewedSubredditStore.record(.moderator)
        case .subreddit(let name): LastViewedSubredditStore.recordSubreddit(name)
        case .multireddit(let path, let name): LastViewedSubredditStore.recordMultireddit(path: path, name: name)
        }
    }
}
