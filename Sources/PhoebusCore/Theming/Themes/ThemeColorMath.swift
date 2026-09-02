import Foundation

/// The 22 semantic colour tokens a compiled theme produces.
///
/// Index-aligned with Apollo-Reborn's theme tokens, with the same string
/// keys as raw values, so a compiled theme here and one from the tweak
/// describe the same thing under the same names.
public enum ThemeToken: String, Sendable, CaseIterable {
    case background
    case secondaryBackground
    case tertiaryBackground
    case elevatedBackground
    case barBackground

    case label
    case secondaryLabel
    case tertiaryLabel
    case quaternaryLabel
    case placeholderText

    case separator
    case opaqueSeparator

    case fill
    case secondaryFill
    case tertiaryFill
    case quaternaryFill

    case accent
    case accentText
    case link
    case selection
    case disabled
    /// Press feedback, independent of `selection` (unread indicators).
    /// Reborn issue #1166, appended after `disabled` so the index alignment holds.
    case rowHighlight
}

/// The eight colours a theme author actually supplies.
public enum ThemeInputKey: String, Sendable, CaseIterable {
    case accent
    case background
    case card
    case raised
    case bars
    case text
    case mutedText
    case separator
}

public enum ThemeVariant: String, Sendable, CaseIterable {
    case subtle
    case balanced
    case bold
}

public enum ThemeMode: String, Sendable, CaseIterable {
    case light
    case dark
}

/// Packed 0xRRGGBB colour maths, ported from Apollo-Reborn's theme compiler
/// and luminance helpers. Plain integer maths with no UI types, so it is
/// exactly assertable.
public enum ThemeColorMath {
    public static func unpack(_ rgb: UInt32) -> (r: Double, g: Double, b: Double) {
        (Double((rgb >> 16) & 0xFF) / 255.0,
         Double((rgb >> 8) & 0xFF) / 255.0,
         Double(rgb & 0xFF) / 255.0)
    }

    public static func clamp01(_ v: Double) -> Double { v < 0 ? 0 : (v > 1 ? 1 : v) }

    public static func pack(r: Double, g: Double, b: Double) -> UInt32 {
        let rr = UInt32((clamp01(r) * 255).rounded())
        let gg = UInt32((clamp01(g) * 255).rounded())
        let bb = UInt32((clamp01(b) * 255).rounded())
        return (rr << 16) | (gg << 8) | bb
    }

    /// Linear blend a->b by t (0 = a, 1 = b).
    public static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        let ca = unpack(a), cb = unpack(b)
        return pack(
            r: ca.r + (cb.r - ca.r) * t,
            g: ca.g + (cb.g - ca.g) * t,
            b: ca.b + (cb.b - ca.b) * t
        )
    }

    public struct HSL: Sendable, Equatable {
        public var h: Double
        public var s: Double
        public var l: Double
    }

    public static func toHSL(_ rgb: UInt32) -> HSL {
        let c = unpack(rgb)
        let mx = max(c.r, max(c.g, c.b)), mn = min(c.r, min(c.g, c.b))
        var h = 0.0, s = 0.0
        let l = (mx + mn) / 2.0
        let d = mx - mn
        if d > 1e-6 {
            s = l > 0.5 ? d / (2.0 - mx - mn) : d / (mx + mn)
            if mx == c.r { h = (c.g - c.b) / d + (c.g < c.b ? 6.0 : 0.0) }
            else if mx == c.g { h = (c.b - c.r) / d + 2.0 }
            else { h = (c.r - c.g) / d + 4.0 }
            h /= 6.0
        }
        return HSL(h: h, s: s, l: l)
    }

    private static func hueChannel(_ p: Double, _ q: Double, _ tIn: Double) -> Double {
        var t = tIn
        if t < 0 { t += 1 }
        if t > 1 { t -= 1 }
        if t < 1.0 / 6.0 { return p + (q - p) * 6.0 * t }
        if t < 1.0 / 2.0 { return q }
        if t < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - t) * 6.0 }
        return p
    }

    public static func fromHSL(_ hsl: HSL) -> UInt32 {
        let h = hsl.h, s = clamp01(hsl.s), l = clamp01(hsl.l)
        if s <= 1e-6 { return pack(r: l, g: l, b: l) }
        let q = l < 0.5 ? l * (1.0 + s) : l + s - l * s
        let p = 2.0 * l - q
        return pack(
            r: hueChannel(p, q, h + 1.0 / 3.0),
            g: hueChannel(p, q, h),
            b: hueChannel(p, q, h - 1.0 / 3.0)
        )
    }

    /// sRGB channel linearisation.
    private static func linearize(_ c: Double) -> Double {
        c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// Relative luminance.
    ///
    /// The PROPER WCAG luminance, with sRGB linearisation; not the cheap
    /// non-linear 0.2126r+0.7152g+0.0722b used by `HexContrast` for the
    /// link-preview card. The card's rule comes from Reborn's flair colors, this
    /// one from the theme compiler.
    public static func luminance(_ rgb: UInt32) -> Double {
        let c = unpack(rgb)
        return 0.2126 * linearize(c.r) + 0.7152 * linearize(c.g) + 0.0722 * linearize(c.b)
    }

    /// The WCAG contrast ratio.
    public static func contrastRatio(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// The threshold is 0.4, NOT 0.5.
    public static func backgroundIsLight(_ bg: UInt32) -> Bool {
        luminance(bg) > 0.4
    }

    /// Soft contrast repair: nudge lightness away from `bg` until the
    /// ratio meets `target`, preserving hue and saturation.
    ///
    /// Uses a 24-step cap and 0.04 step: "darken/lighten until it passes", not a
    /// hard replacement.
    public static func repairContrast(_ color: UInt32, against bg: UInt32, target: Double) -> UInt32 {
        if contrastRatio(color, bg) >= target { return color }
        var hsl = toHSL(color)
        let darken = luminance(bg) > 0.4
        for _ in 0..<24 {
            hsl.l = clamp01(hsl.l + (darken ? -0.04 : 0.04))
            let candidate = fromHSL(hsl)
            if contrastRatio(candidate, bg) >= target { return candidate }
            if hsl.l <= 0.0 || hsl.l >= 1.0 { return candidate }
        }
        return fromHSL(hsl)
    }

    public static func scaleSaturation(_ rgb: UInt32, by factor: Double) -> UInt32 {
        var hsl = toHSL(rgb)
        hsl.s = clamp01(hsl.s * factor)
        return fromHSL(hsl)
    }

    /// Parses a bare or `#`-prefixed 6-digit hex string. The app's one
    /// hex parser: flair colours, theme colours, card colours and
    /// contrast all go through it.
    public static func parseHex(_ hex: String) -> UInt32? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        s.removeAll { $0 == "#" }
        // `UInt32(_:radix:)` alone also takes a leading sign.
        guard s.count == 6, s.allSatisfy(\.isHexDigit), let value = UInt32(s, radix: 16) else { return nil }
        return value
    }

    /// Bare uppercase 6-digit hex, the form the catalog stores.
    public static func hexString(_ rgb: UInt32) -> String {
        String(format: "%06X", rgb)
    }
}
