import Foundation

/// Reborn Gallery View tile size (`Apollo-Reborn#1357`, `#1434`): five
/// bounded steps, changed by the minus/plus buttons or a pinch. The
/// step is stored under Reborn's `ApolloGalleryTileSizeV2` so a backup
/// carries it over.
public enum GalleryTileSize {
    /// Target tile widths in points, smallest to largest.
    public static let widths: [Double] = [90, 128, 185, 260, 360]
    public static let count = widths.count
    /// The middle step: about two columns on an iPhone.
    public static let defaultIndex = 2
    public static let maxColumns = 12
    /// Gutter between tiles and around the grid, 3pt.
    public static let spacing: Double = 3

    public static let key = "ApolloGalleryTileSizeV2"
    /// Reborn's first, 4-step key (0...3); its steps are the last four of the five.
    public static let legacyKey = "ApolloGalleryTileSize"

    public static func clamped(_ index: Int) -> Int {
        max(0, min(count - 1, index))
    }

    public static func stepped(_ index: Int, by step: Int) -> Int {
        clamped(clamped(index) + step)
    }

    public static func index(fromLegacy legacy: Int) -> Int {
        clamped(max(0, min(3, legacy)) + 1)
    }

    /// Columns for a grid `width` points wide: as many tiles of the
    /// step's width as fit, 1...12. The 128pt and 185pt steps keep two
    /// columns whenever the grid is wide enough for two 128pt tiles.
    public static func columns(forWidth width: Double, sizeIndex: Int) -> Int {
        guard width.isFinite, width > 0 else { return 1 }
        let index = clamped(sizeIndex)
        let fit = Int(((width + spacing) / (widths[index] + spacing)).rounded(.down))
        let keepsTwo = index > 0 && index < 3 && width >= 2 * widths[1] + spacing
        return max(keepsTwo ? 2 : 1, min(maxColumns, fit))
    }

    /// The step a pinch settles on: the preset whose width is nearest
    /// (by ratio) to the starting width scaled by the pinch. Spreading
    /// (`scale` > 1) enlarges tiles; pinching together shrinks them.
    public static func sizeIndex(afterPinchScale scale: Double, from index: Int) -> Int {
        let start = clamped(index)
        guard scale.isFinite, scale > 0 else { return start }
        let target = widths[start] * scale
        var best = start
        var bestDistance = Double.infinity
        for (candidate, width) in widths.enumerated() {
            let distance = abs(log(width / target))
            if distance < bestDistance { best = candidate; bestDistance = distance }
        }
        return best
    }

    public static func load(from defaults: UserDefaults = .standard) -> Int {
        if let stored = defaults.object(forKey: key) as? NSNumber { return clamped(stored.intValue) }
        if let legacy = defaults.object(forKey: legacyKey) as? NSNumber { return index(fromLegacy: legacy.intValue) }
        return defaultIndex
    }

    public static let storage = CustomSettingsSource<Int>(
        key: key,
        load: { load(from: $0) },
        save: { $1.set(clamped($0), forKey: key) })
}
