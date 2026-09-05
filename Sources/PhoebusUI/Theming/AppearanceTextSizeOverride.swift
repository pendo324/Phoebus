import SwiftUI
import PhoebusCore

/// Applies Apollo's Appearance "Use System Text Size"/"Text Size" setting
/// (`AppearanceSettings.useSystemTextSize`/`.textSizeScale`, keys
/// `SystemTextSwitchTag`/`shownTextSize`) app-wide.
///
/// A conditional modifier rather than an always-applied `.dynamicTypeSize(_:)`:
/// that call overrides the environment unconditionally and has no pass-through
/// value, so applying it while "Use System Text Size" is on would pin every user
/// to one size and defeat the OS Dynamic Type setting. It is attached only
/// while the setting is off.
public struct AppearanceTextSizeOverride: ViewModifier {
    /// Held in `@State` and refreshed on change, not read once from a default
    /// argument, so the slider takes effect live without a relaunch.
    @State private var settings: AppearanceSettings

    init(settings: AppearanceSettings) {
        _settings = State(initialValue: settings)
    }

    @ViewBuilder
    public func body(content: Content) -> some View {
        Group {
            if settings.useSystemTextSize {
                content
            } else {
                content.dynamicTypeSize(Self.dynamicTypeSize(forScale: settings.textSizeScale))
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: AppearanceSettingsStore.didChangeNotification)) { _ in
            settings = AppearanceSettingsStore.load()
        }
    }

    /// `DynamicTypeSize` has no continuous scale API, so `textSizeScale` (slider
    /// range 0.8...1.4, default 1.0) picks the closest of its 12 discrete cases
    /// via `AppearanceTextSizeStep`'s step math. `.large` is both the system
    /// default case and this scale's pivot.
    static func dynamicTypeSize(forScale scale: Double) -> DynamicTypeSize {
        let allSizes = DynamicTypeSize.allCases.sorted { $0 < $1 }
        guard let largeIndex = allSizes.firstIndex(of: .large) else { return .large }
        let targetIndex = max(0, min(allSizes.count - 1, largeIndex + AppearanceTextSizeStep.steps(forScale: scale)))
        return allSizes[targetIndex]
    }
}

extension View {
    /// Applies the "Use System Text Size"/"Text Size" override; see `AppearanceTextSizeOverride`.
    public func apolloTextSizeOverride(_ settings: AppearanceSettings = AppearanceSettingsStore.load()) -> some View {
        modifier(AppearanceTextSizeOverride(settings: settings))
    }
}
