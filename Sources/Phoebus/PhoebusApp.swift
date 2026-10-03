import SwiftUI
import PhoebusCore
import PhoebusUI

@main
struct PhoebusApp: App {
    // `AccountManager` owns the account list and rebuilds
    // `authClient`/`repository` whenever the active account changes.
    /// Enforces "Portrait Lock" / "Smart Rotation Lock": SwiftUI has
    /// no orientation hook, so UIKit must be asked via the app delegate.
    @UIApplicationDelegateAdaptor(ApolloAppDelegate.self) private var appDelegate
    @StateObject private var accountManager = AccountManager()
    @State private var isSignedIn = false
    /// Live copy of the selected theme so a change re-renders the app.
    @State private var theme = ThemeStore.load()
    @State private var themeRevision = 0
    @State private var checkedPersistedLogin = false
    @State private var pendingDeepLink: RedditURLTarget?

    /// Applies the "Automatic Switch Threshold" section: system
    /// following, the three switch modes, brightness threshold and
    /// schedule times. Preserves the user's theme family (light/dark
    /// pairs sharing a name) rather than dropping onto a stock default.
    private func applyAutomaticThemeSwitchIfNeeded() {
        ThemeAutoSwitch.applyIfNeeded()
    }

    init() {
        // Local crash recording first, so it covers everything after.
        CrashRecorder.start()

        // Applies user-configured Custom API settings before anything
        // else touches RedditOAuthConfig/RedditAPIClient.
        CustomAPISettingsStore.applyPersisted()

        // Automatic Backups: checked while the app is active (launch,
        // every return, a clock change, and hourly), as Reborn's.
        AutomaticBackupRunner.runIfDue()
        AutomaticBackupRunner.startActiveChecks()

        // Reddit Chat's token comes from a real browser load.
        ChatTokenWebMinter.install()
    }

    var body: some Scene {
        WindowGroup {
            // Security setting enforcement; see `AppLockGate`. Wraps
            // everything so the lock covers feed, comments, settings
            // and the account switcher alike.
            AppLockGate {
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
                        deepLink: $pendingDeepLink
                    )
                    // Rebuilds MainTabView's whole subtree whenever
                    // the active account changes, matching Apollo's
                    // "switching accounts returns to the feed" behavior.
                    .id(accountManager.activeIndex)
                    // "Save All Media" progress and result (#1048).
                    .saveAllMediaOverlay()
                } else {
                    NavigationStack {
                        LoginScreen(auth: accountManager.authClient, accountManager: accountManager) {
                            isSignedIn = true
                        }
                    }
                }
            }
            .onOpenURL { incoming in
                // Backend notification taps arrive as apollo://...
                let url = PushNotificationClient.appURL(fromApolloURL: incoming) ?? incoming
                // phoebus://open?url=... links from the Share Sheet action extension.
                if let target = RedditURLTarget.parseAppScheme(url) {
                    pendingDeepLink = target
                } else if let action = QuickAction.parse(url) {
                    // Reborn's `apollo://reborn/<action>` URLs.
                    QuickActionRouter.shared.pending = action
                }
            }
            // Siri/Shortcuts navigation: taken on sign-in (an intent can
            // launch the app before an account loads) and whenever an
            // intent sets a new target while the app is running.
            .task(id: isSignedIn) { consumeAppIntentNavigation() }
            .onReceive(NotificationCenter.default.publisher(for: AppIntentNavigation.didRequestNotification)) { _ in
                consumeAppIntentNavigation()
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
                applyAutomaticThemeSwitchIfNeeded()
            }
            // Re-evaluated on foreground and on a timer, so a
            // scheduled switch happens while the app is open.
            .onReceive(
                Timer.publish(every: 60, on: .main, in: .common).autoconnect()
            ) { _ in
                applyAutomaticThemeSwitchIfNeeded()
            }
            #if canImport(UIKit)
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.didBecomeActiveNotification)) { _ in
                applyAutomaticThemeSwitchIfNeeded()
            }
            // Live, as Apollo's: the brightness threshold and the
            // system's own light/dark change.
            .onReceive(NotificationCenter.default.publisher(
                for: UIScreen.brightnessDidChangeNotification)) { _ in
                applyAutomaticThemeSwitchIfNeeded()
            }
            .onAppear {
                SystemStyleObserver.start { applyAutomaticThemeSwitchIfNeeded() }
            }
            #endif
            // Turning Use System Light/Dark Mode (or another rule) on takes
            // effect at once.
            .onReceive(NotificationCenter.default.publisher(for: .apolloSettingsChanged)) { note in
                guard note.object as? String == ThemeAutoSwitchSettingsStore.defaultsKey else { return }
                ThemeAutoSwitch.clearOverride()
                applyAutomaticThemeSwitchIfNeeded()
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
            // "Enable Quick Switch": a nav-bar long-press that toggles themes.
            .apolloQuickSwitchGesture()
            // "Use System Text Size"/"Text Size": when off,
            // `textSizeScale` (0.8...1.4, default 1.0) maps onto
            // SwiftUI's `dynamicTypeSize`. When on (default), no
            // modifier is applied, so the OS's own setting governs.
            .apolloTextSizeOverride()
            }
        }
    }

    private func consumeAppIntentNavigation() {
        guard isSignedIn, let target = AppIntentNavigation.shared.pendingTarget else { return }
        pendingDeepLink = target
        AppIntentNavigation.shared.pendingTarget = nil
    }
}

/// Root tab bar. Apollo's tab bar is exactly five tabs: "Posts", "Inbox",
/// the signed-in user's own username, "Search" and "Settings".
struct MainTabView: View {
    @ObservedObject private var inboxBadge = InboxBadge.shared
    @State private var showingSessionExpired = false
    @State private var showingAccountsForReSignIn = false
    let repository: RedditRepository
    let authClient: RedditAuthClient
    let accountManager: AccountManager
    let onSignOut: () -> Void
    @Binding var deepLink: RedditURLTarget?
    @State private var subredditsDestination: SubredditsRootDestination?
    /// The Inbox tab's stack, path-driven like Settings so Apollo's page
    /// swipes work in it.
    @StateObject private var inboxNavigation = SettingsNavigationModel(tab: 1)
    /// The other tabs' stacks get a path too, so every `SettingsLink`
    /// push is tracked: a back snapshot for the page swipes, and refused
    /// while a back swipe is in progress (a tap as the finger lifts).
    @StateObject private var postsNavigation = SettingsNavigationModel(tab: 0)
    @StateObject private var profileNavigation = SettingsNavigationModel(tab: 2)
    @StateObject private var searchNavigation = SettingsNavigationModel(tab: 3)
    @State private var inAppBrowserURL: URL?
    /// A tapped link that is a plain image, shown in the app's own
    /// viewer instead of a web view. See `openedLink(_:)`.
    @State private var viewerImageURL: URL?
    /// Seeded from the signed-in account, then confirmed by
    /// `CurrentUserProfileLoader`'s `/api/v1/me` fetch, so the Profile
    /// tab doesn't show the literal word "Profile" while waiting.
    /// See `ProfileTabAvatar`.
    @StateObject private var profileTabAvatar = ProfileTabAvatar()
    @State private var currentUsername: String? =
        FavoriteSubredditsAccountContext.currentUsernameProvider()
    /// "Liquid Glass Tab Bar"; see `LiquidGlassTabBar`. Gated on the
    /// user's setting; `false` keeps stock `TabView` behavior.
    @Setting(GeneralSettingsStore.storage) private var generalSettings
    @State private var liquidGlassSelection = 0
    /// Path for the Settings tab's stack; see `SettingsNavigationModel`,
    /// which enables back/forward page swipes on Settings.
    @StateObject private var settingsNavigation = SettingsNavigationModel(tab: 4)
    @State private var showingSettingsShortcuts = false
    private static let tabBarSwipeNavigationAtLaunch = GeneralSettingsStore.load().tabBarSwipeNavigation
    /// "Floating Post Tabs"; see `FloatingPostTabsSettings`. One
    /// app-wide manager, installed into the environment and overlaid
    /// above the tab bar so bubbles float above every tab.
    @StateObject private var floatingPostTabsManager = FloatingPostTabsManager()
    @Setting(FloatingPostTabsSettingsStore.storage) private var floatingTabsSettings
    @ObservedObject private var selectText = SelectTextPresenter.shared
    /// "Remember Subreddit"/"Default Reddit to Load" push the launch
    /// destination onto the Posts tab's stack. Guards the one-time
    /// auto-push in `postsTab`'s `.task` so it only fires once per
    /// cold launch.
    @State private var appliedInitialFeedDestination = false

    @Environment(\.scenePhase) private var chatPollPhase

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
            // Select Text from a row swipe, on any screen.
            .sheet(item: $selectText.request) { request in
                SelectTextSheet(title: request.title, body: request.body) { selectText.request = nil }
            }
            .overlay(alignment: .bottom) {
                if floatingTabsSettings.enabled {
                    FloatingPostTabsOverlay(manager: floatingPostTabsManager, repository: repository)
                }
            }
        // Live-apply General settings changes (e.g. the Liquid Glass toggle).
        .onReceive(NotificationCenter.default.publisher(
            for: GeneralSettingsStore.didChangeNotification)) { _ in
        }
        .environment(\.floatingPostTabsManager, floatingPostTabsManager)
        // "Sign In to Upvote"/"Downvote"/"Reply" alerts, hosted once
        // at the tab-view root since the voting helpers have no view
        // of their own. See `SignInRequiredPresenter`.
        .apolloSignInRequiredAlert()
        // Reborn #1200: a refused refresh token (password change) asks
        // the user to sign in to the account again.
        .onReceive(NotificationCenter.default.publisher(for: .apolloSessionExpired)
            .receive(on: RunLoop.main)) { _ in
            showingSessionExpired = true
        }
        .alert("Session Expired", isPresented: $showingSessionExpired) {
            Button("Sign In") { showingAccountsForReSignIn = true }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Your Reddit session expired. Sign in again to load this account.")
        }
        .sheet(isPresented: $showingAccountsForReSignIn) {
            NavigationStack { AccountManagerScreen(accountManager: accountManager) }
        }
        // Lets `PollView` run the one-time cookie harvest an OAuth
        // account needs before Reddit will accept a poll vote.
        .environment(\.accountManager, accountManager)
        // Inbox tab badge (and Bark chat notifications, from the same
        // sync): polled while in the foreground, per account.
        .task(id: BadgePollKey(isActive: chatPollPhase == .active, repository: ObjectIdentifier(repository))) {
            if chatPollPhase == .active {
                let accounts = accountManager.accounts
                let username = accountManager.activeIndex.flatMap { accounts.indices.contains($0) ? accounts[$0].username : nil }
                InboxBadge.shared.start(repository: repository, username: username)
            } else {
                InboxBadge.shared.stop()
            }
        }
    }

    /// The five tabs, through the system tab bar. `LiquidGlassTabBar`
    /// is a thin wrapper over SwiftUI's own `TabView`/`Tab` plus
    /// `tabBarMinimizeBehavior`.
    private var tabBar: some View {
        LiquidGlassTabBar(
            tabs: [
                .init(id: 0, title: "Posts", systemImage: "doc.text", stockIcon: "tab-bar-posts") { postsTab },
                .init(id: 1, title: "Inbox", systemImage: "envelope", stockIcon: "tab-bar-inbox",
                      badge: InboxBadge.badgeText(inboxBadge.unreadCount)) { inboxTab },
                .init(id: 2, title: profileTabTitle, systemImage: "person.circle", stockIcon: "tab-bar-profile", customIcon: profileTabIcon) { profileTab },
                .init(id: 3, title: "Search", systemImage: "magnifyingglass", stockIcon: "tab-bar-search") { searchTab },
                .init(id: 4, title: "Settings", systemImage: "gearshape", stockIcon: "tab-bar-settings") { settingsTab },
            ],
            selection: $liquidGlassSelection,
            hideBarsOnScroll: generalSettings.hideBarsOnScroll,
            hideTopBarOnScroll: generalSettings.hideTopBarOnScroll,
            classicScrollBehavior: generalSettings.classicTabBarScrollBehavior,
            iconOnly: generalSettings.iconOnlyTabBar,
            hideStyle: generalSettings.tabBarHideStyle
        )
        .environment(\.openURL, OpenURLAction { url in
            openLink(url)
            return .handled
        })
        .apolloInAppBrowser(url: $inAppBrowserURL)
        .apolloImageViewer(url: $viewerImageURL)
        // Loads (and reloads on an account switch) the Profile tab's
        // avatar icon.
        .task(id: currentUsername) {
            await profileTabAvatar.load(username: currentUsername, repository: repository)
        }
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
        // Settings Shortcuts (#1150): hold the Settings tab.
        .background(TabItemLongPressProbe(index: 4, count: 5) {
            showingSettingsShortcuts = true
        }.frame(width: 0, height: 0))
        .apolloActionSheet(
            isPresented: $showingSettingsShortcuts,
            title: "Settings Shortcuts",
            rows: SettingsShortcutsStore.load().map { id in
                ApolloActionSheetRow(SettingsShortcutsStore.title(id),
                                     icon: SettingsShortcutsStore.systemImage(id),
                                     accessibilityIdentifier: "settingsShortcut.\(id)") {
                    openSettingsShortcut(id)
                }
            } + [ApolloActionSheetRow("Edit Shortcuts…", icon: "slider.horizontal.3",
                                      startsSection: true,
                                      accessibilityIdentifier: "settingsShortcut.edit") {
                    openSettingsShortcut("__edit")
                }])
        // Home-screen quick actions.
        .onAppear { performPendingQuickAction() }
        .onReceive(NotificationCenter.default.publisher(for: .apolloQuickAction)) { _ in
            performPendingQuickAction()
        }
        // Reddit rate-limiting an API-Key-Free account (#1220).
        .apolloRateLimitNotice()
        // A settings page asked for by route id (the PiP card's gear).
        .onReceive(NotificationCenter.default.publisher(for: .apolloOpenSettingsRoute)) { note in
            if let id = note.object as? String { openSettingsShortcut(id) }
        }
    }

    /// Opens a shortcut on the Settings tab's own stack, from its
    /// root, so back returns to Settings.
    private func openSettingsShortcut(_ id: String) {
        liquidGlassSelection = 4
        let view: AnyView = id == "__edit"
            ? AnyView(SettingsShortcutsScreen())
            : AnyView(SettingsShortcutDestination(id: id, accountManager: accountManager))
        // Pushed on the next turn: in the same turn as the tab switch and sheet
        // dismissal the stack isn't frontmost yet and the nav title comes out empty.
        settingsNavigation.path = []
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            settingsNavigation.path = [SettingsRoute(view: view)]
        }
    }

    /// Search / Inbox / Profile / Settings select their tab; Home
    /// opens the front-page feed on the Posts tab.
    private func performPendingQuickAction() {
        guard let action = QuickActionRouter.shared.pending else { return }
        QuickActionRouter.shared.pending = nil
        switch action {
        case .home:
            liquidGlassSelection = 0
            subredditsDestination = .home
        case .inbox: liquidGlassSelection = 1
        case .profile: liquidGlassSelection = 2
        case .search: liquidGlassSelection = 3
        case .settings: liquidGlassSelection = 4
        }
    }

    /// "Profile Picture Tab Icon": the Liquid Glass tab bar's
    /// custom-icon slot for the Profile tab. `nil` unless both the
    /// setting is on and a username has resolved.
    /// "Hide Username on Tab Bar": falls back to the generic label
    /// "Profile", also shown for an account with no resolved username.
    ///
    /// `iconOnlyTabBar` is a separate, stronger setting that blanks
    /// every tab's title; this one only replaces the username.
    private var profileTabTitle: String {
        if generalSettings.iconOnlyTabBar { return "" }
        if generalSettings.hideUsernameOnTabBar { return "Profile" }
        return currentUsername ?? "Profile"
    }

    private var profileTabIcon: UIImage? {
        guard generalSettings.useProfileAvatarTabIcon, currentUsername != nil else { return nil }
        return profileTabAvatar.image
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
            .navigationDestination(item: $deepLink) { target in
                // A second link while one is open replaces the item in place; a new
                // identity is needed or the old screen keeps its posts under the new title.
                DeepLinkDestination(target: target, repository: repository)
                    .id(target)
            }
            // Tracked like the Search tab's Google results: the back swipe needs a
            // snapshot of the covered screen.
            .apolloTracksForwardNavigation($deepLink)
            // A deep link must also select this tab: the destination
            // lives on the Posts tab only.
            .onChange(of: deepLink) { _, newValue in
                if newValue != nil { liquidGlassSelection = 0 }
            }
            // "Open Reddit Links in Apollo": a tapped reddit.com link
            // that maps onto a screen navigates natively here instead
            // of opening reddit.com in a web view. See `RedditLinkNavigator`.
            .onReceive(NotificationCenter.default.publisher(for: .apolloOpenRedditTarget)) { note in
                guard let target = note.userInfo?["target"] as? RedditURLTarget else { return }
                openNatively(target)
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
                guard deepLink == nil, subredditsDestination == nil else { return }
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

    /// Routes a tapped link. One choke point: every link in the app
    /// funnels through this `OpenURLAction`. Images open in the app's own
    /// viewer; the rest go where `LinkRouter` says, so a reddit.com link
    /// opens its post, subreddit or profile in the app ("Open Reddit
    /// Links in Apollo") instead of a browser.
    private func openLink(_ url: URL) {
        if InlineMediaDetector.isViewableImageURL(url) {
            viewerImageURL = url
            return
        }
        let route = LinkRouter.route(url)
        if case .native(let target) = route {
            openNatively(target)
            return
        }
        // "Open in App" (Bluesky, GitHub, Steam, YouTube) gets every
        // non-Reddit link first, wherever it was tapped.
        if DedicatedAppOpener.open(url, fallback: { openRoutedLink(route) }) { return }
        openRoutedLink(route)
    }

    private func openRoutedLink(_ route: LinkDestination) {
        switch route {
        case .native(let target):
            openNatively(target)
        case .twitterApp(let tweetURL, let client):
            openExternally(LinkRouter.twitterAppURL(for: tweetURL, client: client), fallback: tweetURL)
        case .externalBrowser(let webURL):
            let browser = ExternalBrowserSettingsStore.load().preferredBrowser
            openExternally(browser == .safari ? webURL : browser.translate(webURL), fallback: webURL)
        case .inApp(let webURL):
            inAppBrowserURL = webURL
        }
    }

    /// Hands `url` to the system, falling back to the in-app browser
    /// when there is nothing to open it with (the app isn't installed).
    private func openExternally(_ url: URL?, fallback: URL) {
        #if canImport(UIKit)
        guard let url else { inAppBrowserURL = fallback; return }
        UIApplication.shared.open(url) { opened in
            if !opened { inAppBrowserURL = fallback }
        }
        #else
        inAppBrowserURL = fallback
        #endif
    }

    /// Opens a Reddit link's screen on the tab it was tapped in, as
    /// Apollo pushes it onto the current stack.
    private func openNatively(_ target: RedditURLTarget) {
        // On top of the screen the user is on, keeping its back/forward
        // history; the tab's path only from a root screen.
        let repository = repository
        InPlaceRedditNavigation.shared.destination = { AnyView(DeepLinkDestination(target: $0, repository: repository)) }
        if InPlaceRedditNavigation.shared.open(target, inTab: liquidGlassSelection) { return }
        let route = SettingsRoute(view: AnyView(DeepLinkDestination(target: target, repository: repository)))
        switch liquidGlassSelection {
        case 1: inboxNavigation.path.append(route)
        case 2: profileNavigation.path.append(route)
        case 3: searchNavigation.path.append(route)
        case 4: settingsNavigation.path.append(route)
        default: postsNavigation.path.append(route)
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

    private var inboxTab: some View {
        NavigationStack(path: $inboxNavigation.path) {
            InboxScreen(repository: repository)
                .apolloSettingsNavigation(inboxNavigation)
                .apolloInteractiveSwipeNavigation()
                .apolloPopsToRootOnTabReselection(tab: 1)
        }
    }

    private var profileTab: some View {
        NavigationStack(path: $profileNavigation.path) {
            CurrentUserProfileLoader(repository: repository, accountManager: accountManager,
                                     resolvedUsername: $currentUsername)
                .apolloSettingsNavigation(profileNavigation)
                .apolloInteractiveSwipeNavigation()
                .apolloPopsToRootOnTabReselection(tab: 2)
        }
    }

    /// The Search tab's own pushed feed, kept separate from
    /// `subredditsDestination` so a tapped search result pushes onto
    /// the Search tab's own stack instead of a different tab's.
    @State private var searchDestination: SubredditsRootDestination?
    /// A Google search result opened from the Search tab.
    @State private var searchDeepLink: RedditURLTarget?

    private var searchTab: some View {
        NavigationStack(path: $searchNavigation.path) {
            SubredditSearchScreen(repository: repository, onSelect: { subreddit in
                searchDestination = .subreddit(subreddit.displayName)
            }, onOpenTarget: { target in
                // A Google result opens natively on this tab (#1260).
                searchDeepLink = target
            })
            .apolloSettingsNavigation(searchNavigation)
            .navigationDestination(item: $searchDeepLink) { target in
                DeepLinkDestination(target: target, repository: repository)
            }
            // Tracked like the other pushes: without a back snapshot the back swipe
            // refuses to begin.
            .apolloTracksForwardNavigation($searchDeepLink)
            // Same as the Posts tab root: needs a back snapshot so a
            // feed opened from a search result can be swiped back.
            .apolloTracksForwardNavigation($searchDestination)
            .apolloForwardSwipe()
            .navigationDestination(item: $searchDestination) { destination in
                feedScreen(for: destination)
            }
            .apolloInteractiveSwipeNavigation()
        }
        // Both halves: the path pops anything pushed with a value, and
        // clearing `searchDestination` pops the item-driven feed.
        .apolloPopsToRootOnTabReselection(tab: 3)
        .apolloPopsOnTabReselection(tab: 3, item: $searchDestination)
        // Stock Search re-tap at the root: scroll to top, then focus the field.
        .apolloScrollsThenPopsOnTabReselection(tab: 3, focusesSearchAtRoot: true)
    }

    private var settingsTab: some View {
        NavigationStack(path: $settingsNavigation.path) {
            SettingsScreen(repository: repository, accountManager: accountManager) {
                Task {
                    await authClient.signOut()
                    onSignOut()
                }
            }
            .apolloSettingsNavigation(settingsNavigation)
            .apolloInteractiveSwipeNavigation()
            // Inside the stack, not on it: attached outside, the
            // probe's owning view controller has no
            // `navigationController` to pop.
            .apolloPopsToRootOnTabReselection(tab: 4)
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

/// Resolves a share-extension deep link into the right screen. Post
/// links need the full `RedditPost` fetched (the link only carries
/// subreddit+id, matching how Reddit share URLs work); subreddit/user
/// links can navigate directly.
struct DeepLinkDestination: View {
    let target: RedditURLTarget
    let repository: RedditRepository

    var body: some View {
        switch target {
        case .subreddit(let name):
            FeedScreen(subreddit: name, repository: repository)
        case .user(let name):
            UserProfileScreen(username: name, repository: repository)
        case .post(let subreddit, let id):
            PostLinkLoader(subreddit: subreddit, postID: id, repository: repository)
        case .comment(let subreddit, let postID, let commentID):
            CommentTreeScreen(subreddit: subreddit, postID: postID, repository: repository, focusedCommentID: commentID)
        case .multireddit(let name):
            MultiredditLinkLoader(multiredditName: name, repository: repository)
        case .unknown:
            Text("Couldn't open this link").foregroundStyle(.secondary)
        }
    }
}

/// Resolves the `OpenMultireddit` SiriKit intent's navigation target.
/// Reddit has no "fetch one multireddit by name" endpoint, so this
/// fetches the user's full multireddit list and finds the matching one.
struct MultiredditLinkLoader: View {
    let multiredditName: String
    let repository: RedditRepository

    @State private var multireddit: RedditMultireddit?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let multireddit {
                FeedScreen(multireddit: multireddit, repository: repository)
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .task {
            do {
                let all = try await repository.fetchMultireddits()
                multireddit = all.first { $0.name.caseInsensitiveCompare(multiredditName) == .orderedSame }
                if multireddit == nil {
                    errorMessage = "Couldn't find multireddit \"\(multiredditName)\"."
                }
            } catch {
                errorMessage = "Couldn't load multireddits."
            }
        }
    }
}

struct PostLinkLoader: View {
    let subreddit: String
    let postID: String
    let repository: RedditRepository
    @State private var post: RedditPost?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let post {
                PostDetailScreen(post: post, repository: repository)
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            } else {
                ProgressView()
            }
        }
        .task {
            do {
                let data = try await repository.fetchComments(subreddit: subreddit, postID: postID)
                guard let json = try JSONSerialization.jsonObject(with: data) as? [Any],
                      let postListingRaw = json.first as? [String: Any],
                      let postData = postListingRaw["data"] as? [String: Any],
                      let children = postData["children"] as? [Any],
                      let firstChild = children.first as? [String: Any],
                      let childData = firstChild["data"] as? [String: Any] else {
                    errorMessage = "Couldn't load post"
                    return
                }
                let payload = try JSONSerialization.data(withJSONObject: childData)
                post = try JSONDecoder.reddit.decode(RedditPost.self, from: payload)
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }
}

/// Resolves the signed-in user's own username via /api/v1/me before
/// showing their profile, for the account tab.
struct CurrentUserProfileLoader: View {
    let repository: RedditRepository
    let accountManager: AccountManager
    @Binding var resolvedUsername: String?
    @State private var username: String?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let username {
                UserProfileScreen(username: username, repository: repository,
                                  isOwnProfile: true, accountManager: accountManager)
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            } else {
                ProgressView()
            }
        }
        .task {
            do {
                let name = try await repository.fetchIdentity().name
                username = name
                resolvedUsername = name
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }
}

private struct BadgePollKey: Equatable {
    let isActive: Bool
    let repository: ObjectIdentifier
}

#if canImport(UIKit)
/// Calls back when the system switches light/dark.
@MainActor
enum SystemStyleObserver {
    private static var started = false

    static func start(_ onChange: @escaping @MainActor () -> Void) {
        guard !started,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        started = true
        // The scene's traits are the system's; the app's forced style
        // lives on its windows.
        if #available(iOS 17.0, *) {
            scene.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (_: UIWindowScene, _: UITraitCollection) in
                onChange()
            }
        }
    }
}
#endif
