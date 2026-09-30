import SwiftUI

/// Reborn's "Can't sign in?" troubleshooting disclosure, reachable from the
/// "Sign-In" section of Accounts & API Keys. Content is verbatim from Reborn.
/// Sign-in failures in the embedded web view are most commonly a stuck
/// cookie-consent prompt rather than a credentials problem, so steps 1-4 cover
/// that first.
public struct SignInTroubleshootingScreen: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("If you're having trouble signing in, try the following:")
                    .font(.subheadline)

                step(
                    number: 1,
                    title: "Accept cookies first",
                    body: "Tap the X in the upper-right corner of the sign-in page to return to Reddit homepage. Accept the cookies prompt, then tap back to return to the sign-in page and refresh."
                )
                step(
                    number: 2,
                    title: "Rotate to landscape",
                    body: "If the email/password fields aren't responding, rotate your device to landscape. The cookies banner may appear in the bottom-right. Accept it, then try inputting your credentials again."
                )
                step(
                    number: 3,
                    title: "Request Desktop Website",
                    body: "While on the sign-in page, tap the page settings icon in the upper-right of the toolbar and tap \"Request Desktop Website\". This can fix issues where sign-in appears to succeed but the account never appears."
                )
                step(
                    number: 4,
                    title: "Clear reddit.com cookies in Safari",
                    body: "Go to Settings → Apps → Safari → Advanced → Website Data, search for \"reddit\", and delete the cookies. Then try signing in again."
                )

                Divider()

                // Further common causes: a redirect URI mismatch (what "Universal OAuth Sign-In"
                // addresses) and API-key problems, which are distinct from the cookie issue above.
                Text("Other common causes")
                    .font(.headline)
                step(
                    number: 5,
                    title: "Redirect URI mismatch",
                    body: "If you're using your own Reddit API client, its \"redirect uri\" in reddit.com/prefs/apps must match exactly what's configured under Custom API here, including scheme and trailing slashes. A mismatch fails silently or shows a generic Reddit error page. If your client's redirect URI is an ordinary http(s):// URL rather than a custom app scheme, turn on \"Universal OAuth Sign-In\" (Accounts & API Keys → Sign-In) — it uses an in-app web view instead of relying on the OS to catch the redirect."
                )
                step(
                    number: 6,
                    title: "Revoked or rate-limited API key",
                    body: "Reddit periodically revokes third-party client IDs it flags as suspicious, and can rate-limit or block a client ID entirely. If sign-in previously worked and suddenly stopped for everyone using the same key, register a fresh client ID at reddit.com/prefs/apps and enter it under Custom API."
                )
                step(
                    number: 7,
                    title: "Clock skew",
                    body: "OAuth token exchange is time-sensitive. If your device's clock is significantly wrong (common right after a factory reset, or with automatic time disabled), token requests can be rejected. Check Settings → General → Date & Time and enable \"Set Automatically\"."
                )
                step(
                    number: 8,
                    title: "Blocked in your region",
                    body: "Reddit blocks API and/or web access from some countries and networks. If sign-in consistently fails only on a particular network (e.g. a specific VPN exit or a workplace/school network), try a different network to confirm before assuming it's an app problem."
                )
            }
            .padding()
        }
        .navigationTitle("Can't sign in?")
    }

    private func step(number: Int, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(number). \(title)")
                .font(.subheadline.bold())
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
