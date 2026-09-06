import SwiftUI
import PhoebusCore

/// Small circular avatar next to a username, reimplementing Apollo-
/// Reborn's "User Profile Pictures" for feed rows and comment rows
/// (`UserProfileScreen` already renders the full-size avatar on the
/// profile screen itself via `RedditUser.iconImage` directly). Resolves
/// the avatar URL through `AvatarCache`/`fetchUserProfile` on first
/// appearance and reuses it for the rest of the session.
public struct AvatarView: View {
    let username: String
    let repository: RedditRepository
    let size: CGFloat

    @State private var avatarURLString: String?
    /// Reborn #1136 "Profile Picture Shape": the Profile Layout avatar
    /// style applies to every user picture. Square is a rounded square
    /// with a 0.24 x side corner; Full and Circle both clip round.
    @Setting(ProfileLayoutSettings.self) private var profileLayout
    private var shape: ProfileLayoutSettings.AvatarStyle { profileLayout.avatarStyle }
    @State private var isLoading = false

    public init(username: String, repository: RedditRepository, size: CGFloat = 20) {
        self.username = username
        self.repository = repository
        self.size = size
    }

    public var body: some View {
        Group {
            if let avatarURLString, let url = URL(string: avatarURLString) {
                CachedAsyncImage(url: url)
                    .clipShape(AvatarClipShape(style: shape))
            } else {
                AvatarClipShape(style: shape)
                    .fill(Color.secondary.opacity(0.2))
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.5))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: size, height: size)
        .task(id: username) { await resolve() }
    }

    private func resolve() async {
        // [deleted]/removed authors have no profile to fetch, and
        // AutoModerator-style bots are common enough to skip the round-trip.
        guard username != "[deleted]", !username.isEmpty else { return }
        if let cached = await AvatarCache.shared.cachedURL(for: username) {
            avatarURLString = cached
            return
        }
        if await AvatarCache.shared.hasFreshEntry(for: username) {
            // Cached as "no avatar" — leave the placeholder showing.
            return
        }
        // A thread's batch lookup may already cover this author (#1220).
        await AvatarCache.shared.awaitPending(username)
        if await AvatarCache.shared.hasFreshEntry(for: username) {
            avatarURLString = await AvatarCache.shared.cachedURL(for: username)
            return
        }
        // Rate-limited: stand down without caching a miss, so the picture
        // comes back once Reddit's window resets.
        guard RedditRateLimitHold.shared.remaining() == 0 else { return }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let user = try await repository.fetchUserProfile(username: username)
            await AvatarCache.shared.store(url: user.iconImage, for: username)
            avatarURLString = user.iconImage
        } catch {
            if case RedditAPIError.httpError(429, _)? = error as? RedditAPIError { return }
            // Cache the miss too, so a failing/suspended account
            // doesn't get re-queried on every row appearance.
            await AvatarCache.shared.store(url: nil, for: username)
        }
    }
}

/// The shared user-picture clip: Square is
/// a rounded rect at `width * 0.24`, anything else a circle.
public struct AvatarClipShape: Shape {
    public let style: ProfileLayoutSettings.AvatarStyle
    public init(style: ProfileLayoutSettings.AvatarStyle) { self.style = style }
    public func path(in rect: CGRect) -> Path {
        style == .square
            ? RoundedRectangle(cornerRadius: rect.width * 0.24, style: .continuous).path(in: rect)
            : Circle().path(in: rect)
    }
}
