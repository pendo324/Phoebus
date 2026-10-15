import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit
#endif

/// Appearance: how Phoebus looks outside the post rows: the theme and app
/// icon, text size, the tab bar and navigation bars, the keyboard and user
/// profile pictures. Reborn's Interface and User Profiles screens and the
/// text-size row of Apollo's Appearance screen are its sections; the post
/// rows are Posts.
public struct AppearanceSettingsScreen: View {
    @Setting(GeneralSettingsStore.storage) private var settings
    @Setting(AppearanceSettingsStore.storage) private var textSettings
    @Setting(ProfileLayoutSettingsStore.storage) private var profileLayout
    @State private var showingRestartAlert = false

    public init() {}

    public var body: some View {
        List {
            themeSection
            textSection
            tabBarSection
            barsNavigationSection
            keyboardSection
            profilesSection
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle(SettingsCategory.appearance.title)
        .navigationBarTitleDisplayModeIfAvailable()
    }

    // MARK: - Theme and Text

    private var themeSection: some View {
        Section {
            SettingsDrillDownRow(destination: .themeManager, value: themeSummary)
            SettingsDrillDownRow(destination: .appIcon, artwork: AppIconArtwork.current(), lastBeforeFooter: true)
        } header: {
            Text("Theme")
                .apolloSectionHeader()
        }
    }

    private var themeSummary: String {
        let theme = ThemeStore.load()
        return "\(theme.name) · \(theme.isDark ? "Dark" : "Light")"
    }

    private var textSection: some View {
        Section {
            Toggle("Use System Text Size", isOn: textBinding(\.useSystemTextSize))
                .apolloSearchRow("Use System Text Size")
                .accessibilityIdentifier("appearance.useSystemTextSize")
            // The A ——●—— A slider is always shown (greyed while the
            // switch is on), not hidden.
            HStack(spacing: 7) {
                Text("A").font(.footnote).foregroundStyle(.secondary)
                TextSizeSlider(value: textBinding(\.textSizeScale))
                    .accessibilityIdentifier("appearance.textSize")
                Text("A").font(.title3).foregroundStyle(.secondary)
            }
            .disabled(textSettings.useSystemTextSize)
            .apolloCardRowFill()
            SettingsDrillDownRow(destination: .textSizes, lastBeforeFooter: false)
        } header: {
            Text("Text")
                .apolloSectionHeader()
        }
    }

    private func textBinding<Value>(_ keyPath: WritableKeyPath<AppearanceSettings, Value>) -> Binding<Value> {
        Binding(
            get: { textSettings[keyPath: keyPath] },
            set: { $textSettings[dynamicMember: keyPath].wrappedValue = $0 }
        )
    }

    // MARK: - Tab Bar

    @ViewBuilder private var tabBarSection: some View {
        Section {
            // Reborn hides it on iPad under Liquid Glass, whose bars keep labels.
            if !(LiquidGlass.isEnabled && UIDevice.current.userInterfaceIdiom == .pad) {
                Toggle("Icon-Only Tab Bar", isOn: $settings.iconOnlyTabBar)
                    .apolloSearchRow("Icon-Only Tab Bar")
            }

            // `hideUsernameOnTabBar`. Hidden entirely while Icon-Only is on, since
            // that already implies no username text.
            if !settings.iconOnlyTabBar {
                Toggle("Hide Username on Tab Bar", isOn: $settings.hideUsernameOnTabBar)
                    .apolloSearchRow("Hide Username on Tab Bar")
            }

            // `hideBarsOnScroll` is a plain boolean; the Scroll Behavior picker below is
            // the one style choice `LiquidGlassTabBar` implements.
            Toggle("Hide Bars on Scroll", isOn: $settings.hideBarsOnScroll)
                    .apolloSearchRow("Hide Bars on Scroll")

            if settings.hideBarsOnScroll {
                ApolloSettingsPicker("Hide Style", selection: $settings.tabBarHideStyle,
                                 options: TabBarHideStyle.all,
                                 display: { TabBarHideStyle.titles[$0] },
                                 showsMenuChevrons: true)
                    .apolloSearchRow("Hide Style")
                Toggle("Hide Header on Scroll", isOn: $settings.hideTopBarOnScroll)
                    .apolloSearchRow("Hide Header on Scroll")
                    .accessibilityIdentifier("interface.hideTopBarOnScroll")
                ApolloSettingsPicker("Scroll Behavior", selection: $settings.classicTabBarScrollBehavior,
                                 options: [false, true],
                                 display: { $0 ? "Classic" : "Two-Gesture" },
                                 showsMenuChevrons: true)
                    .apolloSearchRow("Scroll Behavior")
            }

            // iPad idiom plus the Liquid-Glass toggle convention
            // (`enableLiquidGlassTabBar`).
            #if canImport(UIKit)
            if UIDevice.current.userInterfaceIdiom == .pad && settings.enableLiquidGlassTabBar {
                Toggle("Move Tab Bar to Bottom", isOn: $settings.ipadTabBarBottom)
                    .apolloSearchRow("Move Tab Bar to Bottom")
                    // Applies live; deferred a turn so the store has saved.
                    .onChange(of: settings.ipadTabBarBottom) { _, _ in
                        DispatchQueue.main.async { IPadTabBarBottom.refresh() }
                    }
            }
            #endif
            // Reborn #1075, Liquid Glass only, with its Restart Required alert.
            if settings.enableLiquidGlassTabBar {
                Toggle("Swipe Tab Bar to Navigate", isOn: $settings.tabBarSwipeNavigation)
                    .apolloSearchRow("Swipe Tab Bar to Navigate")
                    .onChange(of: settings.tabBarSwipeNavigation) { _, _ in
                        showingRestartAlert = true
                    }
                    .alert("Restart Required", isPresented: $showingRestartAlert) {
                        Button("Quit & Reopen") { exit(0) }
                        Button("Later", role: .cancel) {}
                    } message: {
                        Text("Quit and reopen Phoebus for this change to take effect.")
                    }
            }
        } header: {
            Text("Tab Bar")
                .apolloSectionHeader()
        } footer: {
            Text("After the tab bar reappears, Two-Gesture hides it on the second downward gesture; Classic hides it on the first. Both re-expand after 30 seconds of inactivity." + (settings.enableLiquidGlassTabBar ? "\n\nSwipe Tab Bar to Navigate disables the native drag-to-switch-tab gesture." : ""))
                    .apolloSectionFooter()
        }
    }

    // MARK: - Bars & Navigation

    @ViewBuilder private var barsNavigationSection: some View {
        Section {
            // Reborn "Return Button", default ON. Not Liquid-Glass-gated, unlike
            // the two rows below it.
            Toggle("Return Button", isOn: $settings.scrollReturnButton)
                    .apolloSearchRow("Return Button")

            // Reborn "Collapse Navigation Actions", Liquid-Glass-only, default OFF:
            // collapsing is opt-in and the action strip starts expanded.
            if settings.enableLiquidGlassTabBar {
                Toggle("Collapse Navigation Actions", isOn: $settings.collapseNavigationActions)
                    .apolloSearchRow("Collapse Navigation Actions")
            }

            // Liquid-Glass-only, and a sub-option of Navigation Actions
            // staying expanded (no gap to center once they collapse).
            // Cosmetically inert: there is no per-screen title-centering hook.
            if settings.enableLiquidGlassTabBar && !settings.collapseNavigationActions {
                Toggle("Center Title Between Buttons", isOn: $settings.centerTitleGapCentering)
                    .apolloSearchRow("Center Title Between Buttons")
            }

            // Reads/writes `HeaderStyleStore`. Liquid Glass only, as Reborn's (the edge effect is its glass).
            if LiquidGlass.isEnabled {
                ApolloSettingsPicker("Header Style", selection: headerStyleBinding,
                                     options: HeaderStyle.allCases.map { $0 },
                                     display: { $0.displayName },
                                     showsMenuChevrons: true)
                    .apolloSearchRow("Header Style", lastBeforeFooter: true)
            }
        } header: {
            Text("Bars & Navigation")
                .apolloSectionHeader()
        } footer: {
            Text("Return Button puts an arrow beside Back after a status bar tap scrolls to the top; tap it, the navigation bar, or the status bar again to go back to where you were. Liquid Glass is required for the remaining options.\n\nIn Liquid Glass, navigation titles stay centered unless expanded actions need room. Collapse Navigation Actions hides the actions behind an ellipsis until tapped; scrolling collapses them again. With it off, actions stay expanded. Center Title Between Buttons centers the title in the space between the back button and actions. Both options default to off. Header Style: Soft is the iOS 26 default; Hard is the iOS 27 default. Hidden removes the header edge effect entirely.")
                    .apolloSectionFooter()
        }
    }

    // MARK: - Keyboard

    private var keyboardSection: some View {
        Section {
            // Reborn "True Black Keyboard" (#1316).
            ApolloSettingsPicker("True Black Keyboard", selection: $settings.trueBlackKeyboardMode,
                                 options: TrueBlackKeyboardMode.allCases.map { $0 },
                                 display: { $0.displayName },
                                 showsChevron: true)
                .apolloSearchRow("True Black Keyboard", lastBeforeFooter: true)
                .accessibilityIdentifier("interface.trueBlackKeyboard")
        } header: {
            Text("Keyboard")
                .apolloSectionHeader()
        } footer: {
            Text("True Black Keyboard paints the keyboard background pure black in the chosen appearance (takes effect the next time the keyboard appears).")
                .apolloSectionFooter()
        }
    }

    // MARK: - Profiles

    /// Reborn's "User Profiles" screen (#1352): a live preview of a comment and
    /// reply with the Show User Profile Pictures and Profile Picture Shape rows
    /// that used to sit under Interface. The shape key is shared with the
    /// profile header, so the picker here also reshapes it.
    private var profilesSection: some View {
        Section {
            ProfilePicturesPreviewMock(showsPictures: settings.showUserProfilePictures,
                                       shape: profileLayout.avatarStyle)
                .listRowInsets(EdgeInsets())
                .accessibilityIdentifier("userProfiles.picturesPreview")
            Toggle("Show User Profile Pictures", isOn: $settings.showUserProfilePictures)
                .apolloSearchRow("Show User Profile Pictures")
                .accessibilityIdentifier("userProfiles.showPictures")
            ApolloSettingsPicker("Profile Picture Shape", selection: $profileLayout.avatarStyle,
                                 options: ProfileLayoutSettings.AvatarStyle.allCases.map { $0 },
                                 display: { $0.displayName },
                                 showsChevron: true)
                .apolloSearchRow("Profile Picture Shape")
                .accessibilityIdentifier("userProfiles.avatarShape")
            Toggle("Profile Picture Tab Icon", isOn: $settings.useProfileAvatarTabIcon)
                .apolloSearchRow("Profile Picture Tab Icon")
            SettingsDrillDownRow(destination: .profileLayout, value: profileLayout.style.displayName,
                                 lastBeforeFooter: true)
        } header: {
            Text("Profiles")
                .apolloSectionHeader()
        } footer: {
            Text("Show user profile pictures beside usernames in posts, comments, messages, inbox rows, and moderator lists. Shape also applies to profile headers and the profile tab icon.")
                .apolloSectionFooter()
        }
    }

    /// `HeaderStyleStore` is a separate small persistence store; this
    /// binding reads/writes it directly rather than duplicating it into
    /// `GeneralSettings`.
    private var headerStyleBinding: Binding<HeaderStyle> {
        Binding(
            get: { HeaderStyle(rawValue: headerStyleRaw) ?? .automatic },
            set: { headerStyleRaw = $0.rawValue }
        )
    }

    @AppStorage(HeaderStyleStore.defaultsKey) private var headerStyleRaw = HeaderStyle.automatic.rawValue
}

/// Apollo's stepped text-size slider: a 1pt track between the first and last
/// of seven sizes, a 1pt tick hanging below it at each size, no coloured fill,
/// and a white capsule thumb (#DADADA track and #B5B5B5 ticks on light, thumb
/// 37x24).
private struct TextSizeSlider: View {
    @Binding var value: Double
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    private static let sizes = AppearanceTextSizeStep.sizes
    private static let thumb = CGSize(width: 37, height: 24)

    private var index: Int {
        Self.sizes.enumerated().min { abs($0.element - value) < abs($1.element - value) }?.offset ?? 0
    }

    var body: some View {
        GeometryReader { geometry in
            let inset = Self.thumb.width / 2
            let span = max(1, geometry.size.width - inset * 2)
            let step = span / CGFloat(Self.sizes.count - 1)
            let midY = geometry.size.height / 2
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(trackColor)
                    .frame(width: span, height: 1)
                    .offset(x: inset, y: midY - 0.5)
                ForEach(Self.sizes.indices, id: \.self) { tick in
                    Rectangle()
                        .fill(tickColor)
                        .frame(width: 1, height: 6.5)
                        .offset(x: inset + CGFloat(tick) * step - 0.5, y: midY - 0.5)
                }
                Capsule()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 1)
                    .frame(width: Self.thumb.width, height: Self.thumb.height)
                    .offset(x: CGFloat(index) * step, y: midY - Self.thumb.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard isEnabled else { return }
                        let raw = ((drag.location.x - inset) / step).rounded()
                        let next = Self.sizes[min(max(Int(raw), 0), Self.sizes.count - 1)]
                        if next != value { value = next }
                    }
            )
        }
        .frame(height: 32)
        .accessibilityElement()
        .accessibilityLabel("Text Size")
        .accessibilityValue("\(index + 1) of \(Self.sizes.count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = Self.sizes[min(index + 1, Self.sizes.count - 1)]
            case .decrement: value = Self.sizes[max(index - 1, 0)]
            @unknown default: break
            }
        }
    }

    private var trackColor: Color {
        Color(hex: colorScheme == .dark ? ApolloSettingsRowMetrics.separatorColorHex : "DADADA")
    }

    private var tickColor: Color {
        Color(hex: colorScheme == .dark ? ApolloSettingsRowMetrics.detailColorHex : "B5B5B5")
    }
}
