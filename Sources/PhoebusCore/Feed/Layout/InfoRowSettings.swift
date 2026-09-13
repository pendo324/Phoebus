import Foundation

/// Reborn's Info Row sub-screen: configures the feed post info row
/// (score/comments/time bar): magnifier-on-hold, tap-to-upvote/comments/
/// translate actions, and popup vs overlay detail-reveal mode. Pushed from
/// Posts & Feeds > Feed's "Info Row" row.
///
/// Backs `UDKeyIconRowMagnifier`, `UDKeyInfoRowTapUpvote`,
/// `UDKeyInfoRowTapComments`, `UDKeyInfoRowPopupMode`,
/// `UDKeyInfoRowOverlayMode`, `UDKeyInfoRowTapTranslation`.
public struct InfoRowSettings: Codable, Sendable, Equatable {
    /// Whether the Translation info-row marker is available at all: only once
    /// translation is switched on in Translation settings, so it never
    /// advertises a feature the user has not enabled.
    public static var translationAvailable: Bool {
        translationAvailable(TranslationSettingsStore.load())
    }

    /// Reborn's `translationMarkerAvailable`: the marker exists when
    /// Tap to Translate or either Show Details switch is on (and, here,
    /// translation itself is, since the row draws it unconditionally).
    public static func translationAvailable(_ t: TranslationSettings) -> Bool {
        t.enableBulkTranslation && (t.mode == .tapToTranslate || t.showTitleDetails || t.showDetails)
    }

    /// Real key `UDKeyIconRowMagnifier` ("Magnify Info Row on Hold") -
    /// press-and-hold zooms the info row's icons in a glass card.
    public var magnifierOnHold: Bool
    /// Real key `UDKeyInfoRowTapUpvote` - tapping the score upvotes.
    public var tapToUpvote: Bool
    /// Real key `UDKeyInfoRowTapComments` - tapping the comments count
    /// jumps straight to comments (off: still opens the post, just
    /// doesn't jump to comments specifically).
    public var tapToComments: Bool
    /// Real key `UDKeyInfoRowPopupMode`. Mutually exclusive with
    /// `overlayMode`: turning one on turns the other off.
    public var popupMode: Bool
    /// Real key `UDKeyInfoRowOverlayMode`.
    public var overlayMode: Bool
    /// Real key `UDKeyInfoRowTapTranslation` - only meaningful once a
    /// translation marker is available elsewhere.
    public var tapToTranslation: Bool

    public static let `default` = InfoRowSettings(
        magnifierOnHold: true,
        tapToUpvote: true,
        tapToComments: true,
        popupMode: true,
        overlayMode: false,
        tapToTranslation: true
    )

    public init(magnifierOnHold: Bool, tapToUpvote: Bool, tapToComments: Bool, popupMode: Bool, overlayMode: Bool, tapToTranslation: Bool) {
        self.magnifierOnHold = magnifierOnHold
        self.tapToUpvote = tapToUpvote
        self.tapToComments = tapToComments
        self.popupMode = popupMode
        self.overlayMode = overlayMode
        self.tapToTranslation = tapToTranslation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        magnifierOnHold = (try? container.decodeIfPresent(Bool.self, forKey: .magnifierOnHold)) ?? Self.default.magnifierOnHold
        tapToUpvote = (try? container.decodeIfPresent(Bool.self, forKey: .tapToUpvote)) ?? Self.default.tapToUpvote
        tapToComments = (try? container.decodeIfPresent(Bool.self, forKey: .tapToComments)) ?? Self.default.tapToComments
        popupMode = (try? container.decodeIfPresent(Bool.self, forKey: .popupMode)) ?? Self.default.popupMode
        overlayMode = (try? container.decodeIfPresent(Bool.self, forKey: .overlayMode)) ?? Self.default.overlayMode
        tapToTranslation = (try? container.decodeIfPresent(Bool.self, forKey: .tapToTranslation)) ?? Self.default.tapToTranslation
    }

    /// Summary text for a sub-screen's disclosure row, previewing the current
    /// state without pushing the screen.
    public var summaryText: String {
        var parts: [String] = []
        parts.append(magnifierOnHold ? "Magnifier on" : "Magnifier off")
        parts.append(overlayMode ? "Overlays" : (popupMode ? "Popups" : "Info taps off"))
        var disabled: [String] = []
        if !tapToUpvote { disabled.append("Upvote") }
        if !tapToComments { disabled.append("Comments") }
        if Self.translationAvailable, !tapToTranslation { disabled.append("Translation") }
        if !disabled.isEmpty {
            parts.append("\(disabled.joined(separator: ", ")) off")
        }
        return parts.joined(separator: " · ")
    }
}

public enum InfoRowSettingsStore {
    private static let key = "com.pendo324.Phoebus.infoRowSettings"

    public static let storage = SettingsStore<InfoRowSettings>(key: key) { InfoRowSettings.default }

    public static func load() -> InfoRowSettings { storage.load() }

    public static func save(_ settings: InfoRowSettings) { storage.save(settings) }
}

extension InfoRowSettings: StoredSettingsModel {
    public static var store: SettingsStore<InfoRowSettings> { InfoRowSettingsStore.storage }
}
