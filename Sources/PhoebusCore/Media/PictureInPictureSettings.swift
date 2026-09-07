import Foundation

/// Reborn's Picture-in-Picture settings, keys and registered defaults.
public struct PictureInPictureSettings: Codable, Equatable, Sendable {
    /// `ApolloPiPActivationMode`.
    public enum Activation: Int, Codable, CaseIterable, Sendable, Identifiable {
        case unmutedOnly = 0, allVideos = 1, allVideosAndGIFs = 2
        public var id: Int { rawValue }
        public var title: String {
            switch self {
            case .unmutedOnly: return "Unmuted Videos Only"
            case .allVideos: return "All Videos"
            case .allVideosAndGIFs: return "All Videos & GIFs"
            }
        }
    }

    /// `ApolloPiPStartPosition`.
    public enum StartPosition: Int, Codable, CaseIterable, Sendable, Identifiable {
        case topLeft = 0, topRight = 1, bottomLeft = 2, bottomRight = 3, lastPosition = 4
        public var id: Int { rawValue }
        public var title: String {
            switch self {
            case .topLeft: return "Top Left"
            case .topRight: return "Top Right"
            case .bottomLeft: return "Bottom Left"
            case .bottomRight: return "Bottom Right"
            case .lastPosition: return "Last Position"
            }
        }
    }

    /// `UDKeyPictureInPictureEnabled`, NO.
    public var inAppEnabled: Bool = false
    /// `UDKeyPictureInPictureStartPosition`, Top Right.
    public var startPosition: StartPosition = .topRight
    /// `UDKeyPictureInPictureStartHidden`, NO.
    public var startHidden: Bool = false
    /// `UDKeyPictureInPictureSkipButtons`, NO.
    public var skipButtons: Bool = false
    /// `UDKeyPictureInPictureSkipSeconds`, 10; choices 5/10/15/30.
    public var skipSeconds: Int = 10
    /// `UDKeyPictureInPictureProgressBar`, NO.
    public var progressBar: Bool = false
    /// `UDKeyPictureInPictureNative`, NO ("Enable PiP When Leaving App").
    public var systemEnabled: Bool = false
    /// `UDKeyPictureInPictureActivation`, Unmuted Videos Only.
    public var activation: Activation = .unmutedOnly
    /// `UDKeyPictureInPictureLoop`, YES.
    public var loopVideos: Bool = true

    public static let skipChoices = [5, 10, 15, 30]

    public init() {}
}

/// Reborn's PiP decisions, kept pure so the smoke suite can pin them.
public enum PictureInPicturePolicy {
    /// Whether a playing video scrolled away hands over to the card.
    /// `isSilent` covers GIFs and any clip without an audio track: Reborn's
    /// strict eligibility needs audio, and only "All Videos & GIFs" admits
    /// the silent ones.
    public static func shouldActivate(settings: PictureInPictureSettings, isPlaying: Bool,
                                      isMuted: Bool, isSilent: Bool) -> Bool {
        guard settings.inAppEnabled, isPlaying else { return false }
        switch settings.activation {
        case .unmutedOnly: return !isMuted && !isSilent
        case .allVideos: return !isSilent
        case .allVideosAndGIFs: return true
        }
    }

    /// Whether "Enable PiP When Leaving App" may hand this inline (or card)
    /// video to the system PiP window. Same modes as the card, gated on the
    /// system switch.
    public static func armsSystemPiP(settings: PictureInPictureSettings, isPlaying: Bool,
                                     isMuted: Bool, isSilent: Bool) -> Bool {
        guard settings.systemEnabled, isPlaying else { return false }
        switch settings.activation {
        case .unmutedOnly: return !isMuted && !isSilent
        case .allVideos: return !isSilent
        case .allVideosAndGIFs: return true
        }
    }

    /// GIFs always loop in PiP; other clips follow Loop Videos.
    public static func loops(isGIF: Bool, settings: PictureInPictureSettings) -> Bool {
        isGIF || settings.loopVideos
    }

    /// The fullscreen viewer's "enter PiP" button (#528): only with in-app
    /// PiP on, and only while the video can't be autoplaying inline (autoplay
    /// off, a spoiler/NSFW post, or a viewer opened from a link with no post
    /// behind it).
    public static func showsFullscreenEntry(inAppEnabled: Bool, autoplaysInline: Bool,
                                            isSpoilerOrNSFW: Bool, isURLOpened: Bool) -> Bool {
        inAppEnabled && (!autoplaysInline || isSpoilerOrNSFW || isURLOpened)
    }

    /// What a back-pop does to a card whose post screen closed.
    public enum BackPop: Equatable, Sendable {
        /// The video's feed row is on screen: hand the picture back to it.
        case restoreInline
        /// No visible home: dismiss the card.
        case close
        /// A fullscreen-origin card has no inline home by design; it stays.
        case keep
    }

    public static func backPop(homeVisible: Bool, fromFullscreen: Bool) -> BackPop {
        if fromFullscreen { return .keep }
        return homeVisible ? .restoreInline : .close
    }
}

public enum PictureInPictureSettingsStore {
    private static let key = "Phoebus.pictureInPictureSettings"

    public static let storage = SettingsStore<PictureInPictureSettings>(key: key) { PictureInPictureSettings() }

    public static func load() -> PictureInPictureSettings { storage.load() }

    public static func save(_ settings: PictureInPictureSettings) { storage.save(settings) }
}

extension PictureInPictureSettings: StoredSettingsModel {
    public static var store: SettingsStore<PictureInPictureSettings> { PictureInPictureSettingsStore.storage }
}
