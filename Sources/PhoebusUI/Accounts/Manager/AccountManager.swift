import Foundation
import SwiftUI
import Combine
import PhoebusCore

/// App-root owner of multi-account state. Wraps `AccountStore` (persistence
/// and list mutation) and rebuilds the live `RedditAuthClient`/
/// `RedditRepository` pair for the active account, republishing them so the
/// SwiftUI tree rebuilds on an account switch without a relaunch, as in
/// Apollo.
@MainActor
public final class AccountManager: ObservableObject {
    private let store: AccountStore

    @Published public private(set) var accounts: [StoredAccount] = []
    @Published public private(set) var activeIndex: Int?
    /// Rebuilt whenever the active account changes. `LoginScreen`/`MainTabView`
    /// observe this rather than holding their own `RedditAuthClient`.
    @Published public private(set) var authClient: RedditAuthClient
    @Published public private(set) var repository: RedditRepository

    public init(store: AccountStore = AccountStore()) {
        self.store = store
        self.accounts = store.accounts
        self.activeIndex = store.activeIndex
        let client = Self.buildAuthClient(store: store, account: store.activeAccount)
        self.authClient = client
        self.repository = RedditRepository(client: RedditAPIClient(auth: client))
        let linkPreviewRepository = repository
        ActiveRedditRepository.provider = { linkPreviewRepository }
        refreshMatureMediaPreference()
        // Reborn "Per-Account Favorites": that store lives in PhoebusCore, which has
        // no account-model dependency, so it reads the active username through
        // this static provider, refreshed on every switch/add/remove.
        FavoriteSubredditsAccountContext.currentUsernameProvider = { @Sendable [weak store] in
            store?.activeAccount?.username
        }
        FavoriteSubredditsAccountContext.allUsernamesProvider = { @Sendable [weak store] in
            store?.accounts.map(\.username) ?? []
        }

        // Same injection for web-session resolution, so `WebSessionRegistry` can
        // answer per-account lookups. Both closures are `nonisolated`/`@Sendable`
        // because they are read from background executors and `AccountManager` is
        // `@MainActor`; otherwise they would inherit main-actor isolation and trap
        // off-main. `AccountStore` does its own locking.
        WebSessionRegistry.accountProvider = { @Sendable [weak store] username in
            store?.accounts.first { $0.username == username }
        }
        WebSessionRegistry.removeHandler = { @Sendable [weak store] username in
            store?.setWebSession(nil, for: username)
        }
        restoreObserver = NotificationCenter.default.addObserver(
            forName: .apolloAccountsRestored, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadAccounts() }
        }
    }

    private var restoreObserver: NSObjectProtocol?

    /// Picks up accounts a backup restore wrote to the keychain without a
    /// relaunch.
    public func reloadAccounts() {
        store.reload()
        refreshFromStore()
    }

    /// True once at least one account has a usable credential. Async because
    /// `RedditAuthClient` is an actor and `isSignedIn` reads its isolated state.
    public var isSignedIn: Bool {
        get async { await authClient.isSignedIn }
    }

    /// Accounts a push backend can watch: those with a refresh token
    /// (OAuth). The backend refreshes the access token itself before
    /// using it, so an expired one is fine to send.
    public func pushRegistrationAccounts() async -> [PushNotificationClient.Account] {
        accounts.compactMap { account in
            guard let credential = account.oauthCredential, let refresh = credential.refreshToken, !refresh.isEmpty else { return nil }
            return PushNotificationClient.Account(username: account.username, accessToken: credential.accessToken, refreshToken: refresh)
        }
    }

    public func switchTo(index: Int) {
        store.switchTo(index: index)
        refreshFromStore()
    }

    public func remove(at index: Int) {
        store.remove(at: index)
        refreshFromStore()
    }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        store.move(fromOffsets: source, toOffset: destination)
        refreshFromStore()
    }

    /// Files a completed OAuth sign-in (see `AddOAuthAccountSheet`) under
    /// `username`'s `AccountStore` entry and switches to it, as Apollo does.
    public func addOAuthAccount(_ credential: RedditCredential, username: String) {
        let account = StoredAccount(username: username, oauthCredential: credential)
        store.addOrUpdate(account, makeActive: true)
        refreshFromStore()
    }

    /// Same for a completed web-session (keyless) sign-in; the harvested
    /// `WebSessionCredential` carries the username from its `/api/me.json` probe.
    public func addWebSessionAccount(_ session: WebSessionCredential) {
        // Preserve any existing OAuth credential for this username: a fresh
        // `StoredAccount` would drop it and downgrade a working OAuth account to
        // cookie transport when its owner harvests a cookie for a web-only feature
        // (Polls).
        let existingOAuth = store.accounts.first { $0.username == session.username }?.oauthCredential
        let account = StoredAccount(username: session.username, oauthCredential: existingOAuth, webSession: session)
        // Only switch when the account is new; an auxiliary harvest for an
        // existing account must not change the active account.
        let isNewAccount = existingOAuth == nil
        store.addOrUpdate(account, makeActive: isNewAccount)
        refreshFromStore()
    }

    /// Migrates the legacy single-account `KeychainCredentialStore`/
    /// `WebSessionStoreBox` slots into `AccountStore` on first launch. Runs only
    /// when `AccountStore` is empty and a legacy credential exists.
    public func migrateLegacyCredentialIfNeeded() async {
        guard store.accounts.isEmpty else { return }
        let legacyCredentialStore = KeychainCredentialStoreBox()
        let legacyWebSessionStore = WebSessionStoreBox()
        let legacyCredential = legacyCredentialStore.load()
        let legacyWebSession = legacyWebSessionStore.load()
        guard legacyCredential != nil || legacyWebSession != nil else { return }

        // A username is needed to file this under. The web-session credential
        // carries one; a legacy OAuth credential does not, so it is resolved the
        // same way `AddOAuthAccountSheet` does for a fresh sign-in.
        let username: String
        if let legacyWebSession {
            username = legacyWebSession.username
        } else {
            let legacyAuth = RedditAuthClient(credentialStore: legacyCredentialStore, webSessionStore: legacyWebSessionStore)
            let legacyRepository = RedditRepository(client: RedditAPIClient(auth: legacyAuth))
            guard let identity = try? await legacyRepository.fetchIdentity() else {
                // Identity could not be resolved (e.g. offline at launch): leave the
                // legacy store untouched and retry next launch.
                return
            }
            username = identity.name
        }

        let migrated = StoredAccount(username: username, oauthCredential: legacyCredential, webSession: legacyWebSession)
        store.addOrUpdate(migrated, makeActive: true)
        // Clear the legacy slots only after the migrated copy is persisted, so an
        // interrupted migration never loses the credential.
        legacyCredentialStore.clear()
        legacyWebSessionStore.clear()
        refreshFromStore()
    }

    public func signOutActiveAccount() {
        guard let activeIndex = store.activeIndex else { return }
        store.remove(at: activeIndex)
        refreshFromStore()
    }

    private func refreshFromStore() {
        accounts = store.accounts
        activeIndex = store.activeIndex
        let client = Self.buildAuthClient(store: store, account: store.activeAccount)
        authClient = client
        repository = RedditRepository(client: RedditAPIClient(auth: client))
        let linkPreviewRepository = repository
        ActiveRedditRepository.provider = { linkPreviewRepository }
        refreshMatureMediaPreference()
    }

    /// Re-reads the active account's "Blur mature media" pref (which "Blur NSFW
    /// Media → Reddit Setting" follows) and its block list.
    private func refreshMatureMediaPreference() {
        guard store.activeAccount != nil else { return }
        let repository = repository
        Task {
            _ = try? await repository.fetchIdentity()
            _ = try? await repository.fetchBlockedUsers()
        }
    }

    private static func buildAuthClient(store: AccountStore, account: StoredAccount?) -> RedditAuthClient {
        guard let account else {
            // No accounts at all: a client with no persisted credential, as on a
            // fresh signed-out install.
            return RedditAuthClient(credentialStore: EphemeralCredentialStore(), webSessionStore: EphemeralWebSessionStore())
        }
        return RedditAuthClient(
            credentialStore: AccountCredentialAdapter(store: store, username: account.username),
            webSessionStore: AccountWebSessionAdapter(store: store, username: account.username)
        )
    }
}

/// Optional environment plumbing for `AccountManager`: `Environment` rather
/// than `EnvironmentObject` so views can be constructed standalone in
/// previews and tests, with a `nil` default.
///
/// `PollView` needs it for the one-time cookie harvest Apollo performs on an
/// OAuth account's first vote.
private struct AccountManagerKey: EnvironmentKey {
    static let defaultValue: AccountManager? = nil
}

public extension EnvironmentValues {
    var accountManager: AccountManager? {
        get { self[AccountManagerKey.self] }
        set { self[AccountManagerKey.self] = newValue }
    }
}
