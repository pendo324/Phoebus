import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Measured Apollo point sizes that still follow Dynamic Type.
///
/// Much of the app's type is pinned to sizes measured from Apollo
/// (`.system(size: 15, weight: .semibold)` for a comment author, 17pt for
/// settings rows). Pinned sizes ignore the user's text size, which Apollo
/// honours (Reborn #1165 extends that to its settings). This keeps the
/// measured size at the default ("Large") category and scales it with
/// `UIFontMetrics` for every other, the same scaling UIKit applies to a
/// `preferredFont`. The environment's `dynamicTypeSize` (set app-wide by "Use
/// System Text Size" / "Text Size") drives it.
struct ScaledSystemFont: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight
    let textStyle: Font.TextStyle
    let monospacedDigit: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let font = Font.system(size: Self.scaled(size, style: textStyle, for: dynamicTypeSize), weight: weight)
        return content.font(monospacedDigit ? font.monospacedDigit() : font)
    }

    static func scaled(_ size: CGFloat, style: Font.TextStyle, for dynamicType: DynamicTypeSize) -> CGFloat {
        #if canImport(UIKit)
        let metrics = UIFontMetrics(forTextStyle: style.uiTextStyle)
        let traits = UITraitCollection(preferredContentSizeCategory: dynamicType.contentSizeCategory)
        return metrics.scaledValue(for: size, compatibleWith: traits)
        #else
        return size
        #endif
    }
}

extension View {
    /// `.font(.system(size:weight:))` that scales with Dynamic Type.
    func apolloFont(size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body,
                    monospacedDigit: Bool = false) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, textStyle: style, monospacedDigit: monospacedDigit))
    }
}

#if canImport(UIKit)
extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        default: return .body
        }
    }
}

extension DynamicTypeSize {
    var contentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}
#endif

/// Apollo's measured 52pt settings row, as a Dynamic Type aware minimum:
/// exactly 52pt at the default text size, scaled with the text above it, and
/// free to grow when a long title wraps (an explicit height clips two-line
/// titles at large sizes).
struct ApolloSettingsRowHeight: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        // Scaled by the text's growth only: scaling the whole 52pt by the body
        // metrics also grows the 29pt icon's padding, giving 96pt rows at AX sizes.
        let growth = ScaledSystemFont.scaled(ApolloSettingsRowMetrics.titlePointSize, style: .body, for: dynamicTypeSize)
            - ApolloSettingsRowMetrics.titlePointSize
        let height = ApolloSettingsRowMetrics.rowHeight + growth
        // No padding here: the row's `apolloSettingsRowInsets` already
        // adds breathing room above the default size.
        return content.frame(minHeight: height)
    }
}

extension View {
    func apolloSettingsRowHeight() -> some View { modifier(ApolloSettingsRowHeight()) }
}

/// Vertical breathing room for a settings row once Dynamic Type is
/// above the default, where titles wrap. Nothing at the default size.
struct ApolloSettingsRowVerticalBreathing: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var enabled = true
    func body(content: Content) -> some View {
        content.padding(.vertical, enabled && dynamicTypeSize > .large ? 8 : 0)
    }
}

/// `defaultMinListRowHeight` scaled with Dynamic Type (52pt at the
/// default size, the measured settings pitch).
struct ApolloScaledMinRowHeight: ViewModifier {
    let base: CGFloat
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    func body(content: Content) -> some View {
        let growth = ScaledSystemFont.scaled(17, style: .body, for: dynamicTypeSize) - 17
        return content.environment(\.defaultMinListRowHeight, base + growth)
    }
}
