import SwiftUI
import AuthenticationServices
import PhoebusCore

/// What the account switcher presents: the sign-in method chooser and
/// the two sign-in sheets. Shared by the switcher screen and the Accounts
/// section of Settings, so either can add or re-sign-in an account.
@MainActor
final class AccountSwitcherModel: ObservableObject {
    @Published var showingAddAccountChooser = false
    @Published var showingOAuthLogin = false
    @Published var showingWebSessionLogin = false
    @Published var isAuthenticatingOAuth = false
    @Published var errorMessage: String?
}

extension View {
    /// The chooser and sign-in sheets `model` drives, hosted on the view
    /// the add and re-sign-in actions belong to.
    func accountSwitcherPresentations(_ model: AccountSwitcherModel, accountManager: AccountManager) -> some View {
        modifier(AccountSwitcherPresentations(model: model, accountManager: accountManager))
    }
}

private struct AccountSwitcherPresentations: ViewModifier {
    @ObservedObject var model: AccountSwitcherModel
    let accountManager: AccountManager

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Choose Sign-In Method", isPresented: $model.showingAddAccountChooser, titleVisibility: .visible) {
                Button("Sign In With API Key") {
                    model.showingOAuthLogin = true
                }
                .accessibilityIdentifier("accounts.addAccount.apiKey")
                Button("Sign In Without API Key (Experimental)") {
                    model.showingWebSessionLogin = true
                }
                .accessibilityIdentifier("accounts.addAccount.keyless")
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $model.showingWebSessionLogin) {
                NavigationStack {
                    WebSessionLoginScreen(
                        onSuccess: { credential in
                            accountManager.addWebSessionAccount(credential)
                            model.showingWebSessionLogin = false
                        },
                        onCancel: { model.showingWebSessionLogin = false }
                    )
                }
            }
            .sheet(isPresented: $model.showingOAuthLogin) {
                AddOAuthAccountSheet(
                    isAuthenticating: $model.isAuthenticatingOAuth,
                    onSuccess: { credential, username in
                        accountManager.addOAuthAccount(credential, username: username)
                        model.showingOAuthLogin = false
                    },
                    onError: { message in model.errorMessage = message },
                    onCancel: { model.showingOAuthLogin = false }
                )
            }
    }
}

/// Reborn's account switcher: a multi-account list to add, switch, remove and
/// reorder Reddit accounts, persisted via `AccountStore`. OAuth and web-session
/// ("keyless") accounts coexist in the list; keyless accounts get a small badge.
public struct AccountManagerScreen: View {
    @ObservedObject var accountManager: AccountManager
    @StateObject private var model = AccountSwitcherModel()

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
            AccountSwitcherSections(accountManager: accountManager, model: model, showsAddRow: false)
        }
        .listStyle(.insetGrouped)
        .environment(\.defaultMinListRowHeight, 68)
        .navigationTitle("Accounts")
        .navigationBarTitleDisplayModeIfAvailable()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    model.showingAddAccountChooser = true
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
        .accountSwitcherPresentations(model, accountManager: accountManager)
    }
}

/// The signed-in accounts as sections: an inline error, then the list
/// with its footer. `showsAddRow` adds an Add Account row at the end of
/// the list, for screens with no "+" in their bar.
struct AccountSwitcherSections: View {
    @ObservedObject var accountManager: AccountManager
    @ObservedObject var model: AccountSwitcherModel
    var showsAddRow: Bool

    var body: some View {
        Group {
            if let errorMessage = model.errorMessage {
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
                                Text(AccountManagerScreen.statusText(for: account))
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
                if showsAddRow {
                    Button("Add Account") { model.showingAddAccountChooser = true }
                        .foregroundStyle(Color.apolloAccent)
                        .accessibilityIdentifier("accounts.addAccount")
                        // The chooser and sheets hang off the button, not the Section.
                        .accountSwitcherPresentations(model, accountManager: accountManager)
                        .apolloSearchRow("Add Account", lastBeforeFooter: true) // search: item "Account Switcher", "Web Session Accounts"
                }
            } header: {
                if showsAddRow {
                    Text("Accounts").apolloSectionHeader()
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
    }
}


extension AccountSwitcherSections {
    /// The row's ellipsis: a web-session account offers Re-Sign In
    /// and a switch to API-key sign-in; an OAuth account offers
    /// Re-Sign In. Remove sits at the bottom of both, as swipe-to-delete
    /// does.
    @ViewBuilder
    func accountMenu(for account: StoredAccount, index: Int) -> some View {
        Menu {
            Section(account.isKeyless ? "Signed in without an API key (web session)." : "Signed in with the Reddit API key.") {
                Button {
                    if account.isKeyless { model.showingWebSessionLogin = true } else { model.showingOAuthLogin = true }
                } label: {
                    Label("Re-Sign In", systemImage: "arrow.clockwise")
                }
                if account.isKeyless {
                    Button {
                        model.showingOAuthLogin = true
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

