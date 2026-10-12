import Foundation

/// Reborn "Siri & Spotlight" (#1299), Settings › Apollo Reborn › Siri &
/// Spotlight › Index Phoebus Content. Off until the person turns it on.
public enum SiriContentSettings {
    /// Reborn's key, so a Reborn backup carries the choice over.
    public static let enabledKey = "ApolloSiriContentEnabled"
    public static let enabled = DefaultsKey<Bool>(enabledKey, default: false)
    public static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
}

/// Something that happened to content the catalogue may hold.
public enum SiriContentEvent: Sendable {
    /// A listing's sanitized t3/t5 rows.
    case listing(Data, account: String)
    /// A post the person opened (a one-row payload), for onscreen context.
    case openedPost(Data, account: String)
    /// Comments loaded for an opened post.
    case comments(Data, account: String)
    /// Hide, delete or unsubscribe: catalogue ids as Reddit names (`t3_…`, `r/…`).
    case suppress([String], account: String)
    /// Unhide or subscribe.
    case allow([String], account: String)
}

/// Where loaded content enters the Siri & Spotlight index. The app target
/// installs `sink`; until then, and while the setting is off, nothing is
/// read from a response.
public enum SiriContentCapture {
    public nonisolated(unsafe) static var sink: (@Sendable (SiriContentEvent) -> Void)?

    /// The signed-in username the running app is browsing as.
    public static var activeAccount: String? {
        FavoriteSubredditsAccountContext.currentUsernameProvider().flatMap { $0.isEmpty ? nil : $0 }
    }

    private static var isCapturing: Bool { sink != nil && SiriContentSettings.isEnabled }

    /// A listing the account loaded. `account` is who requested it: a
    /// response that lands after an account switch must not feed the new one.
    public static func listingLoaded(_ listing: RedditListing, requestedBy account: String?) {
        guard isCapturing, let account, account == activeAccount,
              let payload = SiriContentSanitizer.listingPayload(listing.data.children) else { return }
        sink?(.listing(payload, account: account))
    }

    /// A `/comments/<id>` response (or its "continue this thread" variant).
    public static func commentsLoaded(_ data: Data, requestedBy account: String?) {
        guard isCapturing, let account, account == activeAccount else { return }
        let (post, comments) = SiriContentSanitizer.commentsResponse(data)
        if let post { sink?(.openedPost(post, account: account)) }
        for chunk in comments { sink?(.comments(chunk, account: account)) }
    }

    public static func moreCommentsLoaded(_ things: [JSONValue], requestedBy account: String?) {
        guard isCapturing, let account, account == activeAccount else { return }
        for chunk in SiriContentSanitizer.moreChildren(things) { sink?(.comments(chunk, account: account)) }
    }

    /// A hide, delete or unsubscribe is requested, or an unhide or subscribe
    /// succeeded. Names are `t3_…`, `t5_…` or `r/<name>`.
    public static func eligibilityChanged(_ names: [String], allow: Bool) {
        guard isCapturing, !names.isEmpty, let account = activeAccount else { return }
        let capped = Array(names.prefix(SiriContentLimits.tombstones))
        sink?(allow ? .allow(capped, account: account) : .suppress(capped, account: account))
    }
}

/// The account the index belongs to, from the stored accounts, so a
/// background launch (an intent or a Spotlight request) needs no UI.
public enum SiriAccountStatus: Sendable, Equatable {
    /// Can't be told yet (the keychain is locked before first unlock): keep
    /// what is held and answer nothing.
    case unresolved
    case signedOut
    case signedIn(String)

    public static func resolve(_ persisted: AccountStorePersisted?, locked: Bool) -> SiriAccountStatus {
        guard let persisted else { return locked ? .unresolved : .signedOut }
        guard let index = persisted.activeIndex, persisted.accounts.indices.contains(index) else { return .signedOut }
        return .signedIn(persisted.accounts[index].username)
    }

    public static func current(store: any AccountKeychainStore = AccountKeychainStoreBox()) -> SiriAccountStatus {
        resolve(store.load(), locked: store.isLocked)
    }

    /// A one-way fingerprint of the username that scopes the index; never
    /// the username itself.
    public static func fingerprint(_ username: String) -> String {
        SHA256Digest.hex(Data(username.lowercased().utf8))
    }
}

/// Settings, Shortcuts and Siri tell people what the index holds.
public enum SiriContentStatus {
    public static func text(enabled: Bool, signedIn: Bool, posts: Int, communities: Int) -> String {
        guard enabled else { return "Phoebus content indexing is off. Its post and subscription index is cleared." }
        guard signedIn else {
            return "Phoebus content indexing is enabled. Sign in and browse Phoebus to collect eligible public content."
        }
        return "Phoebus catalogue: \(posts) posts and \(communities) subscribed communities. Public, non-NSFW content only; up to 30 days of loaded content."
    }

    public static func incompleteRefresh(_ status: String) -> String {
        "\(status) Reached the \(SiriContentLimits.communities)-subscription fetch limit; no missing entries were removed."
    }
}

/// What Settings drives. The app target installs it with the service.
public protocol SiriContentControlling: Sendable {
    func setIndexing(_ enabled: Bool) async -> String
    func indexStatus() async -> String
    func refreshSubscriptions() async -> String
}

public enum SiriContent {
    public nonisolated(unsafe) static var controller: (any SiriContentControlling)?
}

public extension Notification.Name {
    /// The ids the app may annotate onscreen changed (content, eligibility,
    /// opt-out or account).
    static let phoebusSiriOnscreenChanged = Notification.Name("Phoebus.siriOnscreenChanged")
}

/// Which posts and comments the app may annotate for Siri right now. The
/// content service replaces it after every change, so a row asks
/// synchronously and a hidden post, an opt-out or an account change drops
/// its annotation at once.
public enum SiriOnscreen {
    private static let state = LockedValue<Set<String>>([])

    public static func contains(_ id: String) -> Bool { state.withValue { $0.contains(id) } }

    public static func replace(with ids: Set<String>) {
        let changed = state.withValue { current -> Bool in
            guard current != ids else { return false }
            current = ids
            return true
        }
        if changed { NotificationCenter.default.post(name: .phoebusSiriOnscreenChanged, object: nil) }
    }

    /// The catalogue id of a post fullname, as annotations name it.
    public static func postID(_ fullName: String) -> String? {
        SiriContentRecord.identifier(["kind": "t3", "name": fullName])
    }

    public static func commentID(_ fullName: String) -> String? { SiriCommentRecord.identifier(fullName) }
}

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func withValue<T>(_ body: (inout Value) -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body(&value)
    }
}
