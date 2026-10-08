#if canImport(UIKit)
import UIKit
import ObjectiveC

/// Reborn "Hide Bars on Scroll" navigation reveals (#1349): tells the tab bar
/// whenever a tab's navigation stack pushes, pops or is replaced.
///
/// Pushes are driven by SwiftUI bindings, by page swipes and by the tab
/// bar's own swipe, so there is no single call site to put this at; the one
/// place they all meet is the `UINavigationController` the stack runs on.
/// Installed once, from the tab bar.
@MainActor
enum NavigationRevealHooks {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        let cls = UINavigationController.self

        let push = #selector(UINavigationController.pushViewController(_:animated:))
        if let method = class_getInstanceMethod(cls, push) {
            typealias IMPType = @convention(c) (UINavigationController, Selector, UIViewController, Bool) -> Void
            let original = unsafeBitCast(method_getImplementation(method), to: IMPType.self)
            let block: @convention(block) (UINavigationController, UIViewController, Bool) -> Void = { nav, viewController, animated in
                MainActor.assumeIsolated { notify(nav) }
                original(nav, push, viewController, animated)
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }

        let pop = #selector(UINavigationController.popViewController(animated:))
        if let method = class_getInstanceMethod(cls, pop) {
            typealias IMPType = @convention(c) (UINavigationController, Selector, Bool) -> UIViewController?
            let original = unsafeBitCast(method_getImplementation(method), to: IMPType.self)
            let block: @convention(block) (UINavigationController, Bool) -> UIViewController? = { nav, animated in
                MainActor.assumeIsolated { if nav.viewControllers.count > 1 { notify(nav) } }
                return original(nav, pop, animated)
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }

        let popTo = #selector(UINavigationController.popToViewController(_:animated:))
        if let method = class_getInstanceMethod(cls, popTo) {
            typealias IMPType = @convention(c) (UINavigationController, Selector, UIViewController, Bool) -> NSArray?
            let original = unsafeBitCast(method_getImplementation(method), to: IMPType.self)
            let block: @convention(block) (UINavigationController, UIViewController, Bool) -> NSArray? = { nav, target, animated in
                MainActor.assumeIsolated { if nav.topViewController !== target { notify(nav) } }
                return original(nav, popTo, target, animated)
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }

        let popToRoot = #selector(UINavigationController.popToRootViewController(animated:))
        if let method = class_getInstanceMethod(cls, popToRoot) {
            typealias IMPType = @convention(c) (UINavigationController, Selector, Bool) -> NSArray?
            let original = unsafeBitCast(method_getImplementation(method), to: IMPType.self)
            let block: @convention(block) (UINavigationController, Bool) -> NSArray? = { nav, animated in
                MainActor.assumeIsolated { if nav.viewControllers.count > 1 { notify(nav) } }
                return original(nav, popToRoot, animated)
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }

        // SwiftUI may re-apply a stack that has not changed; only a
        // different stack counts as navigation.
        let replace = #selector(UINavigationController.setViewControllers(_:animated:))
        if let method = class_getInstanceMethod(cls, replace) {
            typealias IMPType = @convention(c) (UINavigationController, Selector, NSArray, Bool) -> Void
            let original = unsafeBitCast(method_getImplementation(method), to: IMPType.self)
            let block: @convention(block) (UINavigationController, NSArray, Bool) -> Void = { nav, stack, animated in
                MainActor.assumeIsolated {
                    let next = stack as? [UIViewController] ?? []
                    let current = nav.viewControllers
                    let unchanged = next.count == current.count && zip(next, current).allSatisfy { $0 === $1 }
                    if !unchanged { notify(nav) }
                }
                original(nav, replace, stack, animated)
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }
    }

    /// Only a stack on screen inside the tab bar counts; a sheet's stack or
    /// a tab that is not showing does not.
    private static func notify(_ navigationController: UINavigationController) {
        guard navigationController.viewIfLoaded?.window != nil,
              let tabBarController = navigationController.tabBarController else { return }
        var hiddenByScreen = tabBarController.tabBar.isHidden
        if #available(iOS 18.0, *), tabBarController.isTabBarHidden { hiddenByScreen = true }
        // After the call that is mid-update, so SwiftUI state is not
        // written while it is still diffing; the transition is still starting.
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .apolloNavigationWillChange, object: nil,
                userInfo: [NavigationRevealUserInfo.tabBarHiddenByScreen: hiddenByScreen])
        }
    }
}
#endif
