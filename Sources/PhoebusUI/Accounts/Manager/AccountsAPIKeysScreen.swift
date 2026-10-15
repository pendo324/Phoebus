import SwiftUI
import PhoebusCore

/// Reborn's "Accounts & API Keys" screen (Apollo Reborn → Setup), titled
/// API Keys & Sign-In here. Only the sign-in flow shows it as a screen of
/// its own; Settings draws the same sections inside Accounts & Security.
///
/// Sections in order: Default API Keys, Kagi Search, Sign-In, Separate
/// Settings per Account, YouTube. Section 1's seven fields are the
/// `CustomAPISettingsScreen` content, embedded here.
public struct AccountsAPIKeysScreen: View {
    let accountManager: AccountManager

    public init(accountManager: AccountManager) {
        self.accountManager = accountManager
    }

    public var body: some View {
        List {
            APIKeySections()
            SignInSections(accountManager: accountManager)
            PerAccountSettingsSections(accountManager: accountManager)
            YouTubeSections()
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle("API Keys & Sign-In")
        .navigationBarTitleDisplayModeIfAvailable()
    }
}

/// Default API Keys and Kagi Search.
struct APIKeySections: View {
    @Setting(CustomAPISettingsStore.storage) private var settings

    var body: some View {
        Group {
            apiKeysSection
            kagiSection
        }
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
            Text("API Keys")
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

/// Sign-In: the OAuth method, reddit.com web sign-in, and the two help screens.
struct SignInSections: View {
    @ObservedObject var accountManager: AccountManager
    @Setting(CustomAPISettingsStore.storage) private var settings
    @State private var isShowingWebSessionLogin = false
    @State private var isShowingSignedInChoice = false

    private var activeUsername: String? {
        guard let index = accountManager.activeIndex, index < accountManager.accounts.count else { return nil }
        return accountManager.accounts[index].username
    }

    private var activeHasSession: Bool {
        guard let index = accountManager.activeIndex, index < accountManager.accounts.count else { return false }
        return accountManager.accounts[index].webSession != nil
    }

    /// Sign-In rows in order: Universal OAuth Sign-In, reddit.com Web Sign-In,
    /// Can't sign in?, Giphy & Image Chest API Key Setup.
    var body: some View {
        Section {
            SettingsDetailToggle("Universal OAuth Sign-In",
                                 detail: "Signs in with an in-app web view so any Redirect URI works, including http/https (\"Web app\" Reddit API clients). Turn off for Phoebus's native sign-in.",
                                 isOn: $settings.useCustomOAuthSignIn)
            .apolloSearchRow("Universal OAuth Sign-In")
            webSignInRow
            SettingsDrillDownRow(destination: .signInTroubleshooting)
            SettingsDrillDownRow(destination: .apiKeySetupGuide, lastBeforeFooter: true)
        } header: {
            Text("Sign-In")
                .apolloSectionHeader()
        } footer: {
            Text(footer)
                    .apolloSectionFooter()
        }
    }

    private var footer: String {
        guard let username = activeUsername else {
            return "Choose how accounts sign in, or get help setting up your keys. Polls act as whichever account you're using, so sign in to one first."
        }
        if activeHasSession {
            return "u/\(username)'s reddit.com session is set up, so polls and the other features that need it work. If they stop, sign in again here. Choose how accounts sign in, or get help setting up your keys."
        }
        return "u/\(username) needs a one-time reddit.com sign-in for polls, which are voted on and posted through the web session. It is usually captured when you sign in; you sign in on reddit.com directly and Phoebus never sees your password."
    }

    /// Reborn's "Set Up reddit.com Web Sign-In" action row, which is also where
    /// polls get the active account's web session: a status cell (a green check
    /// and "Ready to vote and post") once one exists, offering to sign in again,
    /// and a "Sign in to a Reddit account first." note with no account.
    @ViewBuilder private var webSignInRow: some View {
        Group {
            if let username = activeUsername {
                if activeHasSession {
                    Button { isShowingSignedInChoice = true } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("reddit.com Web Sign-In").foregroundStyle(.primary)
                                Text("u/\(username) · Ready to vote and post").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            // A green check reads as "connected" at a glance.
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                } else {
                    Button { isShowingWebSessionLogin = true } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Set Up reddit.com Web Sign-In").foregroundStyle(Color.apolloAccent)
                                Text("One quick sign-in for u/\(username)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("reddit.com Web Sign-In")
                        .foregroundStyle(.secondary)
                    Text("Sign in to a Reddit account first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        // Polls' Web Sign-In link scrolls to and flashes this row.
        // search: item "Set Up reddit.com Web Sign-In"
        .apolloSearchRow("reddit.com Web Sign-In")
        .confirmationDialog("u/\(activeUsername ?? "") is signed in", isPresented: $isShowingSignedInChoice, titleVisibility: .visible) {
            Button("Sign In Again") { isShowingWebSessionLogin = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sign in again only if polls have stopped working.")
        }
        .sheet(isPresented: $isShowingWebSessionLogin) {
            NavigationStack {
                WebSessionLoginScreen(
                    requiredUsername: activeUsername,
                    onSuccess: { credential in
                        accountManager.addWebSessionAccount(credential)
                        isShowingWebSessionLogin = false
                    },
                    onCancel: { isShowingWebSessionLogin = false }
                )
            }
        }
    }
}

/// "Separate Settings per Account" (Phoebus-only): global defaults, plus
/// per account the settings changed while signed in to it.
struct PerAccountSettingsSections: View {
    let accountManager: AccountManager

    @Setting(AccountSettingsScope.enabledStorage) private var separateSettingsPerAccount
    @State private var isShowingGlobalDefaults = false
    @State private var overridesToCopy: String?
    @State private var isConfirmingReset = false
    /// Re-renders the section when the account or editing layer changes.
    @State private var scopeRevision = 0

    var body: some View {
        let _ = scopeRevision
        let account = AccountSettingsScope.activeAccount
        let otherAccounts = accountManager.accounts.map(\.username).filter { $0 != account }
        let canCopy = account != nil && !otherAccounts.isEmpty
        Section {
            SettingsDetailToggle("Separate Settings per Account",
                                 detail: "Settings you change apply to the current account only. Other accounts keep the global defaults.",
                                 isOn: $separateSettingsPerAccount.binding)
                .accessibilityIdentifier("accounts.perAccountSettings")
                // search: item "Edit Global Defaults", "Global Defaults & Overrides"
                .apolloSearchRow("Separate Settings per Account",
                                 lastBeforeFooter: !separateSettingsPerAccount)
                // Hosted on the switch, which stays while the rows below it change: a
                // presentation on one of them would close when the layer being edited does.
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
            Text(footer(account: account))
                .apolloSectionFooter()
        }
        .onReceive(NotificationCenter.default.publisher(for: AccountSettingsScope.didChangeNotification)) { _ in
            scopeRevision &+= 1
        }
    }

    private func footer(account: String?) -> String {
        guard separateSettingsPerAccount else {
            return "When on, each account keeps its own settings on top of the global defaults."
        }
        guard let account else { return "Signed out, Settings changes the global defaults." }
        return "Changes in Settings now apply to \(account) only. A dot marks a row set for this account; long-press it to use the global default. API keys, passcode, backups and notifications stay global."
    }
}

/// Phoebus-only: signs the YouTube player in as the user's Google account.
struct YouTubeSections: View {
    @StateObject private var youTube = YouTubeAccount.shared
    @State private var isShowingYouTubeSignIn = false
    @State private var isShowingYouTubeImport = false
    @State private var isConfirmingYouTubeSignOut = false

    var body: some View {
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
