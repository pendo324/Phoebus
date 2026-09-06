import AuthenticationServices
#if canImport(UIKit)
import UIKit
#endif

/// Anchors the sign-in sheet on the app's key window. A bare
/// `ASPresentationAnchor()` is a new, detached window.
final class AuthPresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        // ASWebAuthenticationSession asks on the main thread.
        return MainActor.assumeIsolated { UIKitTree.keyWindow } ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}
