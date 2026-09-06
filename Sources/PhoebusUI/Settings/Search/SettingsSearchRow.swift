import SwiftUI
import PhoebusCore

/// Scroll-to-and-flash for a settings row opened from search.
///
/// Real behaviour: after landing on the screen, scroll the target row
/// to the middle, then select and deselect it so it visibly flashes.
/// Without this, a row-level result on a long screen (General has 53
/// toggles) drops the user at the top with no indication of which row
/// they searched for, which is barely better than not searching.
///
/// Reborn does this against a `UITableView` by index path and
/// retries since the just-pushed table may not have laid out yet.
/// Here the row registers its own identity and the host scrolls to
/// it, so there is nothing to race.
struct SettingsSearchRowModifier: ViewModifier {
    let title: String
    @Environment(\.settingsSearchHighlightedRow) private var highlighted
    @State private var isFlashing = false

    private var isTarget: Bool { highlighted == title }

    func body(content: Content) -> some View {
        content
            .id(SettingsSearchRowID(title: title))
            // Deliberately an OVERLAY, not `.listRowBackground`.
            // Reborn flashes by asking the table view to select the
            // row, which uses the platform's own selected-row fill. The
            // SwiftUI equivalent, `.listRowBackground`, would mean
            // every settings row permanently declares its own
            // background - overriding whatever the active custom theme
            // paints, on all ~245 rows, for a one-second flash.
            .overlay {
                if isFlashing {
                    Color.apolloAccent
                        .opacity(0.28)
                        .allowsHitTesting(false)
                }
            }
            .task(id: isTarget) {
                guard isTarget else { return }
                // Real timings: the flash lands 0.45s after the scroll
                // starts and clears 0.9s later.
                try? await Task.sleep(nanoseconds: 450_000_000)
                withAnimation { isFlashing = true }
                try? await Task.sleep(nanoseconds: 900_000_000)
                withAnimation { isFlashing = false }
            }
    }
}

/// Namespaced scroll identity, so a row title can never collide with
/// some other `.id` value in the same list.
struct SettingsSearchRowID: Hashable {
    let title: String
}

/// Installs the scroll host a settings screen needs for search results
/// to land on a specific row.
///
/// A `ViewModifier` CAN wrap its content in a `ScrollViewReader`, which
/// is what makes this a one-line change per screen rather than an
/// invasive rewrite of 38 screen bodies.
struct SettingsSearchScrollHost: ViewModifier {
    @Environment(\.settingsSearchHighlightedRow) private var highlighted

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .task(id: highlighted) {
                    guard let highlighted else { return }
                    // One runloop hop so the list has rows to scroll to.
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    withAnimation {
                        proxy.scrollTo(SettingsSearchRowID(title: highlighted), anchor: .center)
                    }
                }
        }
    }
}

public extension View {
    /// Marks a settings row as a search target. Also applies Apollo's plain-row
    /// geometry, because this modifier sits on every Toggle / picker / link row
    /// of every settings screen.
    ///
    /// Geometry: title x 33, toggle trailing edge x 361, hairline x 32..361 at
    /// 0.33pt #333640, rows 52pt. `apolloSettingsRowInsets()` (icon rows) is the
    /// same 32/32 with the rule inset past the tile; a plain row's rule starts at
    /// the row's own leading edge.
    func apolloSearchRow(_ title: String) -> some View {
        modifier(SettingsSearchRowModifier(title: title))
            .apolloPlainSettingsRowInsets()
    }

    /// Plain (icon-less) settings row: 32pt insets, hairline at
    /// x 32..361. See `apolloSearchRow`.
    func apolloPlainSettingsRowInsets(rule: Bool = true) -> some View {
        modifier(ApolloSettingsRowChrome(rule: rule, ruleLeading: 0, breathing: false))
    }

    /// The last row of a section that has a FOOTER: the real table
    /// draws no rule there.
    func apolloSearchRow(_ title: String, lastBeforeFooter: Bool) -> some View {
        modifier(SettingsSearchRowModifier(title: title))
            .apolloPlainSettingsRowInsets(rule: !lastBeforeFooter)
    }

    /// Marks a settings screen's list as able to scroll to a search target.
    func apolloSettingsSearchScroll() -> some View {
        modifier(SettingsSearchScrollHost())
    }
}

/// Reborn's title + wrapping detail + trailing switch settings cell: body
/// title over a footnote detail, 3pt apart, 11pt above and below, the switch
/// centred vertically and the text wrapping short of it.
public struct SettingsDetailToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    var tint: Color? = nil

    public init(_ title: String, detail: String, isOn: Binding<Bool>, tint: Color? = nil) {
        self.title = title
        self.detail = detail
        _isOn = isOn
        self.tint = tint
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .apolloFont(size: ApolloSettingsRowMetrics.titlePointSize)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .tint(tint)
                .modifier(ApolloToggleTintOverride(tint: tint))
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}

/// A switch's own colour in place of the settings green, when it has one.
struct ApolloToggleTintOverride: ViewModifier {
    let tint: Color?

    func body(content: Content) -> some View {
        if let tint {
            content.environment(\.apolloToggleTint, tint)
        } else {
            content
        }
    }
}
