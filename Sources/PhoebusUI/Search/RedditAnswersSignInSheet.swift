#if canImport(UIKit)
import SwiftUI
import PhoebusCore

/// Reddit Answers talks to Reddit the way the website does, so it needs a
/// reddit.com web session. This is the same one-time sign-in polls use; the
/// session is kept for the active account.
struct RedditAnswersSignInSheet: View {
    @Environment(\.accountManager) private var accountManager
    @Environment(\.dismiss) private var dismiss
    let onSignedIn: () -> Void

    var body: some View {
        NavigationStack {
            WebSessionLoginScreen(
                requiredUsername: activeUsername,
                onSuccess: { credential in
                    accountManager?.addWebSessionAccount(credential)
                    dismiss()
                    onSignedIn()
                },
                onCancel: { dismiss() }
            )
        }
    }

    private var activeUsername: String? {
        guard let accountManager, let index = accountManager.activeIndex,
              accountManager.accounts.indices.contains(index) else { return nil }
        return accountManager.accounts[index].username
    }
}
#endif
