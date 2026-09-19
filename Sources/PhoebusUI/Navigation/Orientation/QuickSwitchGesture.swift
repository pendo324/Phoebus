import SwiftUI
import PhoebusCore

/// Apollo's "Enable Quick Switch" gesture (`ThemeToggleGestureEnabled`):
/// long-press the top navigation bar to quickly toggle themes.
///
/// A long press recognised on the window, for touches that land in a
/// navigation bar. It sits beside the bar's own controls instead of over
/// them: a tap on Back or a toolbar button never reaches it, and it only
/// takes the touch once the press has lasted 0.6 s. A screen-wide press
/// would also fire from every row's context menu.
public struct QuickSwitchGestureModifier: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        #if canImport(UIKit)
        content.background(QuickSwitchInstaller().allowsHitTesting(false))
        #else
        content
        #endif
    }
}

#if canImport(UIKit)
private struct QuickSwitchInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> InstallerView { InstallerView() }
    func updateUIView(_ view: InstallerView, context: Context) {}

    final class InstallerView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window else { return }
            NavigationBarLongPress.install(on: window)
        }
    }
}

@MainActor
private final class NavigationBarLongPress: NSObject, UIGestureRecognizerDelegate {
    private static let shared = NavigationBarLongPress()
    private static var installed: Set<ObjectIdentifier> = []

    static func install(on window: UIWindow) {
        guard installed.insert(ObjectIdentifier(window)).inserted else { return }
        let press = UILongPressGestureRecognizer(target: shared, action: #selector(pressed(_:)))
        press.minimumPressDuration = 0.6
        press.cancelsTouchesInView = true
        press.delegate = shared
        window.addGestureRecognizer(press)
    }

    @objc private func pressed(_ press: UILongPressGestureRecognizer) {
        guard press.state == .began else { return }
        QuickSwitchGesture.toggleTheme()
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard ThemeAutoSwitchSettingsStore.load().quickSwitchEnabled else { return false }
        var view = touch.view
        while let current = view {
            if current is UINavigationBar { return true }
            view = current.superview
        }
        return false
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
#endif

public enum QuickSwitchGesture {
    /// Flips the active theme between its light and dark variant.
    ///
    /// Reuses the auto-switch resolver's counterpart logic, so a gallery theme
    /// derives its opposite mode rather than failing to find one.
    @MainActor
    public static func toggleTheme() {
        let current = ThemeStore.load()
        guard let next = ThemeAutoSwitchResolver.counterpart(
            for: current,
            wantsDark: !current.isDark,
            in: ThemeStore.allAvailableThemes()
        ) else { return }
        // Holds against the automatic rule until that rule's answer next
        // changes, so it doesn't flip straight back.
        ThemeAutoSwitch.overrideCurrentRule()
        ThemeStore.save(next)
        Haptics.selection()
    }
}

/// Runs the automatic light/dark rules (system, brightness, schedule).
@MainActor
public enum ThemeAutoSwitch {
    /// The rule's answer when the theme was switched by hand.
    private static var overriddenAnswer: Bool?

    public static func desiredDark() -> Bool? {
        #if canImport(UIKit)
        // The screen's style is the system's; the window's is the app's
        // own forced light/dark.
        let systemIsDark = UIScreen.main.traitCollection.userInterfaceStyle == .dark
        let brightness = Double(UIScreen.main.brightness)
        #else
        let systemIsDark = false
        let brightness = 1.0
        #endif
        return ThemeAutoSwitchResolver.shouldUseDarkTheme(
            settings: ThemeAutoSwitchSettingsStore.load(),
            systemIsDark: systemIsDark,
            screenBrightness: brightness)
    }

    static func overrideCurrentRule() {
        overriddenAnswer = desiredDark()
    }

    public static func clearOverride() {
        overriddenAnswer = nil
    }

    /// Preserves the user's theme family (light/dark pairs sharing a
    /// name) rather than dropping onto a stock default.
    public static func applyIfNeeded() {
        guard let wantsDark = desiredDark() else { return }
        if let overriddenAnswer {
            guard overriddenAnswer != wantsDark else { return }
            self.overriddenAnswer = nil
        }
        let current = ThemeStore.load()
        guard current.isDark != wantsDark,
              let next = ThemeAutoSwitchResolver.counterpart(
                for: current, wantsDark: wantsDark, in: ThemeStore.allAvailableThemes())
        else { return }
        ThemeStore.save(next)
    }
}

public extension View {
    /// Real "Enable Quick Switch" long-press.
    func apolloQuickSwitchGesture() -> some View {
        modifier(QuickSwitchGestureModifier())
    }
}
