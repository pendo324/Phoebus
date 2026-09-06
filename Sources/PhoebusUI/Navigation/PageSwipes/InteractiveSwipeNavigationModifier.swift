import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit

extension UINavigationController {
    /// Turns off every pop gesture UIKit installs, so the only back swipe is
    /// Apollo's (`PageSwipeController`).
    ///
    /// iOS 26 adds `interactiveContentPopGestureRecognizer`, which recognizes
    /// across the whole content area and contests rightward row swipes, so it is
    /// disabled along with the classic edge recognizer.
    func apolloDisableSystemPopGestures() {
        interactivePopGestureRecognizer?.isEnabled = false
        if #available(iOS 26.0, *) {
            interactiveContentPopGestureRecognizer?.isEnabled = false
        }
    }
}

public extension View {
    /// Apollo's page swipes on a root tab stack, honouring "Ability to
    /// swipe forward/back pages"
    /// (`NavigationGestureSettings.pushPopSwipeGesturesEnabled`).
    func apolloInteractiveSwipeNavigation() -> some View {
        background(
            PageSwipeInstaller()
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
    }
}
#else
public extension View {
    func apolloInteractiveSwipeNavigation() -> some View { self }
}
#endif
