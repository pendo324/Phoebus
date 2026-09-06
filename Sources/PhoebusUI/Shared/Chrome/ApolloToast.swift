#if canImport(UIKit)
import SwiftUI
import UIKit
import PhoebusCore

/// A short notice at the top of the screen, over everything and never in
/// the way of a touch (error style).
@MainActor
enum ApolloToast {
    private static var window: UIWindow?
    private static var hideWork: DispatchWorkItem?

    static func showError(_ title: String, detail: String, systemImage: String = "exclamationmark.triangle") {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }
        let host = UIHostingController(rootView: ToastView(title: title, detail: detail, systemImage: systemImage))
        host.view.backgroundColor = .clear
        let window = window ?? UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.isUserInteractionEnabled = false
        window.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false
        window.alpha = 0
        Self.window = window
        UIView.animate(withDuration: 0.25) { window.alpha = 1 }
        hideWork?.cancel()
        let work = DispatchWorkItem {
            UIView.animate(withDuration: 0.3, animations: { window.alpha = 0 }) { _ in window.isHidden = true }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
    }

    private struct ToastView: View {
        let title: String
        let detail: String
        let systemImage: String

        var body: some View {
            VStack {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.subheadline.weight(.semibold))
                        Text(detail).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
                .padding(.top, 8)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("toast")
                Spacer()
            }
        }
    }
}

/// Says when Reddit is rate-limiting the API-Key-Free account, rather
/// than leaving a feed spinning (Reborn #1220/#1225): when the limit
/// starts, and again on returning to the app while it holds, at most
/// once every 30 s.
@MainActor
enum RedditRateLimitNotice {
    private static var lastShown: Date = .distantPast

    static func show(seconds: TimeInterval) {
        guard seconds > 0, Date().timeIntervalSince(lastShown) >= 30 else { return }
        lastShown = Date()
        ApolloToast.showError("Reddit Rate Limit Reached", detail: RedditRateLimitHold.detail(seconds: seconds))
    }

    static func showIfHolding() {
        show(seconds: RedditRateLimitHold.shared.remaining())
    }
}

private struct RateLimitNoticeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .apolloRedditRateLimited)) { note in
                RedditRateLimitNotice.show(seconds: note.userInfo?["seconds"] as? TimeInterval ?? 0)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                RedditRateLimitNotice.showIfHolding()
            }
    }
}

public extension View {
    /// Shows `RedditRateLimitNotice` for the whole app.
    func apolloRateLimitNotice() -> some View { modifier(RateLimitNoticeModifier()) }
}
#endif
