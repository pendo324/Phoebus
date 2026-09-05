import Foundation

/// The surfaces of Apollo's five tinted built-in themes (Solarized,
/// Outrun, Sunset, Sepia, Dracula), which recolour the whole app rather
/// than just the accent, and ignore Pure Black. Values are Reborn's stock
/// theme table: card, page and separator, light and dark. The other thirteen
/// built-ins share Apollo's stock surfaces.
public enum StockThemeSurfaces {
    struct Surfaces {
        let card: (light: String, dark: String)
        let page: (light: String, dark: String)
        let separator: (light: String, dark: String)
    }

    static let tinted: [String: Surfaces] = [
        "Solarized": Surfaces(card: ("FDF6E3", "002B36"), page: ("E6DFCF", "003745"), separator: ("E0DCCD", "002836")),
        "Outrun": Surfaces(card: ("CFD7E8", "061636"), page: ("BAC1D1", "081D47"), separator: ("B5B9C7", "06214D")),
        "Sunset": Surfaces(card: ("FFE3D0", "000F29"), page: ("F2D8C7", "12223D"), separator: ("E0CBBD", "061B40")),
        "Sepia": Surfaces(card: ("F1EAD9", "211E1A"), page: ("DBD5CA", "38332C"), separator: ("D4CEC0", "29271F")),
        "Dracula": Surfaces(card: ("F8F8F3", "1A1D29"), page: ("EDEDE8", "222636"), separator: ("D7D3E0", "242838")),
    ]

    public static func isTinted(_ theme: Theme) -> Bool {
        !theme.isGenerated && tinted[theme.name] != nil && Theme.allThemes.contains { $0.id == theme.id }
    }

    /// The compiled tokens for a tinted built-in, or nil for any other
    /// theme. Cards, page and separators are exact; text is derived
    /// against them; the accent is the theme's own, untouched.
    public static func compiled(for theme: Theme) -> CompiledTheme? {
        guard isTinted(theme), let surfaces = tinted[theme.name] else { return nil }
        let pair = Theme.allThemes.filter { $0.name == theme.name }
        func input(_ dark: Bool) -> [ThemeInputKey: String] {
            let accent = pair.first { $0.isDark == dark }?.accentColorHex ?? theme.accentColorHex
            let card = dark ? surfaces.card.dark : surfaces.card.light
            return [
                .accent: accent,
                .background: dark ? surfaces.page.dark : surfaces.page.light,
                .card: card, .raised: card, .bars: card,
                .separator: dark ? surfaces.separator.dark : surfaces.separator.light,
            ]
        }
        let compiled = ThemeCompiler.compile(input: [.light: input(false), .dark: input(true)],
                                             variant: .balanced, advancedEnabled: true)
        var tokens = compiled.tokens
        for mode in ThemeMode.allCases {
            let hex = input(mode == .dark)[.accent] ?? theme.accentColorHex
            if let rgb = ThemeColorMath.parseHex(hex) { tokens[mode]?[.accent] = rgb }
        }
        return CompiledTheme(tokens: tokens)
    }
}
