import Foundation

/// One theme from Apollo-Reborn's gallery.
///
/// The gallery ships as portable schema-v3 JSON; a Swift table is generated
/// from the same files (`scripts/generate/gen-theme-gallery.py`). Every
/// colour is upstream's, unmodified.
public struct GalleryTheme: Sendable, Equatable, Identifiable {
    /// Stable identifier. Slugs are persisted in user backups, so renaming a
    /// shipped slug orphans restores on builds that no longer know it.
    public let slug: String
    public let name: String
    public let variant: ThemeVariant
    public let input: [ThemeMode: [ThemeInputKey: String]]

    public var id: String { slug }

    public init(
        slug: String,
        name: String,
        variant: ThemeVariant,
        input: [ThemeMode: [ThemeInputKey: String]]
    ) {
        self.slug = slug
        self.name = name
        self.variant = variant
        self.input = input
    }

    /// Compiles this theme's tokens.
    ///
    /// Every gallery theme sets `advancedEnabled: true`, because all of them
    /// supply explicit text/mutedText/separator values that would otherwise be
    /// stripped and re-derived.
    public func compiled() -> CompiledTheme {
        ThemeCompiler.compile(input: input, variant: variant, advancedEnabled: true)
    }
}

public enum ThemeGallery {
    public static func theme(slug: String) -> GalleryTheme? {
        all.first { $0.slug == slug }
    }

    /// Compiled tokens, cached: compiling is pure integer maths but
    /// involves up to 24 contrast-repair iterations per token, and a
    /// gallery grid asks for every theme at once.
    public static func compiled(slug: String) -> CompiledTheme? {
        if let cached = cacheLock.withLock({ cache[slug] }) { return cached }
        guard let theme = theme(slug: slug) else { return nil }
        let compiled = theme.compiled()
        cacheLock.withLock { cache[slug] = compiled }
        return compiled
    }

    nonisolated(unsafe) private static var cache: [String: CompiledTheme] = [:]
    private static let cacheLock = NSLock()
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

public extension GalleryTheme {
    /// Bridges a gallery theme into this rewrite's own `Theme` model,
    /// so selecting one from the gallery applies through the existing
    /// `ThemeStore` rather than needing a parallel theming path.
    ///
    /// A `Theme` here carries an accent and a comment-depth palette,
    /// where a gallery theme carries 22 compiled tokens. The accent
    /// maps directly. The comment-depth colours are DERIVED from the
    /// theme's own compiled tokens rather than borrowing one of
    /// Apollo's named palettes: a gallery theme is a coherent colour
    /// scheme, and pinning Dracula's comment rails to Apollo's
    /// "Rainbow" would be exactly the sort of unrelated-colours result
    /// the gallery exists to avoid.
    ///
    /// The derivation walks the theme's own accent hue around the
    /// wheel, keeping its saturation and lightness, so the rails stay
    /// recognisably part of the same scheme.
    func asTheme(mode: ThemeMode) -> Theme {
        let compiled = ThemeGallery.compiled(slug: slug) ?? self.compiled()
        let accentRGB = compiled.rgb(.accent, mode: mode)
        return Theme(
            id: "gallery_\(slug)_\(mode.rawValue)",
            name: name,
            accentColorHex: ThemeColorMath.hexString(accentRGB),
            commentDepthColorHexes: GalleryTheme.commentDepthHexes(fromAccent: accentRGB),
            isDark: mode == .dark,
            // Marked generated so `ThemeStore` PERSISTS it. Without
            // this, a gallery theme would be selected, written as an
            // id, and then fail to resolve on next launch because it
            // is not in the fixed built-in catalog - the app would
            // silently fall back to Default.
            isGenerated: true,
            // No named Apollo palette applies; `nil` means "this
            // theme's own custom hexes", which `CommentsThemeStore`
            // already handles explicitly.
            commentPaletteName: nil
        )
    }

    /// Six comment-depth rails derived from the theme's accent by
    /// rotating hue in even steps, preserving saturation and lightness.
    static func commentDepthHexes(fromAccent accent: UInt32) -> [String] {
        let base = ThemeColorMath.toHSL(accent)
        return (0..<6).map { step in
            var hsl = base
            hsl.h = (base.h + Double(step) / 6.0).truncatingRemainder(dividingBy: 1.0)
            return ThemeColorMath.hexString(ThemeColorMath.fromHSL(hsl))
        }
    }
}
