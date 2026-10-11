import Foundation

/// Decisions for signing in to a Reddit account through a web view. Each
/// sign-in runs on its own throwaway cookie store (a fresh
/// `WKWebsiteDataStore.nonPersistent()`, or an ephemeral
/// `ASWebAuthenticationSession`) instead of the shared persistent one, so
/// Reddit always shows its login form rather than "already logged in" for a
/// session left by an earlier account. The harvested cookies are saved on the
/// account (`WebSessionCredential`), never read back from a shared store.
/// Reborn's "Add Account" gets the same effect by clearing the shared jar
/// first, and its OAuth flow uses a non-persistent store.
public enum SignInSessionPolicy {
    public enum HarvestVerdict: Equatable, Sendable {
        case accept
        /// The web view signed in as someone other than the account the caller
        /// needs; carries the username Reddit actually signed in as.
        case mismatch(signedInAs: String)
    }

    /// With `requiredUsername` set (session-expired re-login, Edit Profile,
    /// Polls) the harvest must belong to that account, or Phoebus would act
    /// as a different user than the one it is acting for.
    public static func verdict(requiredUsername: String?, harvestedUsername: String) -> HarvestVerdict {
        guard let requiredUsername, !requiredUsername.isEmpty else { return .accept }
        if requiredUsername.lowercased() == harvestedUsername.lowercased() { return .accept }
        return .mismatch(signedInAs: harvestedUsername)
    }
}
