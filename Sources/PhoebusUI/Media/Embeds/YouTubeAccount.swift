import SwiftUI
import UIKit
import WebKit
import PhoebusCore

extension Notification.Name {
    /// Posted after signing in to or out of YouTube, so players pick it up.
    static let youTubeSessionChanged = Notification.Name("PhoebusYouTubeSessionChanged")
}

/// The signed-in YouTube session (Phoebus-only). It lives in its own
/// persistent website data store, which every YouTube player web view and
/// the sign-in sheet share, so YouTube's cookies stay apart from the in-app
/// browser's and the Reddit web sessions'.
@MainActor
final class YouTubeAccount: ObservableObject {
    static let shared = YouTubeAccount()

    static let dataStore = WKWebsiteDataStore(forIdentifier: UUID(uuidString: "3C7A9E52-84D1-4B6F-A0E3-5F2D1C9B7A68")!)

    @Published private(set) var isSignedIn = false

    private init() {
        Task { await refresh() }
    }

    func refresh() async {
        let signedIn = YouTubeSession.hasSession(cookieNames: await youTubeCookies().map(\.name))
        if signedIn != isSignedIn { isSignedIn = signedIn }
    }

    func signOut() async {
        await Self.dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        await sessionChanged()
    }

    func importCookies(_ imported: [YouTubeImportedCookie]) async {
        let store = Self.dataStore.httpCookieStore
        // A session cookie would be gone at the next launch.
        let fallbackExpiry = Date(timeIntervalSinceNow: 365 * 24 * 60 * 60)
        for cookie in imported {
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: cookie.name, .value: cookie.value, .domain: cookie.domain, .path: cookie.path,
                .expires: cookie.expires ?? fallbackExpiry,
            ]
            if cookie.isSecure { properties[.secure] = "TRUE" }
            if cookie.isHTTPOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            guard let httpCookie = HTTPCookie(properties: properties) else { continue }
            await store.setCookie(httpCookie)
        }
        await sessionChanged()
    }

    /// For the sign-in sheet, which sees the session appear first.
    func sessionChanged() async {
        await refresh()
        NotificationCenter.default.post(name: .youTubeSessionChanged, object: nil)
    }

    private func youTubeCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            Self.dataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies.filter { $0.domain.lowercased().hasSuffix("youtube.com") })
            }
        }
    }
}

/// Google's sign-in for YouTube in a sheet. Closes itself once youtube.com
/// holds a signed-in session.
struct YouTubeSignInSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            YouTubeSignInWebView {
                Task {
                    await YouTubeAccount.shared.sessionChanged()
                    dismiss()
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Sign In to YouTube")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("youtube.signIn.cancel")
                }
            }
        }
    }
}

private struct YouTubeSignInWebView: UIViewRepresentable {
    let onSignedIn: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSignedIn: onSignedIn) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = YouTubeAccount.dataStore
        let webView = WKWebView(frame: .zero, configuration: configuration)
        // Google serves its sign-in form to Safari's identity, as the Google
        // search session does.
        webView.customUserAgent = GoogleSearchSession.userAgent(desktop: GoogleSearchSession.usesDesktopLayout)
        webView.navigationDelegate = context.coordinator
        YouTubeAccount.dataStore.httpCookieStore.add(context.coordinator)
        webView.load(URLRequest(url: YouTubeSession.signInURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        YouTubeAccount.dataStore.httpCookieStore.remove(coordinator)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        let onSignedIn: () -> Void
        private var finished = false

        init(onSignedIn: @escaping () -> Void) { self.onSignedIn = onSignedIn }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) { check() }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { check() }

        private func check() {
            guard !finished else { return }
            YouTubeAccount.dataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                let names = cookies.filter { $0.domain.lowercased().hasSuffix("youtube.com") }.map(\.name)
                guard YouTubeSession.hasSession(cookieNames: names) else { return }
                Task { @MainActor in
                    guard let self, !self.finished else { return }
                    self.finished = true
                    self.onSignedIn()
                }
            }
        }
    }
}

/// Pasting a browser's YouTube cookies, for when Google won't sign in
/// inside the app.
struct YouTubeImportCookiesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var result: YouTubeCookieImport.Result?
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 180)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("youtube.importCookies.text")
                } footer: {
                    Text("Paste a cookies.txt export or the Cookie header of a signed-in youtube.com request. Only youtube.com and google.com cookies are kept.")
                }
                if let result, !result.hasSession {
                    Section {
                        Text(result.cookies.isEmpty
                             ? "No youtube.com or google.com cookies found."
                             : "Those cookies don't include a signed-in session (SAPISID or LOGIN_INFO).")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Import YouTube Cookies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { importPasted() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting)
                        .accessibilityIdentifier("youtube.importCookies.import")
                }
            }
        }
    }

    private func importPasted() {
        let parsed = YouTubeCookieImport.parse(text)
        result = parsed
        guard parsed.hasSession else { return }
        isImporting = true
        Task {
            await YouTubeAccount.shared.importCookies(parsed.cookies)
            dismiss()
        }
    }
}
