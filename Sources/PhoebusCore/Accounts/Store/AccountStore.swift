import Foundation
#if canImport(Security)
import Security
#endif

/// Reborn's multi-account support: sign in to more than one Reddit account
/// and switch the active one from the Accounts screen.
///
/// Like Reborn it keeps an ordered array of accounts plus an active index,
/// stored as one JSON-encoded Keychain item (as `CredentialStore`/
/// `WebSessionStore` do) since these credentials belong in the Keychain.
///
/// Per-account custom API credential overrides are not supported:
/// `RedditOAuthConfig`/`CustomAPISettings` are a single global override,
/// and every account signs in through the same registered app.
public struct StoredAccount: Codable, Sendable, Equatable, Identifiable {
    /// Reddit username, lowercased (case-insensitive account keying).
    public var username: String
    public var oauthCredential: RedditCredential?
    public var webSession: WebSessionCredential?

    public var id: String { username }

    public init(username: String, oauthCredential: RedditCredential? = nil, webSession: WebSessionCredential? = nil) {
        self.username = username.lowercased()
        self.oauthCredential = oauthCredential
        self.webSession = webSession
    }

    /// Drives the switcher's per-account "keyless" badge: OAuth vs web session
    /// is mutually exclusive per account in normal use.
    public var isKeyless: Bool { webSession != nil && oauthCredential == nil }
}

public struct AccountStorePersisted: Codable, Sendable {
    public var accounts: [StoredAccount]
    public var activeIndex: Int?

    public init(accounts: [StoredAccount], activeIndex: Int?) {
        self.accounts = accounts
        self.activeIndex = activeIndex
    }
}

/// Persists the ordered account list + active index, and exposes the
/// switch/add/remove/reorder operations the Accounts screen drives.
///
/// A plain lock-protected class (not an actor): `RedditAuthClient`'s
/// `CredentialStore`/`WebSessionStore` protocols are synchronous, and
/// the adapters below need to call into this store from those
/// synchronous methods without an `await`.
public final class AccountStore: @unchecked Sendable {
    private let lock = NSLock()
    private let keychain: AccountKeychainStore
    private var _accounts: [StoredAccount]
    private var _activeIndex: Int?
    /// The keychain was locked at launch, so the empty list is not real:
    /// nothing is written until it has been read.
    private var loadDeferred: Bool

    public init(store: AccountKeychainStore = .platformDefault) {
        self.keychain = store
        let persisted = store.load()
        self._accounts = persisted?.accounts ?? []
        self._activeIndex = persisted?.activeIndex
        self.loadDeferred = persisted == nil && store.isLocked
        // Publish on load, not only on mutation. An account signed in
        // before widget credentials existed would otherwise never
        // publish anything until the user happened to switch or
        // re-authenticate, leaving every widget stuck on 403.
        if !loadDeferred { publishWidgetCredentialsLocked() }
    }

    /// Retries a load that the locked keychain refused at launch.
    private func reloadIfDeferredLocked() {
        guard loadDeferred, let persisted = keychain.load() else { return }
        loadDeferred = false
        _accounts = persisted.accounts
        _activeIndex = persisted.activeIndex
        publishWidgetCredentialsLocked()
    }

    /// Re-reads the keychain, after a backup restore wrote to it
    /// directly.
    public func reload() {
        lock.lock(); defer { lock.unlock() }
        guard let persisted = keychain.load() else { return }
        loadDeferred = false
        _accounts = persisted.accounts
        _activeIndex = persisted.activeIndex
        publishWidgetCredentialsLocked()
    }

    public var accounts: [StoredAccount] {
        lock.lock(); defer { lock.unlock() }
        reloadIfDeferredLocked()
        return _accounts
    }

    public var activeIndex: Int? {
        lock.lock(); defer { lock.unlock() }
        reloadIfDeferredLocked()
        return _activeIndex
    }

    public var activeAccount: StoredAccount? {
        lock.lock(); defer { lock.unlock() }
        reloadIfDeferredLocked()
        guard let _activeIndex, _accounts.indices.contains(_activeIndex) else { return nil }
        return _accounts[_activeIndex]
    }

    /// Adds a newly-signed-in account (or updates an existing entry
    /// for the same username, e.g. a token refresh) and makes it
    /// active, as Apollo does when sign-in completes for a NEW account.
    @discardableResult
    public func addOrUpdate(_ account: StoredAccount, makeActive: Bool = true) -> Int {
        lock.lock(); defer { lock.unlock() }
        reloadIfDeferredLocked()
        let index: Int
        if let existingIndex = _accounts.firstIndex(where: { $0.username == account.username }) {
            _accounts[existingIndex] = account
            index = existingIndex
        } else {
            _accounts.append(account)
            index = _accounts.count - 1
        }
        if makeActive { _activeIndex = index }
        persistLocked()
        return index
    }

    /// Switches the active account by index. No-op if the index is invalid or
    /// already active.
    public func switchTo(index: Int) {
        lock.lock(); defer { lock.unlock() }
        reloadIfDeferredLocked()
        guard _accounts.indices.contains(index), index != _activeIndex else { return }
        _activeIndex = index
        persistLocked()
    }

    /// Removes an account. If it was active, the new active account
    /// becomes the previous index (clamped), or nil if none remain.
    public func remove(at index: Int) {
        lock.lock(); defer { lock.unlock() }
        reloadIfDeferredLocked()
        guard _accounts.indices.contains(index) else { return }
        _accounts.remove(at: index)
        if _accounts.isEmpty {
            _activeIndex = nil
        } else if let activeIndex = _activeIndex, index == activeIndex {
            _activeIndex = min(activeIndex, _accounts.count - 1)
        } else if let activeIndex = _activeIndex, index < activeIndex {
            _activeIndex = activeIndex - 1
        }
        persistLocked()
    }

    /// Reorders the list (drag-to-reorder).
    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        lock.lock(); defer { lock.unlock() }
        reloadIfDeferredLocked()
        let activeUsername = _activeIndex.flatMap { _accounts.indices.contains($0) ? _accounts[$0].username : nil }
        _accounts = Self.moved(_accounts, fromOffsets: source, toOffset: destination)
        if let activeUsername {
            _activeIndex = _accounts.firstIndex(where: { $0.username == activeUsername })
        }
        persistLocked()
    }

    /// `Array.move(fromOffsets:toOffset:)` is a SwiftUI-only extension
    /// with no PhoebusCore equivalent, so this reimplements its exact
    /// semantics: remove the elements at `source`, then reinsert them
    /// starting at `destination`, adjusted for the removed positions.
    private static func moved<T>(_ array: [T], fromOffsets source: IndexSet, toOffset destination: Int) -> [T] {
        var result = array
        let moving = source.sorted().map { array[$0] }
        for index in source.sorted(by: >) { result.remove(at: index) }
        let adjustedDestination = destination - source.filter { $0 < destination }.count
        result.insert(contentsOf: moving, at: max(0, min(adjustedDestination, result.count)))
        return result
    }

    /// Reads/writes one account's stored OAuth credential, for
    /// `AccountCredentialAdapter`. `username` is matched
    /// case-insensitively (constructor already lowercases on store).
    func oauthCredential(for username: String) -> RedditCredential? {
        lock.lock(); defer { lock.unlock() }
        reloadIfDeferredLocked()
        return _accounts.first { $0.username == username.lowercased() }?.oauthCredential
    }

    func setOAuthCredential(_ credential: RedditCredential?, for username: String) {
        lock.lock(); defer { lock.unlock() }
        reloadIfDeferredLocked()
        guard let idx = _accounts.firstIndex(where: { $0.username == username.lowercased() }) else { return }
        _accounts[idx].oauthCredential = credential
        persistLocked()
    }

    public func webSession(for username: String) -> WebSessionCredential? {
        lock.lock(); defer { lock.unlock() }
        reloadIfDeferredLocked()
        return _accounts.first { $0.username == username.lowercased() }?.webSession
    }

    public func setWebSession(_ session: WebSessionCredential?, for username: String) {
        lock.lock(); defer { lock.unlock() }
        reloadIfDeferredLocked()
        guard let idx = _accounts.firstIndex(where: { $0.username == username.lowercased() }) else { return }
        _accounts[idx].webSession = session
        persistLocked()
    }

    private func persistLocked() {
        // Never overwrite the real list with the placeholder.
        guard !loadDeferred else { return }
        keychain.save(AccountStorePersisted(accounts: _accounts, activeIndex: _activeIndex))
        publishWidgetCredentialsLocked()
    }

    /// Mirrors the active account's transport credentials into the App
    /// Group so the widget extension can make authenticated requests.
    /// Hangs off `persistLocked` deliberately so every mutation funnels
    /// through here and the widget's copy cannot drift. Without this
    /// the widgets get 403 on every fetch.
    private func publishWidgetCredentialsLocked() {
        SharedFeedCache.store(credentials: widgetCredentialsLocked())
    }

    private func widgetCredentialsLocked() -> SharedFeedCache.WidgetCredentials? {
        guard let activeIndex = _activeIndex, _accounts.indices.contains(activeIndex) else { return nil }
        let account = _accounts[activeIndex]
        if let oauth = account.oauthCredential {
            return .init(
                // The account's web session too, when it has one: a
                // fallback if the bearer can't be renewed.
                cookieHeader: account.webSession?.cookieHeader,
                accessToken: oauth.accessToken,
                expiration: oauth.expiration,
                // The OAuth transport's identity, never the browser
                // one, matching `RedditAPIClient`'s split.
                userAgent: RedditAPIClient.oauthUserAgent,
                refreshToken: oauth.refreshToken,
                clientID: RedditOAuthConfig.clientID,
                clientSecret: RedditOAuthConfig.clientSecret)
        }
        if let web = account.webSession {
            return .init(cookieHeader: web.cookieHeader, accessToken: nil, expiration: nil,
                         userAgent: RedditAPIClient.webBrowserUserAgent)
        }
        return nil
    }
}

/// Keychain-backed persistence for the whole account list, following
/// `CredentialStore`/`WebSessionStore` (a single JSON blob under one
/// Keychain item).
public protocol AccountKeychainStore: Sendable {
    func save(_ persisted: AccountStorePersisted)
    func load() -> AccountStorePersisted?
    func clear()
    /// The item exists but can't be read yet (before the first unlock).
    var isLocked: Bool { get }
}

extension AccountKeychainStore {
    public var isLocked: Bool { false }
}

#if canImport(Security)
public struct KeychainAccountStore: AccountKeychainStore {
    private let item = KeychainItem(service: "com.pendo324.Phoebus.reddit-accounts", account: "default")

    public init() {}

    /// Set when the keychain reports it is unusable for this process:
    /// an ad-hoc-signed build's keychain-access-group is a restricted
    /// entitlement, so `SecItemAdd`/`SecItemCopyMatching` return
    /// `errSecMissingEntitlement` and credentials silently never persist.
    nonisolated(unsafe) static var keychainUnavailable = false

    public func save(_ persisted: AccountStorePersisted) {
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        let status = item.write(data)
        if status == errSecMissingEntitlement || status == errSecNotAvailable {
            Self.keychainUnavailable = true
        }
    }

    public func load() -> AccountStorePersisted? {
        let (status, data) = item.read()
        if status == errSecMissingEntitlement || status == errSecNotAvailable {
            Self.keychainUnavailable = true
            return nil
        }
        return data.flatMap { try? JSONDecoder().decode(AccountStorePersisted.self, from: $0) }
    }

    public var isLocked: Bool { item.read().status == errSecInteractionNotAllowed }

    public func clear() { item.delete() }
}
#else
public final class InMemoryAccountKeychainStore: AccountKeychainStore, @unchecked Sendable {
    private var stored: AccountStorePersisted?
    public init() {}
    public func save(_ persisted: AccountStorePersisted) { stored = persisted }
    public func load() -> AccountStorePersisted? { stored }
    public func clear() { stored = nil }
}
#endif

extension AccountKeychainStore where Self == AccountKeychainStoreBox {
    public static var platformDefault: AccountKeychainStoreBox { AccountKeychainStoreBox() }
}

/// Persists accounts to a file in Application Support with
/// `.completeFileProtection`, as a fallback for when the keychain is
/// genuinely unusable (an ad-hoc-signed build cannot carry a
/// keychain-access-group entitlement), so logins still persist.
public struct FileBackedAccountStore: AccountKeychainStore {
    private var url: URL? {
        guard let directory = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return nil }
        return directory.appendingPathComponent("reddit-accounts.json")
    }

    public init() {}

    public func save(_ persisted: AccountStorePersisted) {
        guard let url, let data = try? JSONEncoder().encode(persisted) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    public func load() -> AccountStorePersisted? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AccountStorePersisted.self, from: data)
    }

    public func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

public struct AccountKeychainStoreBox: AccountKeychainStore {
    private let box: any AccountKeychainStore
    private let fallback = FileBackedAccountStore()

    public var isLocked: Bool { box.isLocked }

    public init() {
        #if canImport(Security)
        box = KeychainAccountStore()
        #else
        box = InMemoryAccountKeychainStore()
        #endif
    }

    /// Writes through to the keychain first; if unusable, also writes
    /// the fallback (checked after the attempt, since unusability is
    /// only knowable by trying).
    public func save(_ persisted: AccountStorePersisted) {
        box.save(persisted)
        #if canImport(Security)
        if KeychainAccountStore.keychainUnavailable {
            fallback.save(persisted)
        }
        #endif
    }

    public func load() -> AccountStorePersisted? {
        if let loaded = box.load() { return loaded }
        #if canImport(Security)
        // A keychain miss is ambiguous (never saved vs unusable), so
        // always consult the fallback.
        return fallback.load()
        #else
        return nil
        #endif
    }

    public func clear() {
        box.clear()
        fallback.clear()
    }
}

/// Bridges one account's slot in `AccountStore` to `RedditAuthClient`'s
/// existing `CredentialStore` protocol, so a `RedditAuthClient`
/// constructed for a specific account persists its token refreshes
/// back into that account's `AccountStore` entry instead of the
/// legacy single fixed keychain slot.
public struct AccountCredentialAdapter: CredentialStore {
    let store: AccountStore
    let username: String

    public init(store: AccountStore, username: String) {
        self.store = store
        self.username = username
    }

    public func save(_ credential: RedditCredential) throws {
        store.setOAuthCredential(credential, for: username)
    }
    public func load() -> RedditCredential? {
        store.oauthCredential(for: username)
    }
    public func clear() {
        store.setOAuthCredential(nil, for: username)
    }
}

/// Same bridge for the web-session (keyless) transport.
public struct AccountWebSessionAdapter: WebSessionStore {
    let store: AccountStore
    let username: String

    public init(store: AccountStore, username: String) {
        self.store = store
        self.username = username
    }

    public func save(_ session: WebSessionCredential) throws {
        store.setWebSession(session, for: username)
    }
    public func load() -> WebSessionCredential? {
        store.webSession(for: username)
    }
    public func clear() {
        store.setWebSession(nil, for: username)
    }
}

/// A purely in-memory `CredentialStore`, used for the "sign in first,
/// discover the username second" step of adding an account: sign-in
/// completes against a throwaway `RedditAuthClient` backed by this
/// store, then `/api/v1/me` reveals the username before the credential
/// is persisted into `AccountStore`, so a fresh sign-in never touches
/// real Keychain storage before the account's identity is known.
public final class EphemeralCredentialStore: CredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: RedditCredential?
    public init() {}
    public func save(_ credential: RedditCredential) throws {
        lock.lock(); defer { lock.unlock() }
        stored = credential
    }
    public func load() -> RedditCredential? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }
    public func clear() {
        lock.lock(); defer { lock.unlock() }
        stored = nil
    }
}

/// Same purpose as `EphemeralCredentialStore`, for the web-session
/// (keyless) sign-in path.
public final class EphemeralWebSessionStore: WebSessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: WebSessionCredential?
    public init() {}
    public func save(_ session: WebSessionCredential) throws {
        lock.lock(); defer { lock.unlock() }
        stored = session
    }
    public func load() -> WebSessionCredential? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }
    public func clear() {
        lock.lock(); defer { lock.unlock() }
        stored = nil
    }
}

