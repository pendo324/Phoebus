import SwiftUI
import PhoebusCore

/// Reborn's "New Account Highlight" (`GeneralSettings.highlightAccountAge`).
/// Account creation date is not on comment/post listing objects, so this
/// does a per-username lookup like `AvatarView` (see `AccountAgeCache`). It
/// renders nothing until the lookup resolves with a usable date, and stays
/// silent for an author whose lookup fails.
public struct AccountAgeBadge: View {
    let username: String
    let repository: RedditRepository

    @State private var createdAt: Date?
    @State private var isLoading = false

    public init(username: String, repository: RedditRepository) {
        self.username = username
        self.repository = repository
    }

    public var body: some View {
        Group {
            if let createdAt, AccountAgeCache.isNewAccount(createdAt: createdAt) {
                Text("NEW")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.orange))
                    .accessibilityLabel("New account")
            }
        }
        .task(id: username) { await resolve() }
    }

    private func resolve() async {
        guard username != "[deleted]", username != "AutoModerator", !username.isEmpty else { return }
        if let cached = await AccountAgeCache.shared.cachedCreatedDate(for: username) {
            createdAt = cached
            return
        }
        if await AccountAgeCache.shared.hasFreshEntry(for: username) {
            // Cached as "lookup failed/unavailable": stay silent.
            return
        }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let user = try await repository.fetchUserProfile(username: username)
            await AccountAgeCache.shared.store(createdAt: user.created, for: username)
            createdAt = user.created
        } catch {
            // Suspended/shadowbanned/deleted accounts or a transient network error:
            // cache the miss too so a failing author is not re-queried on every row
            // appearance, and show nothing.
            await AccountAgeCache.shared.store(createdAt: nil, for: username)
        }
    }
}
