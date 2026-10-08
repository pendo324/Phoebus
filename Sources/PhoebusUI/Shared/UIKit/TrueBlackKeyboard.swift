import Foundation
import PhoebusCore
#if canImport(UIKit)
import UIKit
import ObjectiveC
import os

/// Reborn "True Black Keyboard" (#1316, `TrueBlackKeyboardMode`): paints the
/// system keyboard's backdrop pure black for OLED screens.
///
/// The keyboard is drawn in-process by UIKitCore, so it can be restyled from
/// here. This uses private UIKit classes: `UIKBBackdropView` loses its blur
/// and gets a black fill, and under a light-mode app
/// `+[UIKBRenderConfig configForAppearance:inputMode:traitEnvironment:]` is
/// asked for the dark key set so keycaps and glyphs stay readable. Every
/// class and selector is looked up by name; one that is missing (a UIKit
/// rename) skips that hook and the keyboard just looks stock.
///
/// The mode is read live, so a change applies the next time the keyboard
/// lays out.
@MainActor
public enum TrueBlackKeyboard {
    private static var installed = false
    private nonisolated static let mode = OSAllocatedUnfairLock(initialState: TrueBlackKeyboardMode.off)

    private nonisolated static let renderConfigSelector =
        NSSelectorFromString("configForAppearance:inputMode:traitEnvironment:")

    /// UIKit added the trait-environment variant in iOS 15; without it a light
    /// app cannot get the dark key set, so the keyboard stays stock.
    private nonisolated static let darkKeysAvailable: Bool = {
        guard let config = NSClassFromString("UIKBRenderConfig") else { return false }
        return class_getClassMethod(config, renderConfigSelector) != nil
    }()

    private nonisolated static let darkKeyboardAppearance = UIKeyboardAppearance.dark.rawValue

    /// Installs once at launch; the hooks stay inert while the mode is Off.
    public static func install() {
        guard !installed else { return }
        installed = true
        mode.withLock { $0 = GeneralSettingsStore.load().trueBlackKeyboardMode }
        NotificationCenter.default.addObserver(forName: .apolloSettingsChanged, object: nil, queue: nil) { _ in
            let updated = GeneralSettingsStore.load().trueBlackKeyboardMode
            mode.withLock { $0 = updated }
        }
        installRenderConfigHook()
        installBackdropHooks()
    }

    // MARK: - Hooks

    private static func installRenderConfigHook() {
        guard let config = NSClassFromString("UIKBRenderConfig"), let meta = object_getClass(config),
              let method = class_getClassMethod(config, renderConfigSelector) else { return }
        let selector = renderConfigSelector
        typealias Original = @convention(c) (AnyObject, Selector, Int, AnyObject?, AnyObject?) -> AnyObject?
        let original = unsafeBitCast(method_getImplementation(method), to: Original.self)
        let block: @convention(block) (AnyObject, Int, AnyObject?, AnyObject?) -> AnyObject? = { cls, appearance, inputMode, traits in
            if appearance != darkKeyboardAppearance, Thread.isMainThread,
               MainActor.assumeIsolated({ usesDarkKeys() }) {
                return original(cls, selector, darkKeyboardAppearance, inputMode, traits)
            }
            return original(cls, selector, appearance, inputMode, traits)
        }
        replace(meta, selector, method, block)
    }

    private static func installBackdropHooks() {
        guard let backdrop = NSClassFromString("UIKBBackdropView"),
              backdrop is UIVisualEffectView.Type else { return }

        typealias Plain = @convention(c) (AnyObject, Selector) -> Void
        for selector in [#selector(UIView.didMoveToWindow), #selector(UIView.layoutSubviews)] {
            guard let method = class_getInstanceMethod(backdrop, selector) else { continue }
            let original = unsafeBitCast(method_getImplementation(method), to: Plain.self)
            let block: @convention(block) (AnyObject) -> Void = { view in
                original(view, selector)
                restyle(view)
            }
            replace(backdrop, selector, method, block)
        }

        let renderConfig = NSSelectorFromString("_setRenderConfig:")
        if let method = class_getInstanceMethod(backdrop, renderConfig) {
            typealias SetConfig = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
            let original = unsafeBitCast(method_getImplementation(method), to: SetConfig.self)
            let block: @convention(block) (AnyObject, AnyObject?) -> Void = { view, config in
                original(view, renderConfig, config)
                restyle(view)
            }
            replace(backdrop, renderConfig, method, block)
        }
    }

    /// Added on the class itself when it only inherits the method, so the
    /// superclass's other subclasses are untouched.
    private static func replace(_ owner: AnyClass, _ selector: Selector, _ method: Method, _ block: Any) {
        let imp = imp_implementationWithBlock(block)
        if !class_addMethod(owner, selector, imp, method_getTypeEncoding(method)) {
            method_setImplementation(method, imp)
        }
    }

    private nonisolated static func restyle(_ view: AnyObject) {
        guard Thread.isMainThread, let backdrop = view as? UIVisualEffectView else { return }
        MainActor.assumeIsolated { apply(to: backdrop) }
    }

    // MARK: - Decision

    /// The app's appearance (Apollo may override it per window), from its
    /// first normal-level window.
    private static var appInterfaceStyle: UIUserInterfaceStyle {
        UIKitTree.allWindows.first { $0.windowLevel == .normal }?.traitCollection.userInterfaceStyle ?? .unspecified
    }

    private static func paintsBlack() -> Bool {
        let current = mode.withLock { $0 }
        guard current != .off else { return false }
        return current.paintsBlack(isDark: appInterfaceStyle == .dark, darkKeysAvailable: darkKeysAvailable)
    }

    private static func usesDarkKeys() -> Bool {
        let current = mode.withLock { $0 }
        guard current != .off else { return false }
        return current.usesDarkKeys(isDark: appInterfaceStyle == .dark, darkKeysAvailable: darkKeysAvailable)
    }

    // MARK: - Backdrop styling

    private static var edgeFillKey: UInt8 = 0
    private static var stockLookKey: UInt8 = 0
    /// Uncovered height at the top, keeping the top corners rounded.
    private static let topCornerClearance: CGFloat = 44

    /// What UIKit had set before the backdrop was painted, to put back if the
    /// mode stops applying while the keyboard is still up.
    private final class StockLook {
        var background: UIColor?
        var content: UIColor?
        let hidden = NSHashTable<UIView>.weakObjects()
        init(content: UIColor?) { self.content = content }
    }

    private static func apply(to backdrop: UIVisualEffectView) {
        if belongsToKey(backdrop) { return }
        let applies = paintsBlack()
        updateEdgeFill(backdrop, show: applies)
        guard applies else {
            revert(backdrop)
            return
        }
        let stock: StockLook
        if let existing = objc_getAssociatedObject(backdrop, &stockLookKey) as? StockLook {
            stock = existing
        } else {
            stock = StockLook(content: backdrop.contentView.backgroundColor)
            objc_setAssociatedObject(backdrop, &stockLookKey, stock, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        // UIKit re-sets the tint on each render-config change; keep its latest before covering it.
        if !isOpaqueBlack(backdrop.backgroundColor) { stock.background = backdrop.backgroundColor }
        if backdrop.effect != nil {
            // Outside any running animation: a light/dark flip animates the backdrop's
            // effects, and UIKit throws if `effect` was animated next to it.
            UIView.performWithoutAnimation { backdrop.effect = nil }
        }
        backdrop.backgroundColor = .black
        backdrop.contentView.backgroundColor = .black
        // Any private glass/blur layer view UIKit adds beside the content view.
        for sub in backdrop.subviews where sub !== backdrop.contentView && !sub.isHidden {
            sub.isHidden = true
            stock.hidden.add(sub)
        }
    }

    /// Puts UIKit's look back when the mode stops applying to a backdrop that
    /// is still up (Dark Mode Only and the app flips to light while typing).
    /// UIKit re-sets the effect and tint for the new config, but not the
    /// content fill or the views hidden below.
    private static func revert(_ backdrop: UIVisualEffectView) {
        guard let stock = objc_getAssociatedObject(backdrop, &stockLookKey) as? StockLook else { return }
        objc_setAssociatedObject(backdrop, &stockLookKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        if isOpaqueBlack(backdrop.backgroundColor) { backdrop.backgroundColor = stock.background }
        backdrop.contentView.backgroundColor = stock.content
        for sub in stock.hidden.allObjects { sub.isHidden = false }
    }

    private static func isOpaqueBlack(_ color: UIColor?) -> Bool {
        var red: CGFloat = 1, green: CGFloat = 1, blue: CGFloat = 1, alpha: CGFloat = 0
        guard let color, color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return false }
        return red == 0 && green == 0 && blue == 0 && alpha == 1
    }

    /// Pressed keys and the variant picker draw their own glass with a
    /// `UIKBBackdropView` (inside a key view or `TUIVariantSelectorView`).
    /// Painting those black leaves a black cover under the pressed key, so
    /// only the keyboard's own background backdrops are touched.
    private static func belongsToKey(_ backdrop: UIView) -> Bool {
        if let effectView = NSClassFromString("UIKBVisualEffectView"), backdrop.isKind(of: effectView) { return true }
        let keyView = NSClassFromString("UIKBKeyView")
        let variantSelector = NSClassFromString("TUIVariantSelectorView")
        var view = backdrop.superview
        while let current = view {
            if let keyView, current.isKind(of: keyView) { return true }
            if let variantSelector, current.isKind(of: variantSelector) { return true }
            view = current.superview
        }
        return false
    }

    /// The backdrop's edges are a hair tighter than the screen's, so slivers of
    /// the app can show at the sides and bottom corners. A black strip behind
    /// it, a few points wider (the screen clips the excess), fills that; it
    /// starts below the top corners so they stay round. Constraints rather than
    /// frame writes, so it cannot loop during layout.
    private static func updateEdgeFill(_ backdrop: UIVisualEffectView, show: Bool) {
        var fill = objc_getAssociatedObject(backdrop, &edgeFillKey) as? UIView
        guard show else {
            fill?.isHidden = true
            return
        }
        guard let host = backdrop.superview else { return }
        if fill == nil || fill?.superview !== host {
            fill?.removeFromSuperview()
            let strip = UIView()
            strip.backgroundColor = .black
            strip.isUserInteractionEnabled = false
            strip.translatesAutoresizingMaskIntoConstraints = false
            host.insertSubview(strip, belowSubview: backdrop)
            NSLayoutConstraint.activate([
                strip.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor, constant: -4),
                strip.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor, constant: 4),
                strip.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor, constant: 4),
                strip.topAnchor.constraint(equalTo: backdrop.topAnchor, constant: topCornerClearance),
            ])
            objc_setAssociatedObject(backdrop, &edgeFillKey, strip, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            fill = strip
        }
        fill?.isHidden = false
    }
}
#endif
