import SwiftUI
import AuthenticationServices
import PhoebusCore

/// Reborn's account switcher: a multi-account list to add, switch, remove and
/// reorder Reddit accounts, persisted via `AccountStore`. OAuth and web-session
/// ("keyless") accounts coexist in the list; keyless accounts get a small badge.
public struct AccountManagerScreen: View {
    @ObservedObject var accountManager: AccountManager
    @State private var showingAddAccountChooser = false
    @State var showingOAuthLogin = false
    @State var showingWebSessionLogin = false
    @State private var isAuthenticatingOAuth = false
    @State private var errorMessage: String?

    public init(accountManager: AccountManager) {
        self.accountManager = accountManager
    }

    /// Reborn #1077 row status: web-session rows read "API-key-free"
    /// (kept short, it shares the row with two accessories); OAuth
    /// rows name their key. Every account here signs in through the
    /// one app-wide key, so an OAuth row is "API key · default".
    static func statusText(for account: StoredAccount) -> String {
        account.isKeyless ? "API-key-free" : "API key · default"
    }

    public var body: some View {
        // Reborn #1077: an inset-grouped card of 68pt rows, each a 44pt avatar, the
        // bare username over a status line, a checkmark on the active account and an
        // ellipsis for that account's sign-in; "+" top-leading to add, Edit
        // top-trailing.
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red).font(.caption)
                }
            }
            Section {
                ForEach(Array(accountManager.accounts.enumerated()), id: \.element.username) { index, account in
                    Button {
                        accountManager.switchTo(index: index)
                    } label: {
                        HStack(spacing: 12) {
                            AvatarView(username: account.username, repository: accountManager.repository, size: 44)
                                .frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.username)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(Self.statusText(for: account))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            // Opacity, not removal: the ellipsis keeps
                            // its slot on every row.
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.apolloAccent)
                                .frame(width: 20)
                                .opacity(index == accountManager.activeIndex ? 1 : 0)
                                .accessibilityHidden(index != accountManager.activeIndex)
                            accountMenu(for: account, index: index)
                        }
                        .frame(minHeight: 68 - 16)
                        .apolloFullRowTapTarget()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("accounts.row.\(account.username)")
                }
                .onMove { source, destination in
                    accountManager.move(fromOffsets: source, toOffset: destination)
                }
                .onDelete { offsets in
                    for index in offsets.sorted(by: >) {
                        accountManager.remove(at: index)
                    }
                }
            } footer: {
                // Empty: Apollo's string. Otherwise Reborn's footer, minus the per-account
                // API key editor.
                Text(accountManager.accounts.isEmpty
                     ? "Sign in to an existing account, or create a new account."
                     : "Each account can use the Reddit API key, or sign in without one via a web session. Tap an account to switch to it, or tap the ellipsis to manage its sign-in.")
                    .apolloSectionFooter()
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.defaultMinListRowHeight, 68)
        .navigationTitle("Accounts")
        .navigationBarTitleDisplayModeIfAvailable()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingAddAccountChooser = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Account")
                .accessibilityIdentifier("accounts.addAccount")
            }
            ToolbarItem(placement: .primaryAction) {
                EditButton()
            }
        }
        .confirmationDialog("Choose Sign-In Method", isPresented: $showingAddAccountChooser, titleVisibility: .visible) {
            Button("Sign In With API Key") {
                showingOAuthLogin = true
            }
            .accessibilityIdentifier("accounts.addAccount.apiKey")
            Button("Sign In Without API Key (Experimental)") {
                showingWebSessionLogin = true
            }
            .accessibilityIdentifier("accounts.addAccount.keyless")
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingWebSessionLogin) {
            NavigationStack {
                WebSessionLoginScreen(
                    onSuccess: { credential in
                        accountManager.addWebSessionAccount(credential)
                        showingWebSessionLogin = false
                    },
                    onCancel: { showingWebSessionLogin = false }
                )
            }
        }
        .sheet(isPresented: $showingOAuthLogin) {
            AddOAuthAccountSheet(
                isAuthenticating: $isAuthenticatingOAuth,
                onSuccess: { credential, username in
                    accountManager.addOAuthAccount(credential, username: username)
                    showingOAuthLogin = false
                },
                onError: { message in errorMessage = message },
                onCancel: { showingOAuthLogin = false }
            )
        }
    }
}


extension AccountManagerScreen {
    /// The row's ellipsis: a web-session account offers Re-Sign In
    /// and a switch to API-key sign-in; an OAuth account offers
    /// Re-Sign In. Remove sits at the bottom of both, as swipe-to-delete
    /// does.
    @ViewBuilder
    func accountMenu(for account: StoredAccount, index: Int) -> some View {
        Menu {
            Section(account.isKeyless ? "Signed in without an API key (web session)." : "Signed in with the Reddit API key.") {
                Button {
                    if account.isKeyless { showingWebSessionLogin = true } else { showingOAuthLogin = true }
                } label: {
                    Label("Re-Sign In", systemImage: "arrow.clockwise")
                }
                if account.isKeyless {
                    Button {
                        showingOAuthLogin = true
                    } label: {
                        Label("Use API Key Instead…", systemImage: "key")
                    }
                }
            }
            Button(role: .destructive) {
                accountManager.remove(at: index)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Manage \(account.username)")
        .accessibilityIdentifier("accounts.row.\(account.username).more")
    }
}

/// A minimal wrapper around the `ASWebAuthenticationSession` OAuth flow
/// `LoginScreen` uses, scoped to an `EphemeralCredentialStore` and reporting the
/// discovered username back so `AccountManagerScreen` can file the new
/// credential under the right `AccountStore` entry.
private struct AddOAuthAccountSheet: View {
    @Binding var isAuthenticating: Bool
    let onSuccess: (RedditCredential, String) -> Void
    let onError: (String) -> Void
    let onCancel: () -> Void

    @State private var contextProvider = AuthPresentationAnchor()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if isAuthenticating {
                    ProgressView("Signing you in…")
                } else {
                    Text("Sign in to add another Reddit account.")
                        .foregroundStyle(.secondary)
                    Button("Sign In with Reddit") {
                        Task { await startLogin() }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("accounts.oauthLogin.start")
                }
            }
            .padding()
            .navigationTitle("Add Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .task { await startLogin() }
        }
    }

    private func startLogin() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let ephemeralAuth = RedditAuthClient(credentialStore: EphemeralCredentialStore(), webSessionStore: EphemeralWebSessionStore())
        let state = UUID().uuidString
        let url = await ephemeralAuth.buildAuthorizeURL(state: state)

        do {
            // Reborn's "Universal OAuth Sign-In" switch (`apollo_usesCustomOAuthSignIn`);
            // see `OAuthCallbackAuthenticator`/`CustomOAuthSession`.
            let callbackURL = try await OAuthCallbackAuthenticator.fetchCallbackURL(authorizeURL: url, contextProvider: contextProvider)

            guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value,
                  returnedState == state,
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                onError("OAuth state mismatch or missing code")
                return
            }

            try await ephemeralAuth.exchangeCode(code)
            guard let credential = await ephemeralAuth.credential else {
                onError("Sign-in did not return a credential")
                return
            }

            // Discover the username via /api/v1/me before filing the account:
            // OAuth's token response carries none, unlike the web-session flow's
            // /api/me.json probe.
            let repository = RedditRepository(client: RedditAPIClient(auth: ephemeralAuth))
            let identity = try await repository.fetchIdentity()
            onSuccess(credential, identity.name)
        } catch {
            onError(UserFacingError.text(for: error))
        }
    }
}

