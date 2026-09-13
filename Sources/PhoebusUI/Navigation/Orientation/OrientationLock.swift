import SwiftUI
import AVFoundation
import PhoebusCore
#if canImport(UIKit)
import UIKit

/// Orientation-lock enforcement for Apollo's "Portrait Lock" and
/// "Smart Rotation Lock" settings, via
/// `UIApplicationDelegate.application(_:supportedInterfaceOrientationsFor:)`
/// since SwiftUI's `App` has no orientation hook.
///
/// Composes as Apollo's own footer text describes: Smart Rotation Lock
/// suspends Portrait Lock while viewing rotatable media, then restores
/// it afterward. This locks only the app, independent of the device's
/// own rotation lock.
public enum OrientationLock {
    /// Set while a rotatable media viewer (fullscreen image/video) is
    /// presented; Smart Rotation Lock consults this. Static because
    /// UIKit asks the app delegate for supported orientations from
    /// outside any SwiftUI view's scope.
    @MainActor public static var isViewingRotatableMedia = false {
        didSet {
            guard oldValue != isViewingRotatableMedia else { return }
            requestGeometryUpdate()
        }
    }

    /// Set while Gallery View (grid or fullscreen viewer) is on screen.
    /// Unconditional, unlike `isViewingRotatableMedia`: Gallery View
    /// widens the supported mask to `AllButUpsideDown` regardless of
    /// the Portrait Lock or Smart Rotation Lock settings.
    @MainActor public static var isViewingGallery = false {
        didSet {
            guard oldValue != isViewingGallery else { return }
            requestGeometryUpdate()
        }
    }

    /// The orientations the app currently permits.
    @MainActor public static var supportedOrientations: UIInterfaceOrientationMask {
        if isViewingGallery { return .allButUpsideDown }
        guard PortraitLockStore.load().isEnabled else { return .all }
        // Smart Rotation Lock: "Locks Apollo to portrait … except for
        // Media Viewer."
        return isViewingRotatableMedia ? .all : .portrait
    }

    /// Asks UIKit to re-evaluate immediately, so entering or leaving a
    /// media viewer takes effect at once instead of on the next
    /// physical rotation.
    @MainActor public static func requestGeometryUpdate() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: supportedOrientations))
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

/// Minimal app delegate whose only job is answering UIKit's
/// orientation query. Installed via `@UIApplicationDelegateAdaptor`.
public final class ApolloAppDelegate: NSObject, UIApplicationDelegate {
    public func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { OrientationLock.supportedOrientations }
    }

    /// Home-screen quick actions. Items are registered dynamically; a
    /// cold launch from one arrives through the scene's connection
    /// options, a warm one through `windowScene(_:performActionFor:)`.
    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Muted videos mix with other apps' audio from the first one on.
        VideoAudioSession.configureAmbient()
        VideoAudioSession.pausePlaying = {
            MainActor.assumeIsolated {
                var players = VideoPlayerCache.shared.playingPlayers()
                if let card = FloatingPiPController.shared.player, card.rate != 0,
                   !players.contains(where: { $0 === card }) {
                    players.append(card)
                }
                // Paused first, as Apollo does: otherwise the system stops them after the
                // switch returns, past the restart below, and they stay paused.
                let paused = PausedPlayers(players.map { ($0, $0.rate) })
                players.forEach { $0.pause() }
                return {
                    MainActor.assumeIsolated {
                        for (player, rate) in paused.players where player.rate == 0 {
                            player.rate = rate
                        }
                    }
                }
            }
        }
        MainActor.assumeIsolated {
            application.shortcutItems = QuickAction.allCases.map {
                UIApplicationShortcutItem(
                    type: QuickAction.typePrefix + $0.rawValue,
                    localizedTitle: $0.title,
                    localizedSubtitle: nil,
                    icon: UIApplicationShortcutIcon(systemImageName: $0.systemImage))
            }
        }
        return true
    }

    public func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let item = options.shortcutItem, let action = QuickAction.parse(shortcutType: item.type) {
            MainActor.assumeIsolated { QuickActionRouter.shared.pending = action }
        }
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = ApolloSceneDelegate.self
        return config
    }
}

/// Only here for warm-launch quick actions; SwiftUI still owns the window.
public final class ApolloSceneDelegate: NSObject, UIWindowSceneDelegate {
    public func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard let action = QuickAction.parse(shortcutType: shortcutItem.type) else {
            completionHandler(false); return
        }
        MainActor.assumeIsolated { QuickActionRouter.shared.pending = action }
        completionHandler(true)
    }
}

public extension View {
    /// Marks a fullscreen media viewer as rotatable, so Smart Rotation
    /// Lock suspends Portrait Lock for as long as it is on screen and
    /// restores it on dismissal.
    func allowsRotationWhileViewingMedia() -> some View {
        onAppear { OrientationLock.isViewingRotatableMedia = true }
            .onDisappear { OrientationLock.isViewingRotatableMedia = false }
    }

    /// Marks Gallery View's grid or fullscreen viewer as on screen; see
    /// `OrientationLock.isViewingGallery` for why this is unconditional.
    func galleryOrientationOverride() -> some View {
        onAppear { OrientationLock.isViewingGallery = true }
            .onDisappear { OrientationLock.isViewingGallery = false }
    }
}
#else
public extension View {
    func allowsRotationWhileViewingMedia() -> some View { self }
    func galleryOrientationOverride() -> some View { self }
}
#endif

/// Players paused around an audio session switch, handed back to the
/// main thread to resume.
private final class PausedPlayers: @unchecked Sendable {
    let players: [(AVPlayer, Float)]
    init(_ players: [(AVPlayer, Float)]) { self.players = players }
}
