import Foundation
import AuthenticationServices
import PhoebusCore
#if canImport(UIKit)
import UIKit
#endif

/// Shared OAuth-callback-URL fetcher used by `LoginScreen` and the account
/// manager's "Add Account" flow. Picks Apple's `ASWebAuthenticationSession` or
/// the in-app `CustomOAuthSession` based on `CustomAPISettings.useCustomOAuthSignIn`,
/// the "Universal OAuth Sign-In" switch. With the switch on, sign-in doesn't
/// depend on the redirect URI's scheme being registered with the OS, which is
/// what makes http/https "Web app" redirect URIs work.
enum OAuthCallbackAuthenticator {
    /// Presents whichever OAuth UI is configured and waits for the
    /// provider to redirect back to `RedditOAuthConfig.redirectURI`.
    /// Throws if the user cancels, the provider errors, or (native path
    /// only) the redirect URI has no URL scheme to register.
    @MainActor
    static func fetchCallbackURL(authorizeURL: URL, contextProvider: ASWebAuthenticationPresentationContextProviding) async throws -> URL {
        let useCustom = CustomAPISettingsStore.load().useCustomOAuthSignIn
        #if canImport(WebKit) && canImport(UIKit)
        if useCustom {
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                let session = CustomOAuthSession(url: authorizeURL, redirectURIPrefix: RedditOAuthConfig.redirectURI) { url, error in
                    if let url {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: error ?? URLError(.unknown))
                    }
                }
                session.start()
            }
        }
        #endif
        // Native path (default, and the only path on platforms without
        // WebKit/UIKit).
        guard let scheme = URL(string: RedditOAuthConfig.redirectURI)?.scheme else {
            throw URLError(.badURL)
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(url: authorizeURL, callbackURLScheme: scheme) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? URLError(.unknown))
                }
            }
            session.presentationContextProvider = contextProvider
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }
}
