import Foundation

/// Which settings screen a pinned live preview belongs to.
///
/// Reborn stores one default per screen rather than one global switch:
/// `UDKeySubredditSectionsPreviewPinned`, `UDKeyLinkPreviewPreviewPinned` and
/// `UDKeyInlineMediaPreviewPinned`. The keys are reused so the preference
/// means the same thing here.
public enum SettingsPreviewScreen: String, Sendable, CaseIterable {
    case inlineMedia = "InlineMediaPreviewPinned"
    case linkPreview = "LinkPreviewPreviewPinned"
    case subredditSections = "SubredditSectionsPreviewPinned"
    // The three Reborn layout previews, keyed one key per screen the same way.
    case feedShortcuts = "FeedShortcutsPreviewPinned"
    case subredditLayout = "SubredditLayoutPreviewPinned"
    case profileLayout = "ProfileLayoutPreviewPinned"
}

/// Whether each screen's live preview card stays pinned.
///
/// Pinned by default, with an absent value meaning true. Storing the
/// preference as `isPinned` with an absent-means-true read keeps that,
/// rather than inverting it into "isUnpinned".
public enum SettingsPreviewPinStore {
    /// Namespaced so these cannot collide with the Apollo defaults also read.
    public static func defaultsKey(for screen: SettingsPreviewScreen) -> String {
        "Phoebus." + screen.rawValue
    }

    public static func isPinned(_ screen: SettingsPreviewScreen) -> Bool {
        let key = defaultsKey(for: screen)
        // An ABSENT value means pinned; `bool(forKey:)` alone would return false
        // for "never set".
        guard UserDefaults.standard.object(forKey: key) != nil else { return true }
        return UserDefaults.standard.bool(forKey: key)
    }

    public static func setPinned(_ pinned: Bool, for screen: SettingsPreviewScreen) {
        UserDefaults.standard.set(pinned, forKey: defaultsKey(for: screen))
    }

    /// Caption shown briefly beside the glyph after a tap;
    /// `pinningAvailable` false overrides to "Needs room".
    public static func caption(pinned: Bool, pinningAvailable: Bool = true) -> String {
        guard pinningAvailable else { return "Needs room" }
        return pinned ? "Pinned" : "Unpinned"
    }

    /// Accessibility label, unaffected by room, since the
    /// control's role (pin vs unpin) does not change, only whether it
    /// takes effect immediately.
    public static func accessibilityLabel(pinned: Bool) -> String {
        pinned ? "Unpin preview" : "Pin preview"
    }

    /// Glyph: `pin.slash` once there truly is no room, regardless of
    /// the stored preference.
    public static func symbolName(pinned: Bool, pinningAvailable: Bool = true) -> String {
        guard pinningAvailable else { return "pin.slash" }
        return pinned ? "pin.fill" : "pin"
    }
}
