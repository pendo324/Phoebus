import SwiftUI
import PhoebusCore

/// Applies a compiled theme's surface tokens to UIKit's global
/// appearance proxies.
///
/// Covers the chrome SwiftUI routes through UIKit (nav bars, tab bars,
/// tables, scroll views) and the semantic colours views read from
/// `\.apolloTheme`. It is not a per-node repaint.
public enum ThemeAppearance {
    /// Applies the active theme, or clears back to system colours when
    /// no gallery theme is selected.
    @MainActor
    public static func apply(_ theme: Theme) {
        #if canImport(UIKit)
        guard let compiled = compiledTheme(for: theme) else {
            reset()
            return
        }
        let mode: ThemeMode = theme.isDark ? .dark : .light
        func color(_ token: ThemeToken) -> UIColor {
            UIColor(rgb: compiled.rgb(token, mode: mode))
        }

        let barAppearance = UINavigationBarAppearance()
        barAppearance.configureWithOpaqueBackground()
        barAppearance.backgroundColor = color(.barBackground)
        barAppearance.titleTextAttributes = [.foregroundColor: color(.label)]
        barAppearance.largeTitleTextAttributes = [.foregroundColor: color(.label)]
        barAppearance.shadowColor = color(.separator)
        UINavigationBar.appearance().standardAppearance = barAppearance
        UINavigationBar.appearance().compactAppearance = barAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = barAppearance

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = color(.barBackground)
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        UITableView.appearance().backgroundColor = color(.background)
        UITableViewCell.appearance().backgroundColor = color(.secondaryBackground)
        // Reborn #1166: press feedback from the theme's `rowHighlight` token
        // (see `RowHighlight`).
        RowHighlight.themed = color(.rowHighlight)
        RowHighlight.themedSurface = color(.secondaryBackground)
        RowHighlight.install()
        UICollectionView.appearance().backgroundColor = color(.background)
        // Not `UIScrollView.appearance()`: `UIFieldEditor`, the view over a
        // focused text field, is a `UIScrollView` subclass, so a blanket proxy
        // paints an opaque rectangle over focused fields. UIAppearance cannot
        // exclude it by class, so only table and collection views are themed.
        UITextView.appearance().backgroundColor = color(.background)
        // A separator equal to the background is the author's intent (hidden
        // dividers), so it is applied as is.
        UITableView.appearance().separatorColor = color(.separator)

        styleSearchFields(text: color(.label), tint: color(.accent))
        #endif
    }

    /// Styles the `UISearchTextField` embedded in a navigation bar.
    ///
    /// Scoped to `UISearchBar` containment so ordinary form text fields are
    /// unaffected. The magnifier and clear glyphs keep system styling, as in
    /// Reborn.
    @MainActor
    static func styleSearchFields(text: UIColor?, tint: UIColor?) {
        #if canImport(UIKit)
        let field = UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self])
        field.textColor = text
        field.tintColor = tint
        // `field.backgroundColor` is left alone: the stock UISearchBar draws its
        // pill via its own background view.
        #endif
    }

    /// Restores system colours. The appearance proxies are global and sticky,
    /// so switching back to a built-in theme would otherwise leave the
    /// previous theme's surfaces painted.
    @MainActor
    public static func reset() {
        #if canImport(UIKit)
        let barAppearance = UINavigationBarAppearance()
        barAppearance.configureWithDefaultBackground()
        UINavigationBar.appearance().standardAppearance = barAppearance
        UINavigationBar.appearance().compactAppearance = barAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = barAppearance

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        // Stock dark palette: rows sit on Apollo's card surface (#20252F) or the
        // Pure Black override. Read live; light mode keeps system colours.
        let stockDark = UIColor { traits in
            guard traits.userInterfaceStyle == .dark else { return .systemBackground }
            return UIColor(rgb: UInt32(PureBlackSettingsStore.load().darkCardHex, radix: 16) ?? 0)
        }
        UITableView.appearance().backgroundColor = stockDark
        UITableViewCell.appearance().backgroundColor = nil
        // Stock themes use Apollo's #34373F / #F0F1F3 press feedback (Reborn #1166).
        RowHighlight.themed = nil
        RowHighlight.themedSurface = nil
        RowHighlight.install()
        UICollectionView.appearance().backgroundColor = stockDark
        UITextView.appearance().backgroundColor = nil
        UITableView.appearance().separatorColor = nil
        // The iOS 26 focused-fill layer hides search text regardless of theming,
        // so set an explicit dynamic `.label`.
        styleSearchFields(text: .label, tint: nil)
        #endif
    }

    /// The custom theme's font design for SwiftUI text, nil for the system's.
    public static func fontDesign(for theme: Theme) -> Font.Design? {
        CustomThemeStore.theme(forThemeID: theme.id)?.font.design
    }

    /// The compiled gallery theme behind a `Theme`, if it came from the
    /// gallery. Gallery-bridged themes carry the id `gallery_<slug>_<mode>`
    /// (`GalleryTheme.asTheme`), so a persisted selection maps back to its
    /// tokens; Apollo's tinted built-ins compile their surfaces the same way.
    public static func compiledTheme(for theme: Theme) -> CompiledTheme? {
        if let stock = StockThemeSurfaces.compiled(for: theme) { return stock }
        if let custom = CustomThemeStore.theme(forThemeID: theme.id) { return custom.compiled() }
        guard theme.id.hasPrefix("gallery_") else { return nil }
        var slug = String(theme.id.dropFirst("gallery_".count))
        for suffix in ["_light", "_dark"] where slug.hasSuffix(suffix) {
            slug = String(slug.dropLast(suffix.count))
        }
        return ThemeGallery.compiled(slug: slug)
    }
}

#if canImport(UIKit)
extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: 1
        )
    }
}
#endif

// MARK: - SwiftUI environment

/// The active compiled theme's tokens, for views that want to paint
/// with them directly rather than relying on the appearance proxies.
public struct ApolloThemeColors: Sendable, Equatable {
    public let compiled: CompiledTheme?
    public let mode: ThemeMode

    public init(compiled: CompiledTheme?, mode: ThemeMode) {
        self.compiled = compiled
        self.mode = mode
    }

    /// The token's colour, or `nil` when no gallery theme is active -
    /// which callers should read as "use the system colour", NOT as
    /// "use black".
    public func color(_ token: ThemeToken) -> Color? {
        guard let compiled else { return nil }
        return Color(hex: compiled.hex(token, mode: mode))
    }
}

private struct ApolloThemeColorsKey: EnvironmentKey {
    static let defaultValue = ApolloThemeColors(compiled: nil, mode: .light)
}

public extension EnvironmentValues {
    var apolloTheme: ApolloThemeColors {
        get { self[ApolloThemeColorsKey.self] }
        set { self[ApolloThemeColorsKey.self] = newValue }
    }
}

// MARK: - Theme-following accent

public extension Color {
    /// The active theme's accent.
    ///
    /// The active theme's accent. `Color.accentColor` does not follow
    /// `.tint()` (it resolves the AccentColor asset), so call sites that paint
    /// a colour explicitly use this.
    static var apolloAccent: Color {
        Color(hex: ThemeStore.load().accentColorHex)
    }

    /// The colour of an IDLE (uncast) vote arrow.
    ///
    /// The colour of an idle (uncast) vote arrow.
    ///
    /// Reborn "Colourize Vote Arrows" (`Theme.voteArrowsAccent`) tints only the
    /// idle arrow; a cast arrow keeps its green/blue-violet "you voted" signal.
    static var apolloIdleVoteArrow: Color {
        // Non-accent fallback is Apollo's tertiary text colour (#61626A), not
        // `.secondary`.
        ThemeStore.load().voteArrowsAccent ? apolloAccent : apolloTertiaryText
    }
}

// MARK: - Apollo's text palette
//
// Apollo does not use the system label colours: title #D0D1D6 (not
// white), header/info #94969C, domain/flair text and idle arrows #61626A.
public enum ApolloTextPalette {
    public static let primaryLight = "000000"
    public static let primaryDark = "EEEFF5"
    // Pure Black dims the primary text as well as the background.
    public static let primaryDarkPureBlack = "D0D1D6"
    public static let readLight = "999999"
    public static let readDark = "939499"
    public static let readDarkPureBlack = "86868A"
    public static let secondaryDark = "94969C"
    public static let secondaryLight = "6D6D72"
    public static let tertiaryDark = "61626A"
    public static let tertiaryLight = "858585"
}

public extension Color {
    /// Apollo's post-title colour for the current scheme, dimmed once read.
    /// An active gallery theme's `label` token wins.
    static func apolloPrimaryText(
        isRead: Bool = false,
        colorScheme: ColorScheme,
        themeColors: ApolloThemeColors = ApolloThemeColors(compiled: nil, mode: .light)
    ) -> Color {
        if let themed = themeColors.color(.label) { return themed }
        guard colorScheme == .dark else {
            return Color(hex: isRead ? ApolloTextPalette.readLight : ApolloTextPalette.primaryLight)
        }
        let pureBlack = PureBlackSettingsStore.load().isEnabled
        if isRead {
            return Color(hex: pureBlack ? ApolloTextPalette.readDarkPureBlack : ApolloTextPalette.readDark)
        }
        return Color(hex: pureBlack ? ApolloTextPalette.primaryDarkPureBlack : ApolloTextPalette.primaryDark)
    }

    /// Apollo's secondary text (subreddit header, info row).
    static func apolloSecondaryText(
        colorScheme: ColorScheme,
        themeColors: ApolloThemeColors = ApolloThemeColors(compiled: nil, mode: .light)
    ) -> Color {
        if let themed = themeColors.color(.secondaryLabel) { return themed }
        return Color(hex: colorScheme == .dark ? ApolloTextPalette.secondaryDark : ApolloTextPalette.secondaryLight)
    }

    /// Apollo's tertiary text (inline domain, flair text, idle arrows).
    static func apolloTertiaryText(
        colorScheme: ColorScheme,
        themeColors: ApolloThemeColors = ApolloThemeColors(compiled: nil, mode: .light)
    ) -> Color {
        if let themed = themeColors.color(.tertiaryLabel) { return themed }
        return Color(hex: colorScheme == .dark ? ApolloTextPalette.tertiaryDark : ApolloTextPalette.tertiaryLight)
    }

    /// Apollo's hairline between rows and sections.
    static func apolloSeparator(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "333640") : Color(hex: "EEEEEF")
    }

    /// The inline search/find field's rounded fill.
    static func apolloSearchFieldFill(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "1C1C1E") : Color(hex: "E3E4E8")
    }

    /// The inline search/find field's placeholder and glyph.
    static func apolloSearchFieldPlaceholder(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "69696B") : Color(hex: "8E8E93")
    }

    /// The flair capsule's fill when Reddit supplies no colour of its
    /// own: #1A1A1A in pure-black dark mode.
    static func apolloFlairFill(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "1A1A1A") : Color(hex: "EFEFF0")
    }

    /// Scheme-free tertiary, for the few call sites (the idle vote
    /// arrow helper) that are static properties without environment
    /// access; SwiftUI resolves the dynamic UIColor per trait.
    static var apolloTertiaryText: Color {
        #if canImport(UIKit)
        return Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(rgb: 0x61626A)
                : UIColor(rgb: 0x858585)
        })
        #else
        return Color(hex: ApolloTextPalette.tertiaryDark)
        #endif
    }
}

extension ThemeFont {
    public var design: Font.Design? {
        switch self {
        case .system: return nil
        case .rounded: return .rounded
        case .serif: return .serif
        case .mono: return .monospaced
        }
    }
}
