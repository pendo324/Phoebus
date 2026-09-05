import SwiftUI
import PhoebusCore

/// Applies Apollo's Pure Black Dark Mode setting (see `PureBlackSettings`) as a
/// background override: when the setting is on and the system is in dark mode,
/// the default system background becomes true black behind the whole app. Light
/// mode is never affected. `reduceSmearing` uses a barely-off black (`#050505`)
/// instead of `#000000` for OLED anti-ghosting (`PureBlackModeReduceSmearing`).
public struct PureBlackBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let settings: PureBlackSettings

    public func body(content: Content) -> some View {
        content
            .background(backgroundColor)
    }

    private var backgroundColor: Color {
        guard colorScheme == .dark else { return Color(uiColor: .systemBackground) }
        return Color(hex: settings.darkCardHex)
    }
}

extension View {
    /// Applies the Pure Black Dark Mode background; see `PureBlackBackground`.
    public func apolloPureBlackBackground(_ settings: PureBlackSettings) -> some View {
        modifier(PureBlackBackground(settings: settings))
    }
}

/// The stock dark PAGE surface, drawn directly behind a screen's list.
///
/// The root `.apolloPureBlackBackground` never shows, since every navigation
/// stack's hosting view paints opaque system black above it, so each main list
/// carries this itself. Dark mode only; light mode keeps the system background.
public struct ApolloStockSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.apolloTheme) private var apolloTheme
    @AppStorage("com.pendo324.Phoebus.pureBlackSettings") private var stored: Data = Data()

    public func body(content: Content) -> some View {
        content.background {
            // A theme with its own surfaces (a tinted built-in or a
            // gallery theme) paints its card colour, in either mode.
            if let card = apolloTheme.color(.secondaryBackground) {
                card.ignoresSafeArea()
            } else if colorScheme == .dark {
                let settings = (try? JSONDecoder().decode(PureBlackSettings.self, from: stored)) ?? .default
                Color(hex: settings.darkCardHex).ignoresSafeArea()
            }
        }
    }
}

extension View {
    /// Apollo's stock dark surface (#20252F, or the Pure Black tier).
    public func apolloStockSurface() -> some View { modifier(ApolloStockSurface()) }
}
