import Foundation

/// What `/user/<name>/about` says that a row draws: the avatar and the
/// account's creation date.
public struct UserProfileSnapshot: Sendable, Equatable {
    public let iconURL: String?
    public let createdAt: Date

    public init(iconURL: String?, createdAt: Date) {
        self.iconURL = iconURL
        self.createdAt = createdAt
    }

    public init(user: RedditUser) {
        self.init(iconURL: user.iconImage, createdAt: user.created)
    }
}

/// The one place a username's `/about` is fetched for the avatar (Reborn
/// "User Profile Pictures") and the NEW badge (Reborn "New Account Highlight").
/// Both used to ask for it on their own, so an author beside both settings
/// cost two requests; now whichever asks first fetches once (callers that ask
/// meanwhile share it) and fills `AvatarCache` and `AccountAgeCache`, which
/// the other then finds fresh. An account Reddit has no page for is recorded
/// as a miss in both; a failed connection or a 429 is recorded in neither.
public actor UserProfileSnapshotCache {
    public static let shared = UserProfileSnapshotCache()

    private var lookups: [String: Task<UserProfileSnapshot, Error>] = [:]

    private init() {}

    public func snapshot(for username: String, repository: RedditRepository) async throws -> UserProfileSnapshot {
        try await snapshot(for: username) {
            UserProfileSnapshot(user: try await repository.fetchUserProfile(username: username))
        }
    }

    public func snapshot(for username: String,
                         fetch: @escaping @Sendable () async throws -> UserProfileSnapshot) async throws -> UserProfileSnapshot {
        let key = username.lowercased()
        if let running = lookups[key] { return try await running.value }
        let task = Task { try await fetch() }
        lookups[key] = task
        do {
            let snapshot = try await task.value
            lookups[key] = nil
            await AvatarCache.shared.storeIfAbsent(url: snapshot.iconURL, for: username)
            await AccountAgeCache.shared.store(createdAt: snapshot.createdAt, for: username)
            return snapshot
        } catch {
            lookups[key] = nil
            let failure = ProfileLookupFailure(error)
            await AvatarCache.shared.store(failure: failure, for: username)
            if failure.isDefinitiveMiss { await AccountAgeCache.shared.store(createdAt: nil, for: username) }
            throw error
        }
    }
}
