import Foundation

/// Apollo's moderator green.
///
/// Stock Apollo uses `rgb(0, 148, 15)` (`#00940F`), chosen for opaque chrome.
/// Apollo-Reborn 3.7.0 replaced it with `rgb(48, 209, 88)` (`#30D158`) for
/// legibility on Liquid Glass (Reborn #1047). It is the only moderator green
/// in the app, not the system green.
public enum ApolloPalette {
    /// `#30D158`, Reborn's moderator green.
    public static let moderatorGreenHex = "30D158"

    /// `#00940F`, stock Apollo's moderator green; documented and assertable, not used.
    public static let legacyModeratorGreenHex = "00940F"
}
