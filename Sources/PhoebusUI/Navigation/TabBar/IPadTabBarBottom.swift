import Foundation
import PhoebusCore
#if canImport(UIKit)
import UIKit
import ObjectiveC

/// Reborn's "Move Tab Bar to Bottom" on iPad (#387).
///
/// On iPadOS 26 the tab bar is a floating glass pill at the top centre,
/// over the Subreddits search field, and UIKit has no public switch for
/// its placement. Reborn's lever is the private
/// `-[_UITabContainerView canShowFloatingUI]`: returning NO makes the
/// adaptive style fall back to the classic bottom-docked `UITabBar`,
/// and UIKit's docked layout recomputes the content insets.
///
/// Gates: iPad only (dormant on iPhone), Liquid Glass tab bar on, and
/// the opt-in toggle (`GeneralSettings.ipadTabBarBottom`, key
/// `IPadTabBarBottom`, default off). The toggle is read live and
/// `refresh()` re-queries the bar, so flipping it needs no relaunch.
@MainActor
public enum IPadTabBarBottom {
    private static var installed = false

    static var isActive: Bool {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return false }
        let settings = GeneralSettingsStore.load()
        return settings.enableLiquidGlassTabBar && settings.ipadTabBarBottom
    }

    public static func install() {
        guard !installed, UIDevice.current.userInterfaceIdiom == .pad,
              let cls = NSClassFromString("_UITabContainerView") else { return }
        let selector = NSSelectorFromString("canShowFloatingUI")
        guard let method = class_getInstanceMethod(cls, selector) else { return }
        installed = true
        typealias Original = @convention(c) (AnyObject, Selector) -> Bool
        let original = unsafeBitCast(method_getImplementation(method), to: Original.self)
        let block: @convention(block) (AnyObject) -> Bool = { view in
            MainActor.assumeIsolated { isActive } ? false : original(view, selector)
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    /// Re-lays-out every tab bar controller so the placement is
    /// re-queried.
    public static func refresh() {
        install()
        for scene in UIApplication.shared.connectedScenes {
            for window in (scene as? UIWindowScene)?.windows ?? [] {
                var stack: [UIViewController] = window.rootViewController.map { [$0] } ?? []
                while let vc = stack.popLast() {
                    if vc is UITabBarController {
                        vc.view.setNeedsLayout()
                        vc.view.layoutIfNeeded()
                    }
                    stack.append(contentsOf: vc.children)
                }
                window.setNeedsLayout()
                window.layoutIfNeeded()
            }
        }
    }
}
#endif
