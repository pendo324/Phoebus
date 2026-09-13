import SwiftUI
import PhoebusCore

/// The lock screen for the Security setting ("Require Face ID").
///
/// Wraps the whole app: while locked, content is both covered and
/// redacted so it cannot be read behind the overlay. Re-locks when the
/// app leaves the foreground.
public struct AppLockGate<Content: View>: View {
    @Setting(AppLockSettings.self) private var appLockSettings
    private let content: Content

    /// Starts locked whenever the setting is on, so the very first
    /// frame after launch is never readable.
    @State private var isUnlocked = !AppLockStore.load().isEnabled
    @State private var isAuthenticating = false
    @State private var didFail = false
    @Environment(\.scenePhase) private var scenePhase
    /// When the app last went to the background, for the "Require
    /// Passcode: After N Minutes" grace period.
    @State private var backgroundedAt: Date?

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var lockEnabled: Bool { appLockSettings.isEnabled }

    public var body: some View {
        // `.overlay`, not a `ZStack` wrapper: this gate wraps the whole app,
        // and a `ZStack` at the scene root stops SwiftUI bridging a root
        // `TabView` to a real `UITabBarController`.
        content
            // An opaque cover alone can still be captured in the app-switcher
            // snapshot before the overlay draws.
            .redacted(reason: isUnlocked ? [] : .privacy)
            .disabled(!isUnlocked)
            .overlay {
                if !isUnlocked {
                    lockScreen
                        .transition(.opacity)
                }
            }
        .task {
            if !isUnlocked { await attemptUnlock() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                // Re-arm on backgrounding. Content is covered and redacted at once
                // (so the app-switcher snapshot never shows it); whether returning
                // needs authenticating is decided on return.
                if lockEnabled, isUnlocked {
                    backgroundedAt = Date()
                    isUnlocked = false
                }
            case .active:
                if lockEnabled, !isUnlocked, !isAuthenticating {
                    let away = backgroundedAt.map { Date().timeIntervalSince($0) } ?? .infinity
                    if !appLockSettings.requiresUnlock(afterBeingAwayFor: away) {
                        isUnlocked = true
                    } else {
                        Task { await attemptUnlock() }
                    }
                }
            default:
                break
            }
        }
    }

    private var lockScreen: some View {
        ZStack {
            // Opaque, not a material: a blur would still leak content.
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: lockSymbol)
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Phoebus is Locked")
                    .font(.headline)
                if didFail {
                    Text("Authentication failed.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button("Unlock") {
                    Task { await attemptUnlock() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAuthenticating)
                .accessibilityIdentifier("appLock.unlock")
            }
        }
        .accessibilityIdentifier("appLock.screen")
    }

    private var lockSymbol: String {
        switch AppLockStore.biometry {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .none: return "lock.fill"
        }
    }

    private func attemptUnlock() async {
        guard lockEnabled, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let success = await AppLockStore.authenticate()
        didFail = !success
        if success {
            withAnimation { isUnlocked = true }
        }
    }
}
