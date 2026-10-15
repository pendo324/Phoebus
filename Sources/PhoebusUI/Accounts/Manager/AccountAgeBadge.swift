import SwiftUI
import PhoebusCore

/// Reborn's "New Account Highlight" (`GeneralSettings.highlightAccountAge`).
/// Account creation date is not on comment/post listing objects, so
/// `accountAgeLookup` does a per-username lookup like `AvatarView` (see
/// `AccountAgeCache`). The badge renders nothing until the lookup resolves
/// with a usable date, and stays silent for an author whose lookup fails.
public struct AccountAgeBadge: View {
    let createdAt: Date?

    public init(createdAt: Date?) {
        self.createdAt = createdAt
    }

    public var body: some View {
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
}

private struct AccountAgeLookupModifier: ViewModifier {
    let username: String
    let isEnabled: Bool
    let repository: RedditRepository
    @Binding var createdAt: Date?

    func body(content: Content) -> some View {
        // On the row's always-present author name rather than on the badge: a
        // `.task` on a badge that is empty until the answer arrives never runs.
        content.task(id: isEnabled ? username : nil) {
            guard isEnabled, AccountAgeCache.isLookupCandidate(username: username) else {
                createdAt = nil
                return
            }
            let repository = repository, username = username
            createdAt = await AccountAgeCache.shared.createdDate(for: username) {
                try await repository.fetchUserProfile(username: username).created
            }
        }
    }
}

extension View {
    /// Resolves `username`'s account creation date into `createdAt` while
    /// New Account Highlight is on.
    func accountAgeLookup(for username: String, isEnabled: Bool, repository: RedditRepository,
                          into createdAt: Binding<Date?>) -> some View {
        modifier(AccountAgeLookupModifier(username: username, isEnabled: isEnabled,
                                          repository: repository, createdAt: createdAt))
    }
}
