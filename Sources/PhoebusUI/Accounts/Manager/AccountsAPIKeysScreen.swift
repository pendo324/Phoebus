import SwiftUI
import PhoebusCore

/// Reborn's "Accounts & API Keys" screen (Apollo Reborn → Setup).
///
/// Five sections in order: Default API Keys, Kagi Search, Sign-In,
/// Experimental, Extras. Section 1's seven fields are the
/// `CustomAPISettingsScreen` content, embedded here.
public struct AccountsAPIKeysScreen: View {
    let accountManager: AccountManager

    @Setting(CustomAPISettingsStore.storage) private var settings
    @Setting(AccountSettingsScope.enabledStorage) private var separateSettingsPerAccount
    @State private var isShowingWebSessionLogin = false
    @StateObject private var youTube = YouTubeAccount.shared
    @State private var isShowingYouTubeSignIn = false
    @State private var isShowingYouTubeImport = false
    @State private var isConfirmingYouTubeSignOut = false
    @State private var isShowingGlobalDefaults = false
    @State private var overridesToCopy: String?
    @State private var isConfirmingReset = false
    /// Re-renders the section when the account or editing layer changes.
    @State private var scopeRevision = 0

    public init(accountManager: AccountManager) {
        self.accountManager = accountManager
    }

    public var body: some View {
        perAccountSettingsPresentations(List {
            apiKeysSection
            kagiSection
            signInSection
            perAccountSettingsSection
            experimentalSection
            youTubeSection
            extrasSection
        })
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

    /// Reborn "Kagi Search" (#1305): the Session Link behind the Search tab's
    /// Kagi mode. It lives in the Keychain, not in the settings store.
    private var kagiSection: some View {
        Section {
            KagiSessionLinkRow()
                .apolloSearchRow("Kagi Session Link", lastBeforeFooter: true)
        } header: {
            Text("Kagi Search")
                .apolloSectionHeader()
        } footer: {
            Text("For Kagi subscribers. Each page of Kagi results counts as one search on your Kagi plan. Clear the field to remove the link.")
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

    /// "Separate Settings per Account" (Phoebus-only): global defaults, plus
    /// per account the settings changed while signed in to it.
    private var perAccountSettingsSection: some View {
        let _ = scopeRevision
        let account = AccountSettingsScope.activeAccount
        let otherAccounts = accountManager.accounts.map(\.username).filter { $0 != account }
        let canCopy = account != nil && !otherAccounts.isEmpty
        return Section {
            SettingsDetailToggle("Separate Settings per Account",
                                 detail: "Settings you change apply to the current account only. Other accounts keep the global defaults.",
                                 isOn: $separateSettingsPerAccount.binding)
                .accessibilityIdentifier("accounts.perAccountSettings")
                .apolloSearchRow("Separate Settings per Account",
                                 lastBeforeFooter: !separateSettingsPerAccount)
            if separateSettingsPerAccount {
                if AccountSettingsScope.isEditingGlobalDefaults {
                    Text("Editing the global defaults.")
                        .foregroundStyle(.secondary)
                        .apolloPlainSettingsRowInsets(rule: false)
                } else {
                    Button("Edit Global Defaults") { isShowingGlobalDefaults = true }
                        .accessibilityIdentifier("accounts.perAccountSettings.editGlobalDefaults")
                        .apolloPlainSettingsRowInsets()
                    Menu {
                        ForEach(otherAccounts, id: \.self) { username in
                            Button(username) { overridesToCopy = username }
                                .accessibilityIdentifier("accounts.perAccountSettings.copyFrom.\(username)")
                        }
                    } label: {
                        Text("Copy Overrides from…")
                            // A Menu label keeps the primary colour when disabled.
                            .foregroundStyle(canCopy ? Color.apolloAccent : Color.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .disabled(!canCopy)
                    .accessibilityIdentifier("accounts.perAccountSettings.copyFrom")
                    .apolloPlainSettingsRowInsets()
                    Button("Reset This Account's Overrides", role: .destructive) { isConfirmingReset = true }
                        .disabled(account == nil)
                        .accessibilityIdentifier("accounts.perAccountSettings.reset")
                        .apolloPlainSettingsRowInsets(rule: false)
                }
            }
        } header: {
            Text("Settings per Account")
                .apolloSectionHeader()
        } footer: {
            Text(perAccountSettingsFooter(account: account))
                .apolloSectionFooter()
        }
    }

    /// The section's sheet and dialogs, hosted on the list: on a Section
    /// they attach to its rows and close as soon as those rows change.
    private func perAccountSettingsPresentations(_ content: some View) -> some View {
        let account = AccountSettingsScope.activeAccount
        return content
            .onReceive(NotificationCenter.default.publisher(for: AccountSettingsScope.didChangeNotification)) { _ in
                scopeRevision &+= 1
            }
            .sheet(isPresented: $isShowingGlobalDefaults) {
                GlobalDefaultsSettingsSheet(accountManager: accountManager, isPresented: $isShowingGlobalDefaults)
            }
            .confirmationDialog("Copy \(overridesToCopy ?? "")'s settings to \(account ?? "")?",
                                isPresented: Binding(get: { overridesToCopy != nil },
                                                     set: { if !$0 { overridesToCopy = nil } }),
                                titleVisibility: .visible) {
                Button("Copy Overrides", role: .destructive) {
                    if let source = overridesToCopy, let account {
                        AccountSettingsOverrides.copy(from: source, to: account)
                    }
                    overridesToCopy = nil
                }
                .accessibilityIdentifier("accounts.perAccountSettings.copyFrom.confirm")
            } message: {
                Text("This account's own overrides are replaced.")
            }
            .confirmationDialog("Reset \(account ?? "")'s settings to the global defaults?",
                                isPresented: $isConfirmingReset, titleVisibility: .visible) {
                Button("Reset Overrides", role: .destructive) {
                    if let account { AccountSettingsOverrides.removeAll(for: account) }
                }
                .accessibilityIdentifier("accounts.perAccountSettings.reset.confirm")
            }
    }

    private func perAccountSettingsFooter(account: String?) -> String {
        guard separateSettingsPerAccount else {
            return "When on, each account keeps its own settings on top of the global defaults."
        }
        guard let account else { return "Signed out, Settings changes the global defaults." }
        return "Changes in Settings now apply to \(account) only. A dot marks a row set for this account; long-press it to use the global default. API keys, passcode, backups and notifications stay global."
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

/// The Session Link field: saved when editing ends, cleared by emptying it.
/// Anything that isn't a Session Link is refused and the saved one shown
/// again; a saved link Kagi turns away is flagged.
private struct KagiSessionLinkRow: View {
    @State private var draft = KagiSession.token ?? ""
    @State private var notice: KagiSessionLinkSheet.Notice?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ApolloSettingsTextFieldRow("Kagi Session Link", placeholder: "https://kagi.com/search?token=\u{2026}",
                                       text: $draft, secure: true, keyboard: .URL)
                .onSubmit(commit)
                .accessibilityIdentifier("settings.kagiSessionLink")
            Text("Search Reddit with Kagi from the Search tab's magnifier. Copy it from Kagi \u{2192} Settings \u{2192} Account \u{2192} Session Link.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onDisappear(perform: commit)
        .onReceive(NotificationCenter.default.publisher(for: .kagiSessionLinkChanged)) { _ in
            draft = KagiSession.token ?? ""
        }
        .alert(notice?.title ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } }),
               presenting: notice) { _ in
            Button("OK", role: .cancel) {}
        } message: { notice in
            Text(notice.message)
        }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = KagiSession.token
        if trimmed.isEmpty {
            draft = ""
            if current != nil { KagiSession.setToken(nil) }
            return
        }
        guard let token = KagiSearch.normalizeSessionToken(trimmed) else {
            draft = current ?? ""
            notice = .notALink
            return
        }
        draft = token
        guard token != current else { return }
        guard KagiSession.setToken(token) else {
            draft = current ?? ""
            notice = .keychain
            return
        }
        // Saved either way; warn if Kagi turns it away, so a bad paste doesn't
        // only show up later as "Kagi Session Expired" in the Search tab.
        Task {
            if await KagiSearch.checkSession(token: token).result == .rejected { notice = .rejected }
        }
    }
}
