#if canImport(UIKit)
import UIKit

/// Shared lookups into the live UIKit hierarchy under SwiftUI.
@MainActor
enum UIKitTree {
    /// The foreground scene's key window.
    static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }

    /// Every window across connected scenes.
    static var allWindows: [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
    }

    /// The first tab bar controller at or below `root`.
    static func tabBarController(in root: UIViewController?) -> UITabBarController? {
        guard let root else { return nil }
        if let tabs = root as? UITabBarController { return tabs }
        for child in root.children {
            if let tabs = tabBarController(in: child) { return tabs }
        }
        return root.presentedViewController.flatMap { tabBarController(in: $0) }
    }

    /// Scroll views at or under `root`, in pre-order (parent before
    /// children, subviews in array order).
    static func scrollViews(in root: UIView) -> [UIScrollView] {
        var found: [UIScrollView] = []
        func walk(_ view: UIView) {
            if let scroll = view as? UIScrollView { found.append(scroll) }
            view.subviews.forEach(walk)
        }
        walk(root)
        return found
    }

    /// The first descendant of `root` of type `T`, breadth first.
    static func firstDescendant<T: UIView>(of type: T.Type, in root: UIView,
                                           where predicate: (T) -> Bool = { _ in true }) -> T? {
        var queue: [UIView] = [root]
        var index = 0
        while index < queue.count {
            let view = queue[index]; index += 1
            if let match = view as? T, predicate(match) { return match }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }
}

extension UIView {
    /// Nearest owning view controller, via the responder chain.
    func owningViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }
}
#endif
