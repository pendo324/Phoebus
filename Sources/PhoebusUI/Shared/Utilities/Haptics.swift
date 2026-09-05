import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit
#endif

/// Centralized haptic feedback, following Apollo's `HapticFeedback` setting
/// (on by default): votes, saves and other quick actions.
/// `#if canImport(UIKit)`-gated since haptics are iOS-only.
public enum Haptics {
    @MainActor
    public static func light() {
        #if canImport(UIKit)
        guard GeneralSettingsStore.load().hapticFeedbackEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    @MainActor
    public static func medium() {
        #if canImport(UIKit)
        guard GeneralSettingsStore.load().hapticFeedbackEnabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }

    @MainActor
    public static func selection() {
        #if canImport(UIKit)
        guard GeneralSettingsStore.load().hapticFeedbackEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}
