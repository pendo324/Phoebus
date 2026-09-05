import Foundation
#if canImport(UIKit)
import UIKit
import Metal
#endif

/// Whether the running OS draws Apple's Liquid Glass chrome. Mirrors
/// Reborn's `IsLiquidGlass()`: iOS 26+ and `UIGlassEffect` exists at
/// runtime. The runtime class lookup keeps this honest: `@available` alone
/// would claim glass on an iOS 26 build running without the effect.
public enum LiquidGlass {
    /// Cached. Requires the `UIGlassEffect` class at runtime and that the
    /// app's own linked SDK is new enough (`(sdk >> 16) >= 19`, read from
    /// `LC_BUILD_VERSION`). The SDK check matters: on iOS 26, a build linked
    /// against an older SDK gets UIKit's legacy menu design even though the
    /// class exists.
    public static let isAvailable: Bool = {
        #if canImport(UIKit)
        guard #available(iOS 26.0, *) else { return false }
        guard NSClassFromString("UIGlassEffect") != nil else { return false }
        return linkedSDKEnablesGlass
        #else
        return false
        #endif
    }()

    /// Whether the executable's own linked SDK opts it into the iOS 26 design
    /// system. An app linked against an older SDK keeps the legacy appearance
    /// regardless of OS, so this is not derived from the OS version.
    public static let linkedSDKEnablesGlass: Bool = {
        #if canImport(UIKit)
        guard let sdk = MachOLinkedSDK.iOSSDKVersion() else {
            // Unknown rather than old: refusing glass on an unparseable binary would
            // silently disable it on a capable build.
            return true
        }
        // The first iOS 26 SDK encoded itself as 19.0.
        return sdk.major >= 19
        #else
        return false
        #endif
    }()
}

// MARK: - User preference

public extension LiquidGlass {
    /// Whether glass chrome should actually be drawn right now: the device
    /// can do it and the user has not turned it off.
    ///
    /// Reborn has no such toggle and gates glass on capability alone; this is
    /// a Phoebus addition. `isAvailable` answers "can this device draw glass"
    /// and stays honest so a row's visibility isn't hidden by the preference;
    /// `isEnabled` answers "should we draw it".
    @MainActor
    static var isEnabled: Bool {
        isAvailable && preferenceEnabled
    }

    /// Backing store for the user preference. Read through `UserDefaults`
    /// rather than `GeneralSettings` so PhoebusCore types and appearance
    /// proxies that run before any view exists can ask.
    /// `GeneralSettings.enableLiquidGlass` is the user-facing mirror and writes
    /// through to here.
    @MainActor
    static var preferenceEnabled: Bool {
        get {
            // Defaults to true when unset: a capable device should look like the
            // platform it runs on.
            UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: preferenceKey)
        }
    }

    static let preferenceKey = "PhoebusLiquidGlassEnabled"
}

// MARK: - Can the host actually draw glass?

public extension LiquidGlass {
    /// Whether this host can render Liquid Glass at all. `UIGlassEffect`
    /// existing is not sufficient: `glassEffect` is a GPU effect, and on a host
    /// without working Metal it draws nothing or a smear.
    /// `MTLCreateSystemDefaultDevice()` returning nil is the honest test.
    /// Cached, because creating a Metal device is not free.
    static var canRenderGlass: Bool {
        // An override always wins, so either path can be exercised on any host.
        // See `RenderOverride`.
        switch renderOverride {
        case .forceGlass: return true
        case .forceFallback: return false
        case .automatic: return detectedMetalDevice
        }
    }

    /// The real capability answer, cached.
    static let detectedMetalDevice: Bool = {
        #if canImport(UIKit)
        return MTLCreateSystemDefaultDevice() != nil
        #else
        return false
        #endif
    }()

    /// Forces the glass or fallback path, for testing hosts that only support
    /// one of them. Set from Settings > General > Glass Rendering and stored
    /// in `UserDefaults`. The environment variable is checked first, but it
    /// does not survive being launched through `launchd`, so the UI picker is
    /// the supported control.
    enum RenderOverride: String, Codable, CaseIterable, Sendable {
        /// Ask the hardware (shipping behaviour).
        case automatic
        /// Draw glass even if Metal is missing. Expected to look wrong on a
        /// host that cannot render it.
        case forceGlass = "force-glass"
        /// Never draw glass, even on capable hardware.
        case forceFallback = "force-fallback"
    }

    /// The active override. Environment beats defaults, so a stale stored
    /// value can be overridden.
    static var renderOverride: RenderOverride {
        get { readRenderOverride() }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: overrideKey) }
    }

    private static func readRenderOverride() -> RenderOverride {
        if let raw = ProcessInfo.processInfo.environment[overrideEnvironmentKey],
           let mode = RenderOverride(rawValue: raw) {
            return mode
        }
        if let raw = UserDefaults.standard.string(forKey: overrideKey),
           let mode = RenderOverride(rawValue: raw) {
            return mode
        }
        return .automatic
    }

    static let overrideKey = "PhoebusGlassRenderOverride"
    static let overrideEnvironmentKey = "APOLLO_GLASS_MODE"

    /// Which path the UI is actually taking, for tests to read back. Not
    /// inferred from the override: forcing glass on a Metal-less host still
    /// reports `glass`, since that is what the UI attempts.
    @MainActor
    static var activeRenderPath: String {
        guard isEnabled else { return "disabled" }
        return canRenderGlass ? "glass" : "fallback"
    }
}
