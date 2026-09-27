import SwiftUI
import AuthenticationServices
import PhoebusCore

/// Sign-in splash: "Sign In with Reddit" via `ASWebAuthenticationSession`,
/// "Create Account", and a mail glyph above the description copy.
public struct LoginScreen: View {
    let auth: RedditAuthClient
    /// Persists a completed sign-in as an account. `AccountManager` builds its auth
    /// client on ephemeral stores so nothing touches persistent storage before the
    /// identity is known; both sign-in paths hand the credential here.
    var accountManager: AccountManager?
    let onSuccess: () -> Void

    @State private var isAuthenticating = false
    @State private var errorMessage: String?
    @State private var contextProvider = AuthPresentationAnchor()
    @State private var showingCustomAPISettings = false
    @State private var showingSignInMethodChooser = false
    @State private var showingWebSessionLogin = false
    public init(auth: RedditAuthClient, accountManager: AccountManager? = nil, onSuccess: @escaping () -> Void) {
        self.auth = auth
        self.accountManager = accountManager
        self.onSuccess = onSuccess
    }

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "envelope.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color(hex: "007AFF"))
                .frame(width: 118, height: 118)

            Text("Sign in to access your Reddit account, vote on posts, save posts, comment and much more!")
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: "858585"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .frame(maxWidth: 320)

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.caption)
            }

            VStack(spacing: 12) {
                // Reborn's sign-in splash hook: shows the sign-in-method chooser before OAuth.
                Button {
                    showingSignInMethodChooser = true
                } label: {
                    Group {
                        if isAuthenticating {
                            ProgressView().tint(.white)
                        } else {
                            Text("Sign In with Reddit")
                        }
                    }
                    .frame(maxWidth: 320)
                    .frame(height: 35)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "007AFF"))
                .disabled(isAuthenticating)
                .accessibilityIdentifier("login.signIn")
                .confirmationDialog("Choose Sign-In Method", isPresented: $showingSignInMethodChooser, titleVisibility: .visible) {
                    Button("Sign In With API Key") {
                        Task { await startLogin() }
                    }
                    .accessibilityIdentifier("login.signInWithAPIKey")
                    Button("Sign In Without API Key (Experimental)") {
                        showingWebSessionLogin = true
                    }
                    .accessibilityIdentifier("login.signInWithoutAPIKey")
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Use Phoebus's configured API key, or sign in with API-Key-Free Mode. This choice will not change on its own.")
                }

                Button("Create Account") {
                    Task { await startLogin() }
                }
                .font(.system(size: 13))
                .buttonStyle(.plain)
                .foregroundStyle(Color(hex: "007AFF"))
                .disabled(isAuthenticating)
            }

            Spacer()

            // Reborn's Custom API entry point, reachable before sign-in since OAuth needs a
            // working client ID. A new install can also start from a backup.
            HStack(spacing: 20) {
                Button("Custom API Settings") {
                    showingCustomAPISettings = true
                }
            }
            .font(.footnote)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding()
        .sheet(isPresented: $showingCustomAPISettings) {
            NavigationStack {
                // Reborn's Accounts & API Keys.
                Group {
                        CustomAPISettingsScreen()
                }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingCustomAPISettings = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingWebSessionLogin) {
            NavigationStack {
                WebSessionLoginScreen(
                    onSuccess: { credential in
                        Task {
                            await auth.setWebSession(credential)
                            // Persist as a real account, otherwise the
                            // session dies with this throwaway client.
                            accountManager?.addWebSessionAccount(credential)
                            showingWebSessionLogin = false
                            onSuccess()
                        }
                    },
                    onCancel: { showingWebSessionLogin = false }
                )
            }
        }
    }

    private func startLogin() async {
        isAuthenticating = true
        defer { isAuthenticating = false }
        let state = UUID().uuidString
        let url = await auth.buildAuthorizeURL(state: state)

        do {
            // Reborn "Universal OAuth Sign-In" picks between `ASWebAuthenticationSession`
            // and an in-app WKWebView path for any redirect URI; see
            // `OAuthCallbackAuthenticator`/`CustomOAuthSession`.
            let callbackURL = try await OAuthCallbackAuthenticator.fetchCallbackURL(authorizeURL: url, contextProvider: contextProvider)

            guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value,
                  returnedState == state,
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                errorMessage = "OAuth state mismatch or missing code"
                return
            }

            try await auth.exchangeCode(code)
            // Persist the OAuth account. The username is not in the
            // token response, so resolve it the same way
            // `AddOAuthAccountSheet` does before storing.
            // Without a saved account the app would carry on signed in
            // to nothing, so a failed lookup is an error, not success.
            if let accountManager, let credential = await auth.credential {
                let repository = RedditRepository(client: RedditAPIClient(auth: auth))
                let identity = try await repository.fetchIdentity()
                accountManager.addOAuthAccount(credential, username: identity.name)
            }
            onSuccess()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}
