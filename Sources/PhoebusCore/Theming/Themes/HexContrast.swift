import Foundation

/// Black-or-white text selection for a custom colored surface.
///
/// Reborn's Rich Link Previews screen paints the card the exact color you
/// pick, with title and description text set to black or white for contrast.
/// The rule is perceived (Rec. 709) luminance against a 0.6 threshold, with
/// the "dark" choice a near-black (0.10, 0.10, 0.11) rather than pure black.
/// 0.6 is higher than the 0.5 midpoint, so a mid-tone card gets WHITE text.
public enum HexContrast {
    /// Rec. 709 luminance coefficients.
    public static func luminance(ofHex hex: String) -> Double? {
        guard let value = ThemeColorMath.parseHex(hex) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// True when a color is light enough to need DARK text.
    /// True when a color is light enough to need DARK text (luminance > 0.6).
    public static func needsDarkText(onHex hex: String) -> Bool {
        guard let luminance = luminance(ofHex: hex) else { return false }
        return luminance > 0.6
    }

    /// The near-black used for text on a light surface: (0.10, 0.10, 0.11).
    public static let darkTextRGB: (red: Double, green: Double, blue: Double) = (0.10, 0.10, 0.11)
}
