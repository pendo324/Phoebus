import Foundation

/// How an author's name is coloured in comment headers, feed rows and the
/// post header. Phoebus-only: the signed-in user's own name and users they
/// follow stand out, behind Reddit's moderator/admin distinguish, which
/// always wins.
public enum AuthorHighlight: Equatable, Sendable {
    case none
    case moderator
    case admin
    case own
    case followed

    /// `distinguished` is Reddit's value ("moderator", "admin" or nil).
    /// `followedUsernames` must be lowercased (see `FollowedUsernames`).
    public static func resolve(
        author: String,
        distinguished: String?,
        ownUsername: String?,
        followedUsernames: Set<String>,
        highlightOwn: Bool,
        highlightFollowed: Bool
    ) -> AuthorHighlight {
        switch distinguished {
        case "moderator": return .moderator
        case "admin": return .admin
        default: break
        }
        guard !author.isEmpty, author != "[deleted]" else { return .none }
        if highlightOwn, let ownUsername, author.caseInsensitiveCompare(ownUsername) == .orderedSame {
            return .own
        }
        if highlightFollowed, followedUsernames.contains(author.lowercased()) { return .followed }
        return .none
    }

    /// `resolve` for the signed-in account and the current settings. The
    /// followed set is only read when its setting is on.
    public static func current(author: String, distinguished: String?, settings: GeneralSettings) -> AuthorHighlight {
        resolve(
            author: author,
            distinguished: distinguished,
            ownUsername: settings.highlightOwnUsername ? FavoriteSubredditsAccountContext.currentUsernameProvider() : nil,
            followedUsernames: settings.highlightFollowedUsers ? FollowedUsernames.current() : [],
            highlightOwn: settings.highlightOwnUsername,
            highlightFollowed: settings.highlightFollowedUsers)
    }
}

/// The signed-in account's followed users: the Subreddits list's
/// "Following" section (Reddit lists a followed profile as a `u_<name>`
/// subscription) together with the account's Reddit friends, which is what
/// the profile's Follow button adds to (`/api/friend`). Held in memory so
/// colouring a row is a set lookup. The `u_` part is filled from
/// `SubredditListCache` and replaced whenever that cache is saved; the
/// friends part is fetched once per account per launch and again with each
/// Subreddits list refresh. Neither refresh touches the other part, and
/// Follow/Unfollow adjust the friends part at once.
public enum FollowedUsernames {
    /// Posted when the set changes outside a Subreddits list refresh
    /// (friends arriving, Follow/Unfollow), so visible rows recolour.
    public static let didChangeNotification = Notification.Name("FollowedUsernamesDidChange")

    /// Loads the friends list; nil on failure. Replaceable so the smoke
    /// suite can run without a network.
    public nonisolated(unsafe) static var friendsFetcher: @Sendable () async -> [String]? = {
        guard let repository = ActiveRedditRepository.provider() else { return nil }
        return try? await repository.fetchFriends().map(\.name)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cachedAccount: String?
    nonisolated(unsafe) private static var subscriptionNames: Set<String> = []
    nonisolated(unsafe) private static var friendNames: Set<String> = []
    /// Whether the friends part has been fetched (or is being fetched) for
    /// `cachedAccount` this launch.
    nonisolated(unsafe) private static var friendsRequested = false
    nonisolated(unsafe) private static var friendsTask: Task<Void, Never>?
    /// Identifies the current fetch; bumped by each new fetch and by an
    /// account change, so an outdated result is dropped.
    nonisolated(unsafe) private static var friendsGeneration = 0
    /// Follow/Unfollow made while a friends fetch is in flight, re-applied
    /// to its result so a slower, older list can't undo them.
    nonisolated(unsafe) private static var pendingFriendEdits: [String: Bool] = [:]

    /// Lowercased usernames behind the `u_` entries of a subscription list.
    public static func from(subredditNames: [String]) -> Set<String> {
        Set(subredditNames.compactMap { name in
            let lowered = name.lowercased()
            guard lowered.hasPrefix("u_"), lowered.count > 2 else { return nil }
            return String(lowered.dropFirst(2))
        })
    }

    /// The current account's followed users; empty when signed out. The
    /// first read for an account starts the friends fetch in the
    /// background.
    public static func current() -> Set<String> {
        guard let username = FavoriteSubredditsAccountContext.currentUsernameProvider(), !username.isEmpty else { return [] }
        lock.lock()
        loadIfNeeded(account: username)
        let names = subscriptionNames.union(friendNames)
        let needsFriends = !friendsRequested
        lock.unlock()
        if needsFriends { startFriendsFetch(account: username) }
        return names
    }

    /// A Follow or Unfollow that succeeded, so the highlight changes at once.
    public static func setFollowed(_ username: String, followed: Bool) {
        guard let account = FavoriteSubredditsAccountContext.currentUsernameProvider(), !account.isEmpty,
              !username.isEmpty else { return }
        let name = username.lowercased()
        lock.lock()
        loadIfNeeded(account: account)
        if followed {
            friendNames.insert(name)
        } else {
            friendNames.remove(name)
        }
        if friendsTask != nil { pendingFriendEdits[name] = followed }
        lock.unlock()
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    /// Called with a fresh subscription list for `account`. Replaces the
    /// `u_` part only, and refetches friends alongside it.
    public static func update(account: String, subredditNames: [String]) {
        let names = from(subredditNames: subredditNames)
        lock.lock()
        loadIfNeeded(account: account)
        subscriptionNames = names
        lock.unlock()
        startFriendsFetch(account: account)
    }

    /// Refetches the friends part for the active account and waits for it.
    public static func refreshFriends() async {
        guard let account = FavoriteSubredditsAccountContext.currentUsernameProvider(), !account.isEmpty else { return }
        startFriendsFetch(account: account)
        await inFlightFriendsFetch()?.value
    }

    private static func inFlightFriendsFetch() -> Task<Void, Never>? {
        lock.lock()
        defer { lock.unlock() }
        return friendsTask
    }

    /// Forgets the set, so the next read reloads it for whichever account
    /// is active.
    public static func invalidate() {
        lock.lock()
        cachedAccount = nil
        subscriptionNames = []
        friendNames = []
        friendsRequested = false
        friendsTask = nil
        friendsGeneration += 1
        pendingFriendEdits = [:]
        lock.unlock()
    }

    /// Caller holds `lock`. A different account starts from its own cached
    /// list with no friends yet.
    private static func loadIfNeeded(account: String) {
        guard cachedAccount != account else { return }
        let subscriptions = SubredditListCache.load(for: account)?.subscriptions ?? []
        cachedAccount = account
        subscriptionNames = from(subredditNames: subscriptions.map(\.displayName))
        friendNames = []
        friendsRequested = false
        friendsTask = nil
        friendsGeneration += 1
        pendingFriendEdits = [:]
    }

    /// One fetch at a time; its result replaces the friends part only if
    /// it is still the current fetch. A failure keeps what is already there.
    private static func startFriendsFetch(account: String) {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded(account: account)
        guard friendsTask == nil else { return }
        friendsRequested = true
        pendingFriendEdits = [:]
        friendsGeneration += 1
        let generation = friendsGeneration
        let fetch = friendsFetcher
        friendsTask = Task {
            let fetched = await fetch()
            if applyFetchedFriends(fetched, generation: generation) {
                NotificationCenter.default.post(name: didChangeNotification, object: nil)
            }
        }
    }

    /// Returns whether the set changed.
    private static func applyFetchedFriends(_ fetched: [String]?, generation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard generation == friendsGeneration else { return false }
        friendsTask = nil
        defer { pendingFriendEdits = [:] }
        guard let fetched else { return false }
        var names = Set(fetched.map { $0.lowercased() })
        for (name, followed) in pendingFriendEdits {
            if followed { names.insert(name) } else { names.remove(name) }
        }
        let changed = names != friendNames
        friendNames = names
        return changed
    }
}
