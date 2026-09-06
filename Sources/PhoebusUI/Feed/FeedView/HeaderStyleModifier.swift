import SwiftUI
import PhoebusCore

/// Applies the user's `HeaderStyle` to every scroll view beneath it.
public struct HeaderStyleModifier: ViewModifier {
    /// Observed, so a change in Interface settings applies at once.
    @AppStorage(HeaderStyleStore.defaultsKey) private var raw = HeaderStyle.automatic.rawValue

    public func body(content: Content) -> some View {
        styled(content)
            // Scroll views already on screen keep the style they were given
            // until something redraws them, so a change is pushed to them
            // directly, as Reborn sets topEdgeEffect.
            .onChange(of: raw) { _, value in
                HeaderStyleSweep.apply(HeaderStyle(rawValue: value) ?? .automatic)
            }
    }

    @ViewBuilder
    private func styled(_ content: Content) -> some View {
        // Reborn sets the scroll views' top edge effect (iOS 26's
        // UIScrollEdgeEffect); SwiftUI's own edge-effect modifiers do the
        // same, and reach every scroll view below them. Blur is Reborn's
        // own progressive blur, which has no public equivalent, so it
        // falls back to Soft.
        if #available(iOS 26.0, *) {
            switch HeaderStyle(rawValue: raw) ?? .automatic {
            case .automatic:
                content
            case .soft, .blur:
                content.scrollEdgeEffectStyle(.soft, for: .top)
            case .hard:
                content.scrollEdgeEffectStyle(.hard, for: .top)
            case .hidden:
                content.scrollEdgeEffectHidden(true, for: .top)
            }
        } else {
            content
        }
    }
}

extension View {
    /// Applies the currently persisted `HeaderStyle`: the standard call
    /// site for any top-level pushed or tabbed screen that respects this
    /// setting.
    public func applyHeaderStyle() -> some View {
        modifier(HeaderStyleModifier())
    }
}

#if canImport(UIKit)
@MainActor
enum HeaderStyleSweep {
    static func apply(_ style: HeaderStyle) {
        guard #available(iOS 26.0, *) else { return }
        for window in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows) {
            for scrollView in UIKitTree.scrollViews(in: window) {
                let edge = scrollView.topEdgeEffect
                switch style {
                case .automatic:
                    edge.isHidden = false
                    edge.style = .automatic
                case .soft, .blur:
                    edge.isHidden = false
                    edge.style = .soft
                case .hard:
                    edge.isHidden = false
                    edge.style = .hard
                case .hidden:
                    edge.isHidden = true
                }
            }
        }
    }
}
#else
enum HeaderStyleSweep {
    static func apply(_ style: HeaderStyle) {}
}
#endif
