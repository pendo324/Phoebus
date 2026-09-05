import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit
import ObjectiveC

/// Apollo's list-row press feedback (Reborn #1166).
///
/// SwiftUI `List` rows are `UICollectionViewListCell`s, and a pressed row is
/// painted with UIKit's default `systemGray4`, which is neither Apollo's
/// feedback nor a theme's. This paints a custom theme's `rowHighlight` token,
/// else Apollo's #34373F dark / #F0F1F3 light.
///
/// The cell's background configuration is rebuilt by UIKit on every state
/// change, so the colour is applied after `updateConfiguration(using:)` runs,
/// only while the cell is highlighted or selected.
@MainActor
public enum RowHighlight {
    /// The active custom theme's token, or nil for stock themes.
    static var themed: UIColor?
    /// The active theme's own card surface, or nil for stock themes.
    static var themedSurface: UIColor?

    static let stock = UIColor { traits in
        UIColor(rgb: traits.userInterfaceStyle == .dark ? 0x34373F : 0xF0F1F3)
    }

    static var color: UIColor { themed ?? stock }

    /// The page surface: a theme's own card colour, else the Pure Black tier in
    /// dark mode and the system background in light mode.
    public static var surface: UIColor {
        if let themedSurface { return themedSurface }
        return UIColor { traits in
            guard traits.userInterfaceStyle == .dark else { return .systemBackground }
            let hex = PureBlackSettingsStore.load().darkCardHex
            return UIColor(rgb: UInt32(hex, radix: 16) ?? 0x20252F)
        }
    }

    private static var installed = false

    /// The fill a list row gets by default: UIKit's dynamic
    /// `tableCellPlainBackgroundColor` / `tableCellGroupedBackgroundColor`,
    /// which have no public name to compare against.
    static func isSystemFill(_ color: UIColor?) -> Bool {
        guard let color else { return false }
        let name = String(describing: color)
        return name.contains("tableCellPlainBackgroundColor") || name.contains("tableCellGroupedBackgroundColor")
    }

    /// A cell's background from before it was highlighted.
    nonisolated(unsafe) static var savedKey: UInt8 = 0

    final class Box {
        let configuration: UIBackgroundConfiguration?
        init(_ configuration: UIBackgroundConfiguration?) { self.configuration = configuration }
    }

    public static func install() {
        guard !installed else { return }
        installed = true
        let cls: AnyClass = UICollectionViewListCell.self
        let selector = #selector(UICollectionViewCell.updateConfiguration(using:))
        guard let method = class_getInstanceMethod(cls, selector) else { return }
        typealias Original = @convention(c) (UICollectionViewCell, Selector, UICellConfigurationState) -> Void
        let original = unsafeBitCast(method_getImplementation(method), to: Original.self)
        let block: @convention(block) (UICollectionViewCell, UICellConfigurationState) -> Void = { cell, state in
            original(cell, selector, state)
            // iOS 17 gives a plain List's pinned section headers a grey
            // chrome blur; later releases draw them flat. Paint them the
            // page surface instead so headers match the list behind them.
            if var header = cell.backgroundConfiguration, header.visualEffect != nil {
                header.visualEffect = nil
                header.backgroundColor = RowHighlight.surface
                cell.backgroundConfiguration = header
                return
            }
            // A theme with its own surfaces: rows left on the system fill
            // take the theme's card colour (rows with their own
            // background, or a clear one, keep it).
            if let themedSurface = RowHighlight.themedSurface, !(state.isHighlighted || state.isSelected),
               var row = cell.backgroundConfiguration, RowHighlight.isSystemFill(row.backgroundColor) {
                row.backgroundColor = themedSurface
                cell.backgroundConfiguration = row
            }
            guard state.isHighlighted || state.isSelected else {
                // Put back the row's own background. The highlight is an explicit colour,
                // which `updated(for:)` keeps through every later state, so without this a
                // row stays painted after the press ends (iOS 27 does not have SwiftUI
                // reassign the background itself).
                if let unhighlighted = objc_getAssociatedObject(cell, &RowHighlight.savedKey) as? Box {
                    objc_setAssociatedObject(cell, &RowHighlight.savedKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                    cell.backgroundConfiguration = unhighlighted.configuration?.updated(for: state)
                }
                return
            }
            if objc_getAssociatedObject(cell, &RowHighlight.savedKey) == nil {
                objc_setAssociatedObject(cell, &RowHighlight.savedKey, Box(cell.backgroundConfiguration),
                                         .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
            var background = cell.backgroundConfiguration ?? .listPlainCell()
            background.backgroundColor = RowHighlight.color
            cell.backgroundConfiguration = background
        }
        // Added on the list cell class itself, so the base
        // `UICollectionViewCell` (grids, carousels) is untouched.
        if !class_addMethod(cls, selector, imp_implementationWithBlock(block), method_getTypeEncoding(method)) {
            method_setImplementation(method, imp_implementationWithBlock(block))
        }
    }
}
#endif
