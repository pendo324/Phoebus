import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Reborn's Inline Media settings sub-screen: alignment and size controls
/// for inline media previews in post/comment bodies. Separate from
/// `GeneralSettings`, as Reborn groups them on their own screen.
public enum InlineMediaAlignment: String, Codable, Sendable, CaseIterable, Identifiable {
    case left
    case center
    case right

    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }
}


/// Reborn's four autoplay modes for inline GIFs: Always, WiFi Only, Tap to
/// Play, Never. WiFi Only keeps GIFs off cellular data.
public enum InlineGIFAutoplayMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case always, wifiOnly, tapToPlay, never

    /// Reborn's legacy "Default" mode, resolved once to the explicit equivalent
    /// of the app-wide Autoplay GIFs/Videos setting.
    public static func following(_ autoplay: AutoplayMode) -> InlineGIFAutoplayMode {
        switch autoplay {
        case .always: return .always
        case .wifiOnly: return .wifiOnly
        case .never: return .never
        }
    }

    public var id: String { rawValue }

    /// Titles as Reborn words them.
    public var displayName: String {
        switch self {
        case .always: return "Always"
        case .wifiOnly: return "WiFi Only"
        case .tapToPlay: return "Tap to Play"
        case .never: return "Never"
        }
    }

    /// Reborn's sheet order.
    public static var realOrder: [InlineGIFAutoplayMode] {
        [.always, .wifiOnly, .tapToPlay, .never]
    }

    /// Whether a GIF should sit behind a play button rather than autoplaying.
    public var requiresTapToPlay: Bool {
        self == .tapToPlay || self == .never
    }

    /// Tap to Play and Never hold the GIF; WiFi Only plays off cellular.
    public func autoplays(isUnmetered: Bool) -> Bool {
        switch self {
        case .always: return true
        case .wifiOnly: return isUnmetered
        case .tapToPlay, .never: return false
        }
    }

    /// The corner play/pause badge is for Tap to Play, and for WiFi Only while
    /// it is held on cellular. Never is a pure still whose tap opens the viewer.
    public func showsPlayBadge(isUnmetered: Bool) -> Bool {
        switch self {
        case .tapToPlay: return true
        case .wifiOnly: return !isUnmetered
        case .always, .never: return false
        }
    }
}

/// Reborn's inline media box: how wide and how tall a piece of comment
/// media is drawn inside a row.
public struct InlineMediaFrame: Equatable, Sendable {
    public var width: CGFloat
    public var height: CGFloat
    /// The media is aspect-fit inside a box of a different shape, which
    /// Reborn outlines with a hairline.
    public var isLetterboxed: Bool

    /// Tallest box: a square.
    public static let maxRatio: CGFloat = 1.0
    /// Shortest box: about 5.5:1.
    public static let minRatio: CGFloat = 0.18
    /// Narrowest width a tall image shrinks to.
    public static let minTallWidth: CGFloat = 85
    /// Height cap as a share of the screen height (binds in landscape).
    public static let maxScreenHeightFraction: CGFloat = 0.6
    /// Rounded corners of the media.
    public static let cornerRadius: CGFloat = 8
    /// Space above and below the media.
    public static let verticalInset: CGFloat = 4

    /// Height / width from a URL's own `width`/`height` (or `w`/`h`)
    /// query, as Reddit's preview links carry, so the box is right before
    /// the image loads. `nil` when the URL doesn't say.
    public static func ratio(fromQueryOf url: URL) -> CGFloat? {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        var width: Double?, height: Double?
        for item in items {
            switch item.name.lowercased() {
            case "width", "w": width = item.value.flatMap(Double.init)
            case "height", "h": height = item.value.flatMap(Double.init)
            default: break
            }
        }
        guard let width, let height, width > 0, height > 0 else { return nil }
        return CGFloat(height / width)
    }

    /// `ratio` is height / width of the media itself.
    public static func fit(ratio naturalRatio: CGFloat, rowWidth: CGFloat, screenHeight: CGFloat,
                           size: InlineMediaSize, isVideo: Bool = false) -> InlineMediaFrame {
        let ratio = naturalRatio > 0 ? naturalRatio : 1
        let fraction = size.fraction
        var width = rowWidth
        var boxRatio = ratio
        var letterboxed = false
        if isVideo && ratio > 1 {
            // A portrait video keeps a full-row player card, up to 3:2.
            let sizedWidth = fraction < 1 ? rowWidth * fraction : rowWidth
            let viewportCap = screenHeight * maxScreenHeightFraction / max(sizedWidth, 1)
            boxRatio = min(ratio, min(1.5, max(1, viewportCap)))
            letterboxed = true
        } else if ratio > maxRatio {
            let maxHeight = min(rowWidth * maxRatio, screenHeight * maxScreenHeightFraction)
            let tightWidth = maxHeight / ratio
            if tightWidth >= minTallWidth {
                width = tightWidth
            } else {
                width = minTallWidth
                boxRatio = maxHeight / minTallWidth
                letterboxed = true
            }
        } else if ratio < minRatio {
            boxRatio = minRatio
            letterboxed = true
        } else {
            let heightCap = screenHeight * maxScreenHeightFraction
            if rowWidth * ratio > heightCap {
                width = heightCap / ratio
            }
        }
        if fraction < 1 {
            width = min(width, rowWidth * fraction)
        }
        return InlineMediaFrame(width: width, height: width * boxRatio, isLetterboxed: letterboxed)
    }
}

/// The three size detents (50/75/100% of the available row width) of
/// Reborn's slider, presented here as a plain picker.
public enum InlineMediaSize: Int, Codable, Sendable, CaseIterable, Identifiable {
    case small = 50
    case medium = 75
    case large = 100

    public var id: Int { rawValue }
    public var displayName: String { "\(rawValue)%" }

    /// Snaps a raw slider value to the nearest detent: the slider is
    /// continuous but only ever commits 50, 75 or 100.
    public static func snapped(to value: Double) -> InlineMediaSize {
        allCases.min { abs(Double($0.rawValue) - value) < abs(Double($1.rawValue) - value) } ?? .large
    }
    public var fraction: CGFloat { CGFloat(rawValue) / 100.0 }
}

public struct InlineMediaSettings: Codable, Sendable, Equatable {
    /// Master toggle: when false, embedded media URLs render as plain links
    /// like any other body link.
    public var enabled: Bool
    public var alignment: InlineMediaAlignment
    public var size: InlineMediaSize
    /// Reborn "Tap to Play" for inline GIFs: when true, an inline GIF shows a
    /// static poster/play overlay until tapped instead of autoplaying.
    public var autoplayMode: InlineGIFAutoplayMode

    /// Accessor for call sites that only ask "should this GIF wait for a tap?".
    public var tapToPlayGIFs: Bool { autoplayMode.requiresTapToPlay }
    /// Reborn "Inline Media in Messages" (`EnableChatMedia`, default on).
    /// Separate from the master toggle: it governs media inside message
    /// threads.
    public var enabledInMessages: Bool

    public static let `default` = InlineMediaSettings(
        enabled: true, alignment: .center, size: .large,
        autoplayMode: .always, enabledInMessages: true)

    public init(
        enabled: Bool,
        alignment: InlineMediaAlignment,
        size: InlineMediaSize,
        autoplayMode: InlineGIFAutoplayMode = .always,
        enabledInMessages: Bool = true
    ) {
        self.enabled = enabled
        self.alignment = alignment
        self.size = size
        self.autoplayMode = autoplayMode
        self.enabledInMessages = enabledInMessages
    }

    enum CodingKeys: String, CodingKey {
        case enabled, alignment, size, tapToPlayGIFs, autoplayMode, enabledInMessages
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? container.decodeIfPresent(Bool.self, forKey: .enabled)) ?? false
        alignment = (try? container.decodeIfPresent(InlineMediaAlignment.self, forKey: .alignment)) ?? .center
        size = (try? container.decodeIfPresent(InlineMediaSize.self, forKey: .size)) ?? .large
        // Migrate the old boolean: a stored `true` meant "Tap to Play".
        if let mode = (try? container.decodeIfPresent(InlineGIFAutoplayMode.self, forKey: .autoplayMode)) {
            autoplayMode = mode
        } else if (try? container.decodeIfPresent(Bool.self, forKey: .tapToPlayGIFs)) == true {
            autoplayMode = .tapToPlay
        } else {
            autoplayMode = .following(GeneralSettingsStore.load().autoplayMode)
        }
        // Defaults to on for settings persisted without this key.
        enabledInMessages = (try? container.decodeIfPresent(Bool.self, forKey: .enabledInMessages)) ?? true
    }

    /// Explicit encoder: `tapToPlayGIFs` is computed, but it is still written
    /// out so an older build reading the file doesn't silently revert to
    /// autoplay.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(alignment, forKey: .alignment)
        try container.encode(size, forKey: .size)
        try container.encode(autoplayMode, forKey: .autoplayMode)
        try container.encode(tapToPlayGIFs, forKey: .tapToPlayGIFs)
        try container.encode(enabledInMessages, forKey: .enabledInMessages)
    }
}

public enum InlineMediaSettingsStore {
    private static let key = "com.pendo324.Phoebus.inlineMediaSettings"

    /// Unset, inline GIFs follow the app-wide autoplay setting, as Reborn's
    /// registered Default does.
    public static let storage = SettingsStore<InlineMediaSettings>(key: key) {
        var settings = InlineMediaSettings.default
        settings.autoplayMode = .following(GeneralSettingsStore.load().autoplayMode)
        return settings
    }

    public static func load() -> InlineMediaSettings { storage.load() }

    public static func save(_ settings: InlineMediaSettings) { storage.save(settings) }
}

extension InlineMediaSettings: StoredSettingsModel {
    public static var store: SettingsStore<InlineMediaSettings> { InlineMediaSettingsStore.storage }
}
