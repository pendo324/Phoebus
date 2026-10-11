import SwiftUI
import PhoebusCore

/// Reborn's "Accounts & API Keys" screen (Apollo Reborn → Setup).
///
/// Four sections in order: Default API Keys, Sign-In, Experimental, Extras.
/// Section 1's seven fields are the `CustomAPISettingsScreen` content,
/// embedded here.
public struct AccountsAPIKeysScreen: View {
    let accountManager: AccountManager

    @Setting(CustomAPISettingsStore.storage) private var settings
    @State private var isShowingWebSessionLogin = false
    @StateObject private var youTube = YouTubeAccount.shared
    @State private var isShowingYouTubeSignIn = false
    @State private var isShowingYouTubeImport = false
    @State private var isConfirmingYouTubeSignOut = false

    public init(accountManager: AccountManager) {
        self.accountManager = accountManager
    }

    public var body: some View {
        List {
            apiKeysSection
            signInSection
            experimentalSection
            youTubeSection
            extrasSection
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle("Accounts & API Keys")
        .navigationBarTitleDisplayModeIfAvailable()
    }

    /// The seven Default API Keys fields, with Reborn's labels.
    @ViewBuilder
    private var apiKeysSection: some View {
        // One section, "Default API Keys", seven fields in this order, one footer.
        Section {
            keyField("Reddit API Key", text: $settings.redditClientID)
            keyField("Reddit API Secret", placeholder: "Required for \"Web app\" clients; empty otherwise", text: $settings.redditClientSecret)
            keyField("Imgur API Key", text: $settings.imgurClientID)
            keyField("Image Chest API Key", text: $settings.imgChestAPIKey)
            keyField("Giphy API Key", text: $settings.giphyAPIKey)
            keyField("Redirect URI", placeholder: "apollo://reddit-oauth", text: $settings.redditRedirectURI, isURL: true)
            keyField("User Agent", placeholder: "ios:com.christianselig.Apollo:v1.15.11 (by /u/iamthatis)", text: $settings.userAgent, lastBeforeFooter: true)
        } header: {
            Text("Default API Keys")
                .apolloSectionHeader()
        } footer: {
            Text("Default credentials, used by any account without a per-account override. Reddit is required to sign in; the rest enable image uploads and the GIF picker.")
                    .apolloSectionFooter()
        }
    }

    /// Sign-In rows in order: Universal OAuth Sign-In, reddit.com Web Sign-In,
    /// Can't sign in?, Giphy & Image Chest API Key Setup.
    private var signInSection: some View {
        Section {
            SettingsDetailToggle("Universal OAuth Sign-In",
                                 detail: "Signs in with an in-app web view so any Redirect URI works, including http/https (\"Web app\" Reddit API clients). Turn off for Phoebus's native sign-in.",
                                 isOn: $settings.useCustomOAuthSignIn)
            .apolloSearchRow("Universal OAuth Sign-In")
            // A status row that becomes the "Set Up reddit.com Web Sign-In" action row
            // once an API-key account exists; disabled subtitle is "Sign in to a Reddit
            // account first."
            if accountManager.accounts.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("reddit.com Web Sign-In")
                        .foregroundStyle(.secondary)
                    Text("Sign in to a Reddit account first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .apolloPlainSettingsRowInsets()
            } else {
                Button("Set Up reddit.com Web Sign-In") {
                    isShowingWebSessionLogin = true
                }
                .apolloSearchRow("Set Up reddit.com Web Sign-In")
            }
            SettingsLink("Can't sign in?") {
                SignInTroubleshootingScreen()
            }
            .apolloSearchRow("Can't sign in?")
            SettingsLink("Giphy & Image Chest API Key Setup") {
                APIKeySetupGuideScreen()
            }
            .apolloSearchRow("Giphy & Image Chest API Key Setup", lastBeforeFooter: true)
        } header: {
            Text("Sign-In")
                .apolloSectionHeader()
        } footer: {
            Text("Choose how accounts sign in, or get help setting up your keys.")
                    .apolloSectionFooter()
        }
        .sheet(isPresented: $isShowingWebSessionLogin) {
            NavigationStack {
                WebSessionLoginScreen(
                    onSuccess: { credential in
                        accountManager.addWebSessionAccount(credential)
                        isShowingWebSessionLogin = false
                    },
                    onCancel: { isShowingWebSessionLogin = false }
                )
            }
        }
    }

    /// Experimental section; footer "Sign in to reddit.com instead of using API
    /// keys."
    ///
    /// Reborn's "Use Modern Reddit Chat" and "Use Modern Moderator Mail" rows are
    /// omitted: each toggles between two protocol implementations, and Phoebus has
    /// a single classic-inbox messaging surface and a single `ModmailListScreen`.
    private var experimentalSection: some View {
        Section {
            SettingsLink {
                AccountManagerScreen(accountManager: accountManager)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Web Session Accounts")
                    Text("Add or manage individual web-session accounts from the account switcher.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .apolloSearchRow("Web Session Accounts", lastBeforeFooter: true)
        } header: {
            Text("Experimental")
                .apolloSectionHeader()
        } footer: {
            Text("Sign in to reddit.com instead of using API keys.")
                    .apolloSectionFooter()
        }
    }

    /// Phoebus-only: signs the YouTube player in as the user's Google account.
    private var youTubeSection: some View {
        Section {
            if youTube.isSignedIn {
                HStack {
                    Text("Signed In")
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .apolloPlainSettingsRowInsets()
                Button("Sign Out of YouTube", role: .destructive) {
                    isConfirmingYouTubeSignOut = true
                }
                .accessibilityIdentifier("youtube.signOut")
                .apolloSearchRow("Sign Out of YouTube")
            } else {
                Button("Sign In to YouTube") {
                    isShowingYouTubeSignIn = true
                }
                .accessibilityIdentifier("youtube.signIn")
                .apolloSearchRow("Sign In to YouTube")
            }
            Button("Import YouTube Cookies") {
                isShowingYouTubeImport = true
            }
            .accessibilityIdentifier("youtube.importCookies")
            .apolloSearchRow("Import YouTube Cookies")
            Button("Open Cross-Website Tracking Setting") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .accessibilityIdentifier("youtube.openSettings")
            .apolloSearchRow("Open Cross-Website Tracking Setting", lastBeforeFooter: true)
        } header: {
            Text("YouTube")
                .apolloSectionHeader()
        } footer: {
            Text("Plays YouTube videos as your Google account: Premium without ads, watch history, age-restricted videos. Also turn on \"Allow Cross-Website Tracking\" for Phoebus in iOS Settings, or iOS hides the sign-in from the player. Kept apart from the in-app browser and Reddit.")
                .apolloSectionFooter()
        }
        .sheet(isPresented: $isShowingYouTubeSignIn) { YouTubeSignInSheet() }
        .sheet(isPresented: $isShowingYouTubeImport) { YouTubeImportCookiesSheet() }
        .confirmationDialog("Sign out of YouTube?", isPresented: $isConfirmingYouTubeSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Task { await youTube.signOut() }
            }
        }
        .task { await youTube.refresh() }
    }

    /// Extras section: one row, with Reborn's footer.
    private var extrasSection: some View {
        Section {
            SettingsLink("Copy Widget Setup Code") {
                WidgetSetupScreen()
            }
            .apolloSearchRow("Copy Widget Setup Code", lastBeforeFooter: true)
        } header: {
            Text("Extras")
                .apolloSectionHeader()
        } footer: {
            Text("Copy a code to set up the Phoebus home-screen widget.")
                    .apolloSectionFooter()
        }
    }

    private func keyField(_ label: String, placeholder: String? = nil, text: Binding<String?>, isURL: Bool = false, lastBeforeFooter: Bool = false) -> some View {
        ApolloSettingsTextFieldRow(label, placeholder: placeholder, text: Binding(
            get: { text.wrappedValue ?? "" },
            set: { text.wrappedValue = $0.isEmpty ? nil : $0 }
        ), keyboard: isURL ? .URL : .default)
        // Applied in the helper, not at the seven call sites: each
        // `keyField(...)` IS the Section's direct child, so the insets
        // land on the row itself.
        .apolloSearchRow(label, lastBeforeFooter: lastBeforeFooter)
    }
}
