import SwiftUI
import PhoebusCore

/// Under a quarantined subreddit's error: Reddit's own warning and, when
/// signed in, "View Anyway", which opts the account in after a
/// confirmation. Not in Apollo or Reborn.
public struct QuarantineOptInView: View {
    let subreddit: String
    let notice: QuarantineNotice
    let repository: RedditRepository
    let buttonIdentifier: String
    /// Runs once the account has opted in, to reload what was refused.
    let onOptedIn: () async -> Void

    @State private var confirming = false
    @State private var isOptingIn = false
    @State private var failure: String?

    public init(subreddit: String, notice: QuarantineNotice, repository: RedditRepository,
                buttonIdentifier: String = "quarantine.viewAnyway", onOptedIn: @escaping () async -> Void) {
        self.subreddit = subreddit
        self.notice = notice
        self.repository = repository
        self.buttonIdentifier = buttonIdentifier
        self.onOptedIn = onOptedIn
    }

    private var isSignedIn: Bool { FavoriteSubredditsAccountContext.currentUsernameProvider() != nil }

    public var body: some View {
        VStack(spacing: 12) {
            if let message = notice.message {
                LongBodyText(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("quarantine.message")
            }
            if isSignedIn {
                Button {
                    confirming = true
                } label: {
                    if isOptingIn {
                        ProgressView()
                    } else {
                        Text("View Anyway").fontWeight(.semibold)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isOptingIn)
                .accessibilityIdentifier(buttonIdentifier)
            } else {
                Text("Sign in to view quarantined subreddits.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("quarantine.signInRequired")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .alert("View r/\(subreddit)?", isPresented: $confirming) {
            Button("View Anyway") { Task { await optIn() } }
                .accessibilityIdentifier("quarantine.confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This subreddit is quarantined and may contain highly offensive or upsetting content. Viewing it opts your Reddit account in; you can leave from the subreddit's ••• menu.")
        }
        .alert("Couldn't Opt In", isPresented: $failure.isPresent()) {
            Button("OK") { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }

    private func optIn() async {
        isOptingIn = true
        defer { isOptingIn = false }
        do {
            try await repository.setQuarantineOptIn(subredditName: subreddit, optIn: true)
            await onOptedIn()
        } catch {
            failure = UserFacingError.message(for: error)
        }
    }
}
