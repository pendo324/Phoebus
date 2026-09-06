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
    let repository: RedditRepository
    let authClient: RedditAuthClient
    let accountManager: AccountManager
    let onSignOut: () -> Void
    var body: some View {
            NavigationStack { AccountManagerScreen(accountManager: accountManager) }
        // Lets `PollView` run the one-time cookie harvest an OAuth
        // account needs before Reddit will accept a poll vote.
        .environment(\.accountManager, accountManager)
    }
}
