import SwiftUI
import PhoebusCore

/// Liquid Glass over a material backing.
///
/// A SwiftUI material blurs and tints what is behind it but is not Liquid
/// Glass: no specular rim, no edge lensing, and it cannot merge with a
/// neighbouring glass element. `glassEffect(_:in:)`, `GlassEffectContainer`
/// and `GlassButtonStyle` are available from an older deployment target
/// through `#available`.
///
/// `glassEffect` renders nothing on a host without working Metal (it does not
/// degrade gracefully; the surface disappears), so the glass path is gated on
/// `LiquidGlass.canRenderGlass`, which asks whether a Metal device exists, and
/// the material backing is kept underneath regardless. The Metal check skips
/// the effect on a host that cannot draw it; the backing keeps the surface
/// from vanishing if a host reports Metal but still renders nothing.
public extension View {
    /// Applies Liquid Glass in `shape`, over a material backing.
    ///
    /// - Parameters:
    ///   - shape: the glass outline. Must match the shape the caller was
    ///     filling, or the surface changes silhouette.
    ///   - material: the backing, so a caller that used `.regularMaterial` does
    ///     not become lighter.
    ///   - interactive: `true` for surfaces that respond to touch, such as a tab
    ///     bar pill; the effect reacts to presses.
    ///   - fallbackShadow: drawn only on the material path. Glass brings its own
    ///     shading, and drawing both puts a dark ring just outside the specular
    ///     rim, but hosts that cannot draw glass still need it.
    @ViewBuilder
    func apolloGlassBackground<S: Shape>(
        in shape: S,
        fallback material: Material = .ultraThinMaterial,
        interactive: Bool = false,
        fallbackShadow: (color: Color, radius: CGFloat, y: CGFloat)? = nil
    ) -> some View {
        if #available(iOS 26.0, *), LiquidGlass.isEnabled, LiquidGlass.canRenderGlass {
            // The material is drawn under the effect, not instead of it: if
            // `glassEffect` renders nothing (as on a host without working Metal) the
            // surface beneath is still a complete, readable control.
            self.background(
                shape.fill(material)
                    .glassEffect(
                        interactive ? .regular.interactive() : .regular,
                        in: shape
                    )
            )
            .apolloRecordGlassPath(.glass)
        } else if let fallbackShadow {
            self.background(
                shape.fill(material)
                    .shadow(color: fallbackShadow.color,
                            radius: fallbackShadow.radius,
                            y: fallbackShadow.y)
            )
            .apolloRecordGlassPath(.fallback)
        } else {
            self.background(shape.fill(material))
                .apolloRecordGlassPath(.fallback)
        }
    }

    /// Records which path a surface took, so it can be read back without a
    /// screenshot.
    ///
    /// Both paths are meant to look similar, which makes them hard to tell apart
    /// by eye, and impossible on a host where glass renders nothing.
    ///
    /// Deliberately not an accessibility identifier: these surfaces are applied
    /// to views that already carry their own (`liquidGlassTab.Posts`,
    /// `glassSearch.clear`, `actionSheet.cancel`), and another would override
    /// them.
    func apolloRecordGlassPath(_ path: GlassRenderPath) -> some View {
        onAppear { GlassRenderReport.record(path) }
    }
}

public enum GlassRenderPath: String, Sendable {
    case glass
    case fallback
}

/// What the glass surfaces actually did, as opposed to what they were asked
/// to do.
///
/// `LiquidGlass.activeRenderPath` answers from the same inputs the decision
/// is made from, so it can only agree with itself. This records the path a
/// surface took when it appeared, which catches a call site that never
/// rendered or a mix of paths across the app.
@MainActor
public enum GlassRenderReport {
    public private(set) static var observed: Set<GlassRenderPath> = []

    static func record(_ path: GlassRenderPath) {
        observed.insert(path)
    }

    /// A short human-readable summary, shown in Settings.
    public static var summary: String {
        if observed.isEmpty { return "none drawn yet" }
        return observed.map(\.rawValue).sorted().joined(separator: " + ")
    }
}

