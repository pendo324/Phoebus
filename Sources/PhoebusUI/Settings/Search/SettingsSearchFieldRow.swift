import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit
#endif

/// The pinned "Search Settings" field at the top of the Settings root.
///
///   - spans x 16..377 (a 16pt margin each side), 43pt tall, directly under
///     the title;
///   - a capsule (21.5pt radius), not a 10pt-radius rect;
///   - fill rgb(28,28,30) = #1C1C1E dark / #EEEEEF light;
///   - magnifier ink 14pt inside the field (x 30..46.3);
///   - placeholder 17pt regular in rgb(105,105,107) = #69696B, ink starting
///     at x 56.7.
///
/// The comments' "Find in Comments" field shares the same y, x, radius and
/// magnifier, so both rows use `ApolloSearchCapsuleMetrics`.
///
/// A row rather than `.searchable`: with
/// `.searchable(placement: .navigationBarDrawer(displayMode: .always))` the
/// prompt is handed to the iOS 26 Liquid Glass tab bar's own magnifying glass
/// and no field is drawn. Same layout as `FindInCommentsFieldRow`; only the
/// height (44 vs 47) and the placeholder differ.
public struct SettingsSearchFieldRow: View {
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool
    /// How far the list is pulled down past its top, for pull to search.
    @State private var overscroll: CGFloat = 0
    /// The pull while the finger is down; the affordance fades on release.
    @State private var pull: CGFloat = 0

    public init(text: Binding<String>) {
        self._text = text
    }

    /// #1C1C1E measured in pure-black dark mode.
    private var fieldFill: Color {
        Color.apolloSearchFieldFill(colorScheme: colorScheme)
    }

    /// The placeholder's measured rgb(105,105,107).
    private var placeholderColor: Color {
        Color.apolloSearchFieldPlaceholder(colorScheme: colorScheme)
    }

    public var body: some View {
        HStack(spacing: 10) {
            field
            // Reborn's active search: a close button beside the field ends the search.
            if isFocused {
                Button {
                    text = ""
                    isFocused = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(Color.primary)
                        .frame(width: ApolloSearchCapsuleMetrics.height, height: ApolloSearchCapsuleMetrics.height)
                        .background(Circle().fill(fieldFill))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Search")
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, ApolloSearchCapsuleMetrics.sideMargin)
        .animation(.easeOut(duration: 0.2), value: isFocused)
        // Pull to search: the field stays put while the list stretches
        // below it, and the gap shows the affordance.
        .offset(y: -overscroll)
        .overlay(alignment: .bottom) {
            PullToSearchAffordance(overscroll: pull)
                .alignmentGuide(.bottom) { $0[.top] - 12 }
                .offset(y: -overscroll)
                .allowsHitTesting(false)
        }
        #if canImport(UIKit)
        .background(PullToSearchProbe(isActive: isFocused, overscroll: $overscroll, pull: $pull) {
            isFocused = true
        })
        #endif
    }

    private var field: some View {
        HStack(spacing: ApolloSearchCapsuleMetrics.iconToText) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17))
                .foregroundStyle(placeholderColor)
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text("Search Settings")
                        .font(.system(size: 17))
                        .foregroundStyle(placeholderColor)
                }
                TextField("", text: $text)
                    .font(.system(size: 17))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .submitLabel(.search)
            }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(placeholderColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .apolloSearchCapsule(fill: fieldFill, horizontalMargin: 0)
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .accessibilityIdentifier("settings.searchField")
        .accessibilityLabel("Search Settings")
    }
}

/// Reborn's pull to search on the Settings root: past 6pt of overscroll a
/// magnifier and "Pull to search" fade and grow in; at 62pt they turn the
/// accent colour, read "Release to search" with a haptic, and letting go opens
/// search.
enum PullToSearch {
    static let revealStart: CGFloat = 6
    static let threshold: CGFloat = 62

    static func progress(_ overscroll: CGFloat) -> CGFloat {
        guard overscroll > revealStart else { return 0 }
        return min(1, (overscroll - revealStart) / (threshold - revealStart))
    }
}

struct PullToSearchAffordance: View {
    let overscroll: CGFloat

    var body: some View {
        let progress = PullToSearch.progress(overscroll)
        let armed = overscroll >= PullToSearch.threshold
        let tint = armed ? Color.apolloAccent : Color.secondary
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .semibold))
                .scaleEffect(0.6 + 0.4 * progress)
            Text(armed ? "Release to search" : "Pull to search")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(tint)
        .animation(.easeOut(duration: 0.15), value: armed)
        .opacity(progress)
    }
}

#if canImport(UIKit)
/// Reads the list's overscroll off its own pan gesture, as Reborn does,
/// so the list's scrolling is untouched.
private struct PullToSearchProbe: UIViewRepresentable {
    let isActive: Bool
    @Binding var overscroll: CGFloat
    @Binding var pull: CGFloat
    let activate: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        context.coordinator.isActive = isActive
        context.coordinator.report = { overscroll = $0 }
        context.coordinator.reportPull = { value in
            if value == 0 {
                withAnimation(.easeOut(duration: 0.2)) { pull = 0 }
            } else {
                pull = value
            }
        }
        context.coordinator.activate = activate
    }

    final class ProbeView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            coordinator?.attach(to: ScrollGestureExclusivity.enclosingScrollViews(of: self).first)
            unclipRow()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            unclipRow()
        }

        /// The field is held in place above its row while the list
        /// stretches, and the affordance drawn below it, so the row's
        /// cell must not clip them.
        private func unclipRow() {
            var view = superview
            while let current = view, !(current is UIScrollView) {
                current.clipsToBounds = false
                if current is UICollectionViewCell || current is UITableViewCell { break }
                view = current.superview
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var isActive = false
        var report: (CGFloat) -> Void = { _ in }
        var reportPull: (CGFloat) -> Void = { _ in }
        private var observation: NSKeyValueObservation?
        private var lastOverscroll: CGFloat = 0
        var activate: () -> Void = {}
        private weak var scrollView: UIScrollView?
        private var armed = false
        private let haptic = UIImpactFeedbackGenerator(style: .medium)

        func attach(to scrollView: UIScrollView?) {
            guard let scrollView, scrollView !== self.scrollView else { return }
            self.scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(handlePan(_:)))
            self.scrollView = scrollView
            scrollView.panGestureRecognizer.addTarget(self, action: #selector(handlePan(_:)))
            // The field follows the list's offset through the spring back
            // too, not only while the finger is down.
            observation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
                MainActor.assumeIsolated { self?.offsetChanged(scrollView) }
            }
        }

        private func offsetChanged(_ scrollView: UIScrollView) {
            let value = isActive ? 0 : Self.overscroll(of: scrollView)
            guard value != lastOverscroll else { return }
            lastOverscroll = value
            report(value)
        }

        static func overscroll(of scrollView: UIScrollView) -> CGFloat {
            max(0, -(scrollView.contentOffset.y + scrollView.adjustedContentInset.top))
        }

        @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
            guard let scrollView, !isActive else {
                reportPull(0)
                return
            }
            let overscroll = Self.overscroll(of: scrollView)
            switch pan.state {
            case .began:
                armed = false
                haptic.prepare()
                reportPull(overscroll)
            case .changed:
                let nowArmed = overscroll >= PullToSearch.threshold
                if nowArmed && !armed {
                    if GeneralSettingsStore.load().hapticFeedbackEnabled { haptic.impactOccurred() }
                    haptic.prepare()
                }
                armed = nowArmed
                reportPull(overscroll)
            default:
                let fire = pan.state == .ended && armed
                armed = false
                reportPull(0)
                if fire { DispatchQueue.main.async { self.activate() } }
            }
        }
    }
}
#endif

/// Shared geometry of the two real resting search capsules (Settings'
/// "Search Settings", the thread's "Find in Comments"). See
/// `SettingsSearchFieldRow` for the measurements.
enum ApolloSearchCapsuleMetrics {
    static let height: CGFloat = 43
    static let sideMargin: CGFloat = 16
    /// Magnifier ink at x 30 = 14pt inside the capsule's x 16, plus 2pt for the
    /// glyph's own side bearing.
    static let leadingPad: CGFloat = 12
    /// Text ink at x 56.7.
    static let iconToText: CGFloat = 7.4
}

extension View {
    func apolloSearchCapsule(fill: Color, horizontalMargin: CGFloat = ApolloSearchCapsuleMetrics.sideMargin) -> some View {
        self
            .padding(.leading, ApolloSearchCapsuleMetrics.leadingPad)
            .padding(.trailing, 12)
            .frame(height: ApolloSearchCapsuleMetrics.height)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Capsule(style: .continuous).fill(fill))
            .padding(.horizontal, horizontalMargin)
    }
}
