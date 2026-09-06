import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit

/// Reborn's "Center Title Between Buttons" (`CenterTitleBetweenButtons`,
/// default off).
///
/// UIKit centres a `.principal` toolbar item on the bar, so when the
/// leading and trailing controls differ in width the title looks
/// off-centre. This re-centres it in the gap between them.
///
/// Reborn only does this when Liquid Glass is on, actions aren't
/// collapsed, not searching, and both a leading control and trailing
/// actions exist. A screen with only Back keeps the bar midpoint.
///
/// Controls are classified as leading or trailing by the bar midpoint,
/// not by the title, since the title is what may be mispositioned
/// (`NavigationBarGeometry.measure`). The measured offset is published
/// from the screen body (where a `UIViewRepresentable` reliably
/// attaches) to the title inside the toolbar (where one does not),
/// keyed by screen identity so stacked screens cannot read each
/// other's measurement.
@MainActor
public final class TitleCenteringStore: ObservableObject {
    public static let shared = TitleCenteringStore()
    @Published public private(set) var offsets: [String: CGFloat] = [:]

    public func set(_ offset: CGFloat, for key: String) {
        guard abs((offsets[key] ?? 0) - offset) > 0.5 else { return }
        offsets[key] = offset
    }

    public func offset(for key: String) -> CGFloat { offsets[key] ?? 0 }
}

/// Applies the published offset to a `.principal` toolbar title.
public struct CenterTitleBetweenButtonsModifier: ViewModifier {
    @ObservedObject private var store = TitleCenteringStore.shared
    private let key: String
    private let enabled: Bool

    public init(key: String) {
        self.key = key
        let settings = GeneralSettingsStore.load()
        // Liquid Glass and actions not collapsed: a collapsed pill leaves no
        // gap to centre within.
        enabled = settings.enableLiquidGlassTabBar
            && settings.centerTitleGapCentering
            && !settings.collapseNavigationActions
    }

    public func body(content: Content) -> some View {
        content.offset(x: enabled ? store.offset(for: key) : 0)
    }
}

/// The measuring half. It goes on the screen, not the toolbar item: a
/// `UIViewRepresentable` inside a `.principal` toolbar item never runs
/// `updateUIView`. Walking up the responder chain from the screen body
/// reaches the bar that hosts the title.
public struct CenterTitleBetweenButtonsProbe: UIViewRepresentable {
    let key: String
    let enabled: Bool
    let offset: Binding<CGFloat>

    public init(key: String, enabled: Bool, offset: Binding<CGFloat>) {
        self.key = key
        self.enabled = enabled
        self.offset = offset
    }

    public func makeUIView(context: Context) -> UIView {
        let probe = UIView(frame: .zero)
        probe.isUserInteractionEnabled = false
        probe.isHidden = true
        return probe
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        guard enabled else { return }
        DispatchQueue.main.async {
            // The frontmost bar, not `owningViewController()`'s: that controller
            // is a `NavigationStackHostingController` with an empty bar, since
            // SwiftUI hosts toolbar content on a different controller.
            guard let bar = NavigationBarGeometry.frontmostNavigationBar() else { return }
            let measured = NavigationBarGeometry.titleOffset(in: bar)
            TitleCenteringStore.shared.set(measured, for: key)
            // Writing the screen's own `@State` is what actually moves
            // the title; see that property's doc comment.
            if abs(offset.wrappedValue - measured) > 0.5 {
                offset.wrappedValue = measured
            }
        }
    }
}

extension NavigationBarGeometry {
    /// The navigation bar of whatever is frontmost.
    @MainActor
    static func frontmostNavigationBar() -> UINavigationBar? {
        guard let window = UIKitTree.keyWindow else { return nil }
        var controller = window.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return findNavigationBar(in: controller)
    }

    @MainActor
    private static func findNavigationBar(in controller: UIViewController?) -> UINavigationBar? {
        guard let controller else { return nil }
        if let nav = controller as? UINavigationController,
           !nav.isNavigationBarHidden {
            // A nested stack wins: the innermost visible bar carries the title.
            return findNavigationBar(in: nav.visibleViewController) ?? nav.navigationBar
        }
        if let tab = controller as? UITabBarController {
            return findNavigationBar(in: tab.selectedViewController)
        }
        for child in controller.children {
            if let found = findNavigationBar(in: child) { return found }
        }
        return controller.navigationController?.navigationBar
    }

    /// Walks a live bar breadth-first, measuring only content views and
    /// recursing into everything else (measuring containers misclassifies a
    /// wide wrapper as a leading control). Titles and their hosts, bar
    /// backgrounds and snapshots (two bars' worth of replicas during a
    /// push/pop) are excluded.
    @MainActor
    static func titleOffset(in bar: UINavigationBar) -> CGFloat {
        guard let gap = titleGap(in: bar) else { return 0 }
        return gap.midX - bar.bounds.midX
    }

    /// The span between the leading controls and the trailing actions, in
    /// the bar's coordinates, when there is one to centre within.
    @MainActor
    static func titleGap(in bar: UINavigationBar) -> ClosedRange<CGFloat>? {
        let bounds = bar.bounds
        guard bounds.width > 0 else { return nil }
        var leftLimit = bounds.minX + bar.safeAreaInsets.left
        var rightLimit = bounds.maxX - bar.safeAreaInsets.right
        var sawTrailing = false
        let midY = bounds.midY

        var queue: [UIView] = [bar]
        var index = 0
        while index < queue.count {
            let view = queue[index]
            index += 1
            for child in view.subviews {
                guard !child.isHidden, child.alpha >= 0.01 else { continue }
                let className = NSStringFromClass(type(of: child))
                // Exclude titles and their hosts during navigation.
                if className.contains("NavigationBarTitleControl")
                    || className.contains("NavigationBarHostedView")
                    || className.contains("BarBackground")
                    || className.contains("Snapshot") {
                    continue
                }

                // Only these count as measurable content; anything else is a
                // container to descend into. Our bar items are SwiftUI views bridged
                // into the bar, arriving as `_UITAMICAdaptorView` and a SwiftUI
                // `UIKitBarItemHost`, so both are listed. Matching the host beats the
                // drawing view inside it: the host carries the laid-out bounds.
                let isContent = className.contains("NavigationBarPlatterView")
                    || className.contains("UIKitBarItemHost")
                    || className.contains("TAMICAdaptorView")
                    || child is UIControl
                    || child is UILabel
                    || child is UIImageView
                    || child is UIVisualEffectView
                guard isContent else {
                    queue.append(child)
                    continue
                }
                guard child.bounds.width > 0, child.bounds.height > 0 else { continue }

                let frame = child.convert(child.bounds, to: bar)
                // Exclude non-button surfaces: anything spanning the whole bar is a
                // background.
                guard frame.maxY > midY, frame.minY < midY,
                      frame.width < bounds.width - 1 else { continue }
                // Classify pills by the bar midpoint, not the potentially misplaced
                // title.
                if frame.midX < bounds.midX {
                    leftLimit = max(leftLimit, frame.maxX)
                } else {
                    rightLimit = min(rightLimit, frame.minX)
                    sawTrailing = true
                }
            }
        }

        guard offset(
            barWidth: bounds.width,
            leadingSafeArea: bounds.minX + bar.safeAreaInsets.left,
            leftLimit: leftLimit,
            rightLimit: rightLimit,
            hasTrailingActions: sawTrailing
        ) != nil, rightLimit > leftLimit else { return nil }
        return leftLimit...rightLimit
    }
}

public extension View {
    /// Applied to the `.principal` toolbar title.
    func apolloCentersTitleBetweenButtons(key: String) -> some View {
        modifier(CenterTitleBetweenButtonsModifier(key: key))
    }

    /// Applied to the screen that owns that title. Both halves are needed;
    /// see `CenterTitleBetweenButtonsProbe`.
    func apolloMeasuresTitleCentering(key: String, offset: Binding<CGFloat>) -> some View {
        let settings = GeneralSettingsStore.load()
        let enabled = settings.enableLiquidGlassTabBar
            && settings.centerTitleGapCentering
            && !settings.collapseNavigationActions
        return background(
            CenterTitleBetweenButtonsProbe(key: key, enabled: enabled, offset: offset)
                .frame(width: 0, height: 0)
        )
    }
}

extension ClosedRange where Bound == CGFloat {
    var midX: CGFloat { (lowerBound + upperBound) / 2 }
}

/// Publishes each screen's measured gap, in window coordinates.
@MainActor
final class TitleGapStore: ObservableObject {
    static let shared = TitleGapStore()
    @Published private(set) var gaps: [String: ClosedRange<CGFloat>] = [:]
    func set(_ gap: ClosedRange<CGFloat>?, for key: String) {
        guard gaps[key] != gap else { return }
        gaps[key] = gap
    }
}

private struct TitleGapProbe: UIViewRepresentable {
    let key: String

    func makeUIView(context: Context) -> UIView {
        let probe = UIView(frame: .zero)
        probe.isUserInteractionEnabled = false
        probe.isHidden = true
        return probe
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            guard let bar = NavigationBarGeometry.frontmostNavigationBar(), let window = bar.window else { return }
            let gap = NavigationBarGeometry.titleGap(in: bar).map { range -> ClosedRange<CGFloat> in
                let lower = bar.convert(CGPoint(x: range.lowerBound, y: 0), to: window).x
                let upper = bar.convert(CGPoint(x: range.upperBound, y: 0), to: window).x
                return lower...upper
            }
            TitleGapStore.shared.set(gap, for: key)
        }
    }
}

/// A plain screen title that Center Title Between Buttons can move: with
/// the setting on it is drawn as a `.principal` item and offset from where
/// UIKit actually put it (which may already be off-centre for a long title)
/// to the middle of the gap; off, the system title is untouched.
private struct CenteredNavigationTitle: ViewModifier {
    let title: String
    let key: String
    @ObservedObject private var gaps = TitleGapStore.shared
    @State private var titleMidX: CGFloat?

    func body(content: Content) -> some View {
        let settings = GeneralSettingsStore.load()
        if settings.enableLiquidGlassTabBar, settings.centerTitleGapCentering, !settings.collapseNavigationActions {
            let offset = gaps.gaps[key].flatMap { gap in titleMidX.map { gap.midX - $0 } } ?? 0
            content
                .background(TitleGapProbe(key: key).frame(width: 0, height: 0))
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        // The container stays where UIKit put it; only the text moves, so the
                        // measurement can't chase its own offset.
                        ZStack {
                            Text(title)
                                .font(.headline)
                                .lineLimit(1)
                                .offset(x: offset)
                                .accessibilityAddTraits(.isHeader)
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midX } action: { titleMidX = $0 }
                    }
                }
        } else {
            content
        }
    }
}

public extension View {
    /// See `CenteredNavigationTitle`.
    func apolloCentersTitle(_ title: String, key: String) -> some View {
        modifier(CenteredNavigationTitle(title: title, key: key))
    }
}

#else
public extension View {
    func apolloCentersTitle(_ title: String, key: String) -> some View { self }
    func apolloCentersTitleBetweenButtons(key: String) -> some View { self }
    func apolloMeasuresTitleCentering(key: String, offset: Binding<CGFloat>) -> some View { self }
}
#endif
