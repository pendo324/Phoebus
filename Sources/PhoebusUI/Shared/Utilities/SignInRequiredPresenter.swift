import SwiftUI
import PhoebusCore

/// Presents Apollo's "Sign In to X" alerts app-wide.
///
/// A signed-out write otherwise fails silently: the vote is applied
/// optimistically, the request throws `RedditAPIError.notAuthenticated`, and
/// the catch reverts it. Apollo names the action in a titled alert (verbatim
/// strings in `SignInRequiredCopy`).
///
/// The voting helpers are plain enums called from a dozen screens, so this
/// routes through a single shared presenter any screen can host rather than
/// threading alert state through every call site.
@MainActor
public final class SignInRequiredPresenter: ObservableObject {
    public static let shared = SignInRequiredPresenter()

    @Published public var pendingAction: SignInRequiredCopy.Action?

    private init() {}

    /// Raises the real alert for `action` if `error` is Reddit's
    /// not-authenticated case. Returns true when it handled the error,
    /// so callers can tell "signed out" apart from a real failure.
    @discardableResult
    public func presentIfNotAuthenticated(_ error: Error, action: SignInRequiredCopy.Action) -> Bool {
        guard SignInRequiredCopy.isSignedOut(error) else { return false }
        pendingAction = action
        return true
    }
}

extension SignInRequiredCopy.Action: Identifiable {
    public var id: String { title + message }
}

public extension View {
    /// Hosts the real sign-in-required alert.
    func apolloSignInRequiredAlert() -> some View {
        modifier(SignInRequiredAlertModifier())
    }
}

struct SignInRequiredAlertModifier: ViewModifier {
    @ObservedObject private var presenter = SignInRequiredPresenter.shared

    func body(content: Content) -> some View {
        content.alert(item: $presenter.pendingAction) { action in
            Alert(
                title: Text(action.title),
                message: Text(action.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}
