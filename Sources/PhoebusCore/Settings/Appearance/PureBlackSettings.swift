import Foundation

/// Apollo's "Pure Black Dark Mode" setting: `UsePureBlackDarkMode`,
/// `UsePurePUREBlackMode` ("PURER Black Dark Mode", a second tier above Pure
/// Black) and `PureBlackModeReduceSmearing` (OLED sub-toggle). Separate from
/// `Theme`'s accent/comment-color catalog: this overrides dark-mode
/// background surfaces whatever accent theme is selected.
public struct PureBlackSettings: Codable, Sendable, Equatable {
    /// `UsePureBlackDarkMode`: dark-mode background surfaces become true black
    /// instead of the system's dark gray.
    public var isEnabled: Bool
    /// `UsePurePUREBlackMode`: Apollo's second tier ("PURER Black Dark Mode").
    public var isPurerEnabled: Bool
    /// `PureBlackModeReduceSmearing` - OLED anti-smearing sub-option:
    /// keeps a very slightly lighter shade for actively
    /// scrolling/animating surfaces to avoid the visible ghosting
    /// some OLED panels exhibit against true `#000000`.
    public var reduceSmearing: Bool

    /// The dark-mode app background as a hex string, or nil when Pure
    /// Black does not apply.
    ///
    /// Off #20252F (Apollo's stock dark card), Pure Black #131516,
    /// PURER + Reduce Smearing #050505. Drawn by `ApolloStockSurface`
    /// on each main list, because a background at the app root never
    /// shows (every navigation stack paints opaque system black above it).
    ///
    /// Tiers, as in Reborn's theme runtime:
    ///   - Pure Black only:     #131516 (near-black, still has depth)
    ///   - Pure Black + PURER:  #000000, or #050505 with Reduce Smearing
    /// PURER is ignored while Pure Black is off.
    public var darkBackgroundHex: String? {
        guard isEnabled else { return nil }
        guard isPurerEnabled else { return "131516" }
        return reduceSmearing ? "050505" : "000000"
    }

    /// The stock (non-tinted) dark card surface every row draws on:
    /// Apollo's default #20252F, or the Pure Black tier's override.
    public var darkCardHex: String { darkBackgroundHex ?? "20252F" }

    /// The dark settings PAGE behind the cards: #2B3039 by default, black as
    /// soon as Pure Black is on, #050505 with Reduce Smearing (PURER only
    /// darkens the card).
    public var darkPageHex: String {
        guard isEnabled else { return "2B3039" }
        // Reduce Smearing lifts the page with Pure Black alone, PURER or not.
        return reduceSmearing ? "050505" : "000000"
    }

    /// Whether cards show at all in dark mode: under PURER Black the
    /// card and the page are the same black.
    public var darkCardsVisible: Bool { darkCardHex != darkPageHex }

    public init(isEnabled: Bool = false, isPurerEnabled: Bool = false, reduceSmearing: Bool = false) {
        self.isEnabled = isEnabled
        self.isPurerEnabled = isPurerEnabled
        self.reduceSmearing = reduceSmearing
    }

    public static let `default` = PureBlackSettings()
}

public enum PureBlackSettingsStore {
    private static let key = "com.pendo324.Phoebus.pureBlackSettings"

    public static let storage = SettingsStore<PureBlackSettings>(key: key) { PureBlackSettings.default }

    public static func load() -> PureBlackSettings { storage.load() }

    public static func save(_ settings: PureBlackSettings) { storage.save(settings) }
}

extension PureBlackSettings: StoredSettingsModel {
    public static var store: SettingsStore<PureBlackSettings> { PureBlackSettingsStore.storage }
}
