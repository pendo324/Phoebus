import SwiftUI
import PhoebusCore

/// Apollo's flat, full-bleed list appearance. iOS 26 wraps grouped `List`
/// sections in rounded Liquid Glass cards on an inset background, but
/// Apollo's rows are full-bleed on a flat background with a hairline
/// separator inset to the text.
///
/// This opts out of the card per list rather than app-wide via
/// `UIDesignRequiresCompatibility`, which would also force every `UIMenu`
/// into the legacy appearance. `.plain` (not just
/// `.scrollContentBackground(.hidden)`) is what removes the card, since the
/// card is part of the inset-grouped style; `.plain` also collapses section
/// gaps, restored via `listSectionSpacing`.
public extension View {
    /// Flat, full-bleed rows on the app's own background.
    ///
    /// Apply to a `List` or `Form` that should look like Apollo's
    /// settings and content lists.
    /// - Parameter sectionSpacing: the gap between sections. It is a parameter
    ///   because the inner environment value wins, so a caller's own
    ///   `.listSectionSpacing` after this modifier is ignored.
    func apolloFlatListAppearance(sectionSpacing: CGFloat = 20) -> some View {
        self
            .listStyle(.plain)
            // `.plain` drops the card fill but still paints its own background; hide
            // it so the screen's theme shows through.
            .scrollContentBackground(.hidden)
            .apolloStockSurface()
            .apolloListSectionSpacing(20)
            .modifier(ApolloTabBarClearance())
            // `.menu` keeps tap-to-choose while rendering picker values as plain grey
            // text instead of the accent color.
            .pickerStyle(.menu)
            // Toggles are a constant green in Apollo, not the theme accent (except
            // "Follow New Live Comments", which sets its own blue tint). Only the
            // switches: a list-wide green tint turns every row icon green.
            .toggleStyle(ApolloSwitchToggleStyle())
            // `.listStyle(.plain)` drops the grouped style's small grey footer
            // treatment, so footers use `.apolloSectionFooter()` at their call sites.
            .modifier(ApolloScaledMinRowHeight(base: Self.settingsRowHeight))
    }

    /// A settings screen's list. Apollo's settings are an inset-grouped table:
    /// white cards on a #F2F3F7 page in light mode, and the Pure Black tier's
    /// card on its page in dark mode. Under PURER Black both are black, which
    /// reads as a flat list.
    func apolloSettingsListAppearance(sectionSpacing: CGFloat = 20) -> some View {
        modifier(ApolloSettingsListStyle(sectionSpacing: sectionSpacing))
    }

    /// Apollo's row pitch: 52pt, holding a 29pt icon.
    static var settingsRowHeight: CGFloat { 52 }

    /// The rest of the row geometry lives in `ApolloSettingsRowMetrics`.

    /// The vertical inset that turns SwiftUI's stock row into the 52pt one.
    static var settingsRowVerticalInset: CGFloat { 5 }
}

/// Whether rows sit on cards: rows then take their insets from the
/// card's edge, 16pt in from the screen's.
private struct ApolloCardedListKey: EnvironmentKey {
    static let defaultValue = false
}

/// The card fill rows paint, or nil for the system's own.
private struct ApolloCardColorKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    var apolloCardedList: Bool {
        get { self[ApolloCardedListKey.self] }
        set { self[ApolloCardedListKey.self] = newValue }
    }

    var apolloCardColor: Color? {
        get { self[ApolloCardColorKey.self] }
        set { self[ApolloCardColorKey.self] = newValue }
    }
}

/// The last rows clear the floating tab bar. A section footer pulled
/// up by a negative bottom pad ends below the list's content, and
/// without this margin it scrolls no further than under the bar.
struct ApolloTabBarClearance: ViewModifier {
    var bottom: CGFloat = 24

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.contentMargins(.bottom, bottom, for: .scrollContent)
        } else {
            content
        }
    }
}

enum ApolloCardMetrics {
    /// Card x 16..377 on a 393pt screen.
    static let margin: CGFloat = 16
    static let pageLightHex = "F2F3F7"
    static let separatorLightHex = "EEEEEF"
}

/// Section header and footer text sits at the rows' 32pt either way,
/// so on a card it gives back the card's margin.
struct ApolloSectionTextInset: ViewModifier {
    @Environment(\.apolloCardedList) private var carded
    let flatLeading: CGFloat
    let flatTrailing: CGFloat

    func body(content: Content) -> some View {
        let shift = carded ? ApolloCardMetrics.margin : 0
        content
            .padding(.leading, flatLeading - shift)
            .padding(.trailing, max(0, flatTrailing - shift))
    }
}

struct ApolloSettingsListStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.apolloTheme) private var apolloTheme
    @AppStorage("com.pendo324.Phoebus.pureBlackSettings") private var storedPureBlack: Data = Data()
    let sectionSpacing: CGFloat

    func body(content: Content) -> some View {
        let pureBlack = (try? JSONDecoder().decode(PureBlackSettings.self, from: storedPureBlack)) ?? .default
        let dark = colorScheme == .dark
        let themedCard = apolloTheme.color(.secondaryBackground)
        let card = themedCard ?? (dark ? Color(hex: pureBlack.darkCardHex) : nil)
        let page = apolloTheme.color(.background)
            ?? Color(hex: dark ? pureBlack.darkPageHex : ApolloCardMetrics.pageLightHex)
        // Under PURER Black the card is the page's black, so this reads flat; it
        // stays a grouped table so headers scroll with their rows instead of
        // pinning over them, as Apollo's do.
        content
            .listStyle(.insetGrouped)
            // Apollo's settings titles are always inline; left automatic, iOS can draw
            // a large title over the first section.
            .navigationBarTitleDisplayModeIfAvailable()
            .scrollContentBackground(.hidden)
            .background(page.ignoresSafeArea())
            .apolloListSectionSpacing(sectionSpacing)
            .modifier(ApolloTabBarClearance())
            .environment(\.apolloCardColor, card)
            .pickerStyle(.menu)
            // A grouped table tints a button row's label; Apollo's rows read in its
            // title colour (#D0D1D6 under Pure Black). Switches keep their green.
            .tint(Color.apolloPrimaryText(colorScheme: colorScheme))
            .foregroundStyle(Color.apolloPrimaryText(colorScheme: colorScheme))
            .toggleStyle(ApolloSwitchToggleStyle())
            .modifier(ApolloScaledMinRowHeight(base: 52))
            .environment(\.apolloCardedList, true)
    }
}

/// Apollo's switches are a constant green (a few rows pick their own via
/// `apolloToggleTint`), whatever the list's tint.
struct ApolloSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        ApolloSwitch(configuration: configuration)
    }
}

private struct ApolloSwitch: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.apolloToggleTint) private var tint

    var body: some View {
        Toggle(configuration).tint(tint)
    }
}

private struct ApolloToggleTintKey: EnvironmentKey {
    static let defaultValue = Color(red: 103 / 255, green: 206 / 255, blue: 103 / 255)
}

extension EnvironmentValues {
    var apolloToggleTint: Color {
        get { self[ApolloToggleTintKey.self] }
        set { self[ApolloToggleTintKey.self] = newValue }
    }
}

/// A settings row's 32pt text inset from the screen edge, and its
/// hand-drawn rule.
struct ApolloSettingsRowChrome: ViewModifier {
    @Environment(\.apolloCardedList) private var carded
    @Environment(\.apolloCardColor) private var cardColor
    @Environment(\.colorScheme) private var colorScheme
    let rule: Bool
    let ruleLeading: CGFloat
    let breathing: Bool

    func body(content: Content) -> some View {
        let inset = carded ? 32 - ApolloCardMetrics.margin : 32
        let row = content
            .modifier(ApolloSettingsRowVerticalBreathing(enabled: breathing))
            .listRowInsets(EdgeInsets(top: 0, leading: inset, bottom: 0, trailing: inset))
            .frame(maxWidth: .infinity, minHeight: breathing ? nil : 52, alignment: .leading)
        if carded {
            // On a card the system rule is kept: it already stops at a section's last
            // row, which a hand-drawn one cannot know.
            row
                .listRowSeparator(rule ? .automatic : .hidden, edges: .bottom)
                .listRowSeparator(.hidden, edges: .top)
                .listRowSeparatorTint(Color(hex: colorScheme == .dark
                    ? ApolloSettingsRowMetrics.separatorColorHex : ApolloCardMetrics.separatorLightHex))
                .modifier(ApolloCardRowBackground(color: cardColor))
                .alignmentGuide(.listRowSeparatorLeading) { _ in ruleLeading }
                .alignmentGuide(.listRowSeparatorTrailing) { $0.width }
        } else {
            row
                .listRowSeparator(rule ? .automatic : .hidden, edges: .bottom)
                .listRowSeparator(.hidden, edges: .top)
                .listRowSeparatorTint(Color(hex: ApolloSettingsRowMetrics.separatorColorHex))
                .listSectionSeparator(.hidden)
                .alignmentGuide(.listRowSeparatorLeading) { _ in ruleLeading }
                .alignmentGuide(.listRowSeparatorTrailing) { $0.width }
        }
    }
}

/// A list on a theme with its own surfaces shows that theme's card
/// colour behind its rows; stock themes keep the list's own background.
struct ApolloThemedListBackground: ViewModifier {
    @Environment(\.apolloTheme) private var apolloTheme

    func body(content: Content) -> some View {
        if let card = apolloTheme.color(.secondaryBackground) {
            content
                .scrollContentBackground(.hidden)
                .background(card.ignoresSafeArea())
        } else {
            content
        }
    }
}

/// Leaves the system card fill alone when there is no override, so a
/// row's own `.listRowBackground` still wins.
struct ApolloCardRowBackground: ViewModifier {
    let color: Color?

    func body(content: Content) -> some View {
        if let color {
            content.listRowBackground(color)
        } else {
            content
        }
    }
}

/// A custom row that keeps its own insets but takes the card's fill:
/// without it a row shows the system's grey cell, which under PURER
/// Black stands out from the black card.
struct ApolloCardRowFill: ViewModifier {
    @Environment(\.apolloCardColor) private var cardColor

    func body(content: Content) -> some View {
        content.modifier(ApolloCardRowBackground(color: cardColor))
    }
}

extension View {
    func apolloCardRowFill() -> some View { modifier(ApolloCardRowFill()) }
}

/// A row that spans the screen rather than the card, such as the
/// pinned search field.
struct ApolloFullBleedRowInsets: ViewModifier {
    @Environment(\.apolloCardedList) private var carded
    var top: CGFloat = 0
    var bottom: CGFloat = 0

    func body(content: Content) -> some View {
        let edge = carded ? -ApolloCardMetrics.margin : 0
        content.listRowInsets(EdgeInsets(top: top, leading: edge, bottom: bottom, trailing: edge))
    }
}

/// Apollo's settings rule: 1pt, #333640 on dark, #CCCCCC on light.
struct ApolloSettingsSeparator: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(Color(hex: colorScheme == .dark ? ApolloSettingsRowMetrics.separatorColorHex : ApolloCardMetrics.separatorLightHex))
            .frame(height: ApolloSettingsRowMetrics.separatorHeight)
    }
}

/// `listSectionSpacing` is iOS 17+, and this package declares a lower floor
/// for its non-app targets.
extension View {
    @ViewBuilder
    func apolloListSectionSpacing(_ spacing: CGFloat) -> some View {
        if #available(iOS 17.0, *) {
            self.listSectionSpacing(spacing)
        } else {
            self
        }
    }

    /// The pinned search field's own "section" must butt against the first real
    /// one: the 18pt gap under it is carried by the field row's bottom inset,
    /// and the list's own 20pt section spacing would add to it.
    @ViewBuilder
    func apolloListSectionSpacingZero() -> some View {
        if #available(iOS 17.0, *) {
            self.listSectionSpacing(0)
        } else {
            self
        }
    }
}

/// Row-level half of `apolloFlatListAppearance`.
///
/// Separate because SwiftUI applies row background and insets per row, not
/// on the list: a list-level modifier cannot reach them.
public extension View {
    /// Hides the system row separator. Must be applied per row:
    /// `.listRowSeparator(.hidden)` on the list does not propagate.
    func apolloNoRowSeparator() -> some View {
        listRowSeparator(.hidden)
    }

    /// Apollo's Subreddits-list row metrics (60pt row for a 28pt icon).
    /// Applied on the row itself, not inside its content, since
    /// `.listRowInsets` only takes effect on a direct child of the `List`.
    func apolloSubredditRowMetrics() -> some View {
        listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 16))
            .frame(minHeight: 48)
    }

    /// Apollo's section-footer text style: small grey caption. Under
    /// `.listStyle(.plain)` a bare `Section(footer:)` renders at body
    /// size in the primary color instead, so this styles it explicitly.
    func apolloSettingsRowInsets(rule: Bool = true) -> some View {
        // Row title leads at 76pt (32pt inset + 29pt icon + gap); `rule: false`
        // for a section's last row when a footer follows. The rule starts past the
        // tile, relative to the row's own inset rather than the screen edge.
        modifier(ApolloSettingsRowChrome(rule: rule, ruleLeading: 44, breathing: true))
    }

    /// - Parameters:
    ///   - topGap/bottomGap: vertical pulls around the footer.
    ///     Defaults are safe for a plain list with system row insets;
    ///     the hub passes its own tuned values via `apolloHubSectionFooter()`.
    func apolloSectionFooter(
        topGap: CGFloat = 4,
        bottomGap: CGFloat = -19
    ) -> some View {
        apolloFont(size: ApolloSettingsRowMetrics.footerPointSize, relativeTo: .footnote)
            .foregroundStyle(Color.apolloSettingsSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(ApolloSectionTextInset(flatLeading: 16, flatTrailing: 16))
            .padding(.top, topGap)
            .padding(.bottom, bottomGap)
            // The plain list draws a full-width separator under a footer when a
            // header-less section follows; Apollo's tables draw nothing there.
            .listRowSeparator(.hidden)
    }


    /// Apollo's settings section header style: 18pt semibold in #8D8D92.
    /// - Parameters:
    ///   - pointSize: 18 on the hub; 17 on preview-card screens.
    ///   - topGap/bottomGap: as for `apolloSectionFooter`.
    func apolloSectionHeader(
        pointSize: CGFloat = ApolloSettingsRowMetrics.headerPointSize,
        topGap: CGFloat = ApolloSettingsRowMetrics.previewScreenHeaderTopGap,
        bottomGap: CGFloat = ApolloSettingsRowMetrics.previewScreenHeaderBottomGap,
        textDrop: CGFloat = 0
    ) -> some View {
        font(.system(size: pointSize, weight: .semibold))
            .foregroundStyle(Color.apolloSettingsSecondary)
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The plain list clamps a negative bottom pad at its own header inset, so
            // a tighter header-to-row gap pulls the header up with the top pad and
            // draws its glyphs back down by `textDrop`.
            .frame(height: textDrop > 0 ? 1 : nil, alignment: .top)
            .offset(y: textDrop)
            .modifier(ApolloSectionTextInset(flatLeading: ApolloSettingsRowMetrics.headerLeading - 16, flatTrailing: 0))
            .padding(.bottom, bottomGap)
            .padding(.top, topGap)
    }

    /// The preview-card family's section header, using the plain
    /// list's own gaps rather than the hub's tuned pulls.
    func apolloHubSectionHeader() -> some View {
        apolloSectionHeader(topGap: -21, bottomGap: -17,
                            textDrop: 8)
    }

    /// The plain list floors the footer-to-next-header gap, so every hub
    /// section after the first sits a few points below Apollo's.
    func apolloHubSectionFooter() -> some View {
        apolloSectionFooter(topGap: 0, bottomGap: -10)
    }

    func apolloPreviewScreenSectionHeader() -> some View {
        apolloSectionHeader(
            pointSize: ApolloSettingsRowMetrics.previewScreenHeaderPointSize,
            topGap: ApolloSettingsRowMetrics.previewScreenHeaderTopGap,
            bottomGap: ApolloSettingsRowMetrics.previewScreenHeaderBottomGap
        )
    }

    /// The preview-card family's section footer.
    func apolloPreviewScreenSectionFooter() -> some View {
        apolloSectionFooter(
            topGap: ApolloSettingsRowMetrics.previewScreenFooterTopGap,
            bottomGap: ApolloSettingsRowMetrics.previewScreenFooterBottomGap
        )
    }

    func apolloFlatListRow(insets: EdgeInsets? = nil) -> some View {
        listRowBackground(Color.clear)
            .listRowInsets(insets ?? EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }
}

/// Reborn's Liquid Glass navigation bar draws its buttons, back chevron and
/// title menu in the label colour rather than the theme accent (white "+",
/// "Edit", "Home ⌄", sort and "•••"). Applied to a toolbar item's content;
/// earlier iOS keeps the accent-tinted bar.
struct ApolloGlassBarTint: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tint(Color.primary).foregroundStyle(Color.primary)
        } else {
            content
        }
    }
}

public extension View {
    func apolloGlassBarTint() -> some View { modifier(ApolloGlassBarTint()) }
}
