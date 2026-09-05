import Foundation

/// Compiles a theme's eight author-supplied input colours into the 22
/// semantic tokens the UI paints with. Mix fractions and contrast targets are
/// load-bearing constants: a wrong `separatorMix` makes every divider subtly
/// wrong across all gallery themes.
public struct CompiledTheme: Sendable, Equatable {
    /// Packed 0xRRGGBB per token, per mode.
    public let tokens: [ThemeMode: [ThemeToken: UInt32]]

    public func rgb(_ token: ThemeToken, mode: ThemeMode) -> UInt32 {
        tokens[mode]?[token] ?? 0
    }

    public func hex(_ token: ThemeToken, mode: ThemeMode) -> String {
        ThemeColorMath.hexString(rgb(token, mode: mode))
    }
}

public enum ThemeCompiler {
    /// Variant tuning constants (subtle/balanced/bold).
    public struct VariantTuning {
        /// background -> label fraction for the separator.
        public let separatorMix: Double
        public let opaqueSepMix: Double
        /// First fill tier mix; tiers step by `fillStep`.
        public let fillBase: Double
        public let fillStep: Double
        /// accent -> card fraction (higher = subtler).
        public let selectionMix: Double
        /// Saturation multiplier on accent-derived tokens.
        public let accentSat: Double
        /// Extra separation pushed into raised vs card.
        public let raisedBoost: Double
    }

    /// Tuning constants per variant.
    public static func tuning(for variant: ThemeVariant) -> VariantTuning {
        switch variant {
        case .subtle:
            return VariantTuning(separatorMix: 0.10, opaqueSepMix: 0.14,
                                 fillBase: 0.05, fillStep: 0.035,
                                 selectionMix: 0.86, accentSat: 0.85,
                                 raisedBoost: 0.0)
        case .bold:
            return VariantTuning(separatorMix: 0.18, opaqueSepMix: 0.24,
                                 fillBase: 0.09, fillStep: 0.05,
                                 selectionMix: 0.70, accentSat: 1.15,
                                 raisedBoost: 0.04)
        case .balanced:
            return VariantTuning(separatorMix: 0.14, opaqueSepMix: 0.18,
                                 fillBase: 0.066, fillStep: 0.044,
                                 selectionMix: 0.80, accentSat: 1.0,
                                 raisedBoost: 0.0)
        }
    }

    /// Neutral fallbacks per mode, so an empty input still compiles to
    /// something sane.
    static func defaultInput(_ key: ThemeInputKey, mode: ThemeMode) -> UInt32 {
        let dark = mode == .dark
        switch key {
        case .accent: return dark ? 0xFF6B70 : 0xFF5A5F
        case .background: return dark ? 0x000000 : 0xF2F2F7
        case .card: return dark ? 0x1C1C1E : 0xFFFFFF
        case .raised: return dark ? 0x2C2C2E : 0xE5E5EA
        case .bars: return dark ? 0x0A0A0A : 0xF7F7F7
        // text/mutedText/separator all land on the card default, and
        // are then REPLACED by the derived branch, because `wasSet` is
        // false for them.
        case .text, .mutedText, .separator: return dark ? 0x1C1C1E : 0xFFFFFF
        }
    }

    /// The advanced-only input keys, stripped when Advanced is off.
    /// Stripped from a copy so the persisted input is not mutated;
    /// re-enabling Advanced must restore the user's overrides.
    public static let advancedInputKeys: Set<ThemeInputKey> = [.text, .mutedText, .separator]

    /// Compiles one theme.
    public static func compile(
        input: [ThemeMode: [ThemeInputKey: String]],
        variant: ThemeVariant,
        advancedEnabled: Bool
    ) -> CompiledTheme {
        let tune = tuning(for: variant)
        var all: [ThemeMode: [ThemeToken: UInt32]] = [:]
        for mode in ThemeMode.allCases {
            var modeInput = input[mode] ?? [:]
            if !advancedEnabled {
                for key in advancedInputKeys { modeInput.removeValue(forKey: key) }
            }
            all[mode] = compileMode(modeInput, mode: mode, tune: tune)
        }
        return CompiledTheme(tokens: all)
    }

    /// Reads a validated input colour, reporting whether the author
    /// actually set it. The `wasSet` flag is load-bearing, because
    /// text/mutedText/separator take a completely different derivation
    /// when unset.
    private static func inputColor(
        _ input: [ThemeInputKey: String],
        _ key: ThemeInputKey,
        mode: ThemeMode
    ) -> (rgb: UInt32, wasSet: Bool) {
        if let raw = input[key], let parsed = ThemeColorMath.parseHex(raw) {
            return (parsed, true)
        }
        return (defaultInput(key, mode: mode), false)
    }

    private static func compileMode(
        _ input: [ThemeInputKey: String],
        mode: ThemeMode,
        tune: VariantTuning
    ) -> [ThemeToken: UInt32] {
        var t: [ThemeToken: UInt32] = [:]
        let M = ThemeColorMath.self

        // --- surfaces (direct from input) ---
        let accent = inputColor(input, .accent, mode: mode).rgb
        let background = inputColor(input, .background, mode: mode).rgb
        let card = inputColor(input, .card, mode: mode).rgb
        var raised = inputColor(input, .raised, mode: mode).rgb
        let bars = inputColor(input, .bars, mode: mode).rgb

        if tune.raisedBoost > 0 {
            // Bold pushes raised further from card for clearer
            // elevation, toward black on a light card and white on a
            // dark one.
            let toward: UInt32 = M.backgroundIsLight(card) ? 0x000000 : 0xFFFFFF
            raised = M.mix(raised, toward, tune.raisedBoost)
        }

        t[.background] = background
        t[.secondaryBackground] = card
        t[.tertiaryBackground] = raised
        // Elevated deliberately equals card.
        t[.elevatedBackground] = card
        t[.barBackground] = bars

        // --- text (override-aware, repaired against card AND background) ---
        let textIn = inputColor(input, .text, mode: mode)
        let mutedIn = inputColor(input, .mutedText, mode: mode)
        let sepIn = inputColor(input, .separator, mode: mode)

        var label: UInt32
        if textIn.wasSet {
            // Repair against both surfaces, in this order, so author
            // text stays legible on the background and on cards.
            label = M.repairContrast(textIn.rgb, against: background, target: 4.5)
            label = M.repairContrast(label, against: card, target: 4.5)
        } else {
            // Near-black / near-white, softened off pure, then
            // repaired to a much higher 7.0 target.
            label = M.backgroundIsLight(background) ? 0x141414 : 0xF2F2F2
            label = M.repairContrast(label, against: background, target: 7.0)
        }
        t[.label] = label

        let secondaryLabel: UInt32
        if mutedIn.wasSet {
            secondaryLabel = M.repairContrast(mutedIn.rgb, against: background, target: 3.0)
        } else {
            let mixed = M.mix(label, background, 0.36)
            secondaryLabel = M.repairContrast(mixed, against: background, target: 4.0)
        }
        t[.secondaryLabel] = secondaryLabel
        t[.tertiaryLabel] = M.mix(label, background, 0.50)
        t[.quaternaryLabel] = M.mix(label, background, 0.64)
        t[.placeholderText] = t[.tertiaryLabel]
        t[.disabled] = t[.quaternaryLabel]

        // --- separators (override-aware) ---
        if sepIn.wasSet {
            // An explicit override is trusted exactly, including a
            // separator equal to the background to hide dividers entirely.
            t[.separator] = sepIn.rgb
            t[.opaqueSeparator] = sepIn.rgb
        } else {
            t[.separator] = M.mix(background, label, tune.separatorMix)
            t[.opaqueSeparator] = M.mix(background, label, tune.opaqueSepMix)
        }

        // --- fills (background nudged toward label, four tiers) ---
        t[.fill] = M.mix(background, label, tune.fillBase)
        t[.secondaryFill] = M.mix(background, label, tune.fillBase + tune.fillStep)
        t[.tertiaryFill] = M.mix(background, label, tune.fillBase + tune.fillStep * 2)
        t[.quaternaryFill] = M.mix(background, label, tune.fillBase + tune.fillStep * 3)

        // --- accent family ---
        let tunedAccent = M.scaleSaturation(accent, by: tune.accentSat)
        t[.accent] = tunedAccent
        // White or black, whichever reads on the accent, then
        // repaired to a 3.5 contrast target.
        let accentText: UInt32 = M.backgroundIsLight(tunedAccent) ? 0x000000 : 0xFFFFFF
        t[.accentText] = M.repairContrast(accentText, against: tunedAccent, target: 3.5)
        // Link is the accent made readable as TEXT on the
        // background, at a lower 4.0 target.
        t[.link] = M.repairContrast(tunedAccent, against: background, target: 4.0)
        // Selection is the accent tinted heavily toward the CARD,
        // not the background.
        t[.selection] = M.mix(tunedAccent, card, tune.selectionMix)
        // Press feedback (Reborn #1166) halves the accent's
        // contribution so a tap reads as a soft tint, not a flash.
        t[.rowHighlight] = M.mix(tunedAccent, card, 1.0 - (1.0 - tune.selectionMix) * 0.5)

        return t
    }

    /// Derives the opposite mode's inputs from one mode's, for
    /// user/AI/imported themes that only supply one mode.
    public static func generateOppositeModeInput(
        from source: [ThemeInputKey: String],
        sourceMode: ThemeMode
    ) -> [ThemeInputKey: String] {
        var out: [ThemeInputKey: String] = [:]
        let srcLight = sourceMode == .light
        for key in ThemeInputKey.allCases {
            guard let raw = source[key], let rgb = ThemeColorMath.parseHex(raw) else {
                // Leave advanced overrides unset if they were
                // unset, rather than inventing a value for them.
                continue
            }
            var hsl = ThemeColorMath.toHSL(rgb)
            switch key {
            case .accent:
                // Keep hue, nudge lightness toward the new mode's
                // comfort zone.
                hsl.l = srcLight ? min(0.62, hsl.l + 0.06) : max(0.50, hsl.l - 0.06)
            case .text, .mutedText, .separator:
                // Straight lightness inversion.
                hsl.l = 1.0 - hsl.l
            case .background, .card, .raised, .bars:
                // Surfaces invert into a BAND, not a straight
                // flip, so very-light becomes very-dark rather than
                // merely mid-grey.
                hsl.l = srcLight ? (0.06 + (1.0 - hsl.l) * 0.22)
                                 : (0.88 + hsl.l * 0.10)
                hsl.l = ThemeColorMath.clamp01(hsl.l)
            }
            out[key] = ThemeColorMath.hexString(ThemeColorMath.fromHSL(hsl))
        }
        return out
    }
}
