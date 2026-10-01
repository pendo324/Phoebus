import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit
#endif

/// Reborn's Interface settings screen: tab bar section + display/
/// navigation section. Reads/writes the same `GeneralSettingsStore`
/// fields `GeneralSettingsScreen` uses, rather than a second copy.
public struct InterfaceSettingsScreen: View {
    @Setting(GeneralSettingsStore.storage) private var settings

    @Setting(ProfileLayoutSettingsStore.storage) private var profileLayout
    @State private var showingRestartAlert = false

    public init() {}

    private var pictureShapeBinding: Binding<ProfileLayoutSettings.AvatarStyle> {
        Binding(
            get: { profileLayout.avatarStyle },
            set: {
                $profileLayout.avatarStyle.wrappedValue = $0
            }
        )
    }

    public var body: some View {
        List {
            tabBarSection
            displayNavigationSection
            menusSection
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle("Interface")
        .alert("Restart Required", isPresented: $showingRestartAlert) {
            Button("Quit & Reopen") { exit(0) }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Quit and reopen Phoebus for this change to take effect.")
        }
    }

    // MARK: - Tab Bar

    @ViewBuilder private var tabBarSection: some View {
        Section {
            Toggle("Profile Picture Tab Icon", isOn: $settings.useProfileAvatarTabIcon)
                    .apolloSearchRow("Profile Picture Tab Icon")

            // Reborn hides it on iPad under Liquid Glass, whose bars keep labels.
            if !(LiquidGlass.isEnabled && UIDevice.current.userInterfaceIdiom == .pad) {
                Toggle("Icon-Only Tab Bar", isOn: $settings.iconOnlyTabBar)
                    .apolloSearchRow("Icon-Only Tab Bar")
            }

            // `hideUsernameOnTabBar` is shared with General ->
            // Navigation & Sharing. Hidden entirely while Icon-Only is
            // on, since that already implies no username text.
            if !settings.iconOnlyTabBar {
                Toggle("Hide Username on Tab Bar", isOn: $settings.hideUsernameOnTabBar)
                    .apolloSearchRow("Hide Username on Tab Bar")
            }

            // `hideBarsOnScroll` is shared with General -> Navigation & Sharing.
            // It is a plain boolean; the Scroll Behavior picker below is the one
            // style choice `LiquidGlassTabBar` implements.
            Toggle("Hide Bars on Scroll", isOn: $settings.hideBarsOnScroll)
                    .apolloSearchRow("Hide Bars on Scroll")

            if settings.hideBarsOnScroll {
                ApolloSettingsPicker("Hide Style", selection: $settings.tabBarHideStyle,
                                 options: [0, 1, 2, 3],
                                 display: { ["Left", "Right", "Fade", "Down"][$0] },
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
            }
            // Reborn #1150: last row of Tab Bar.
            SettingsLink {
                SettingsShortcutsScreen()
            } label: {
                Text("Settings Shortcuts")
            }
            .apolloSearchRow("Settings Shortcuts", lastBeforeFooter: true)
        } header: {
            Text("Tab Bar")
                .apolloSectionHeader()
        } footer: {
            Text("After the tab bar reappears, Two-Gesture hides it on the second downward gesture; Classic hides it on the first. Both re-expand after 30 seconds of inactivity." + (settings.enableLiquidGlassTabBar ? "\n\nSwipe Tab Bar to Navigate disables the native drag-to-switch-tab gesture." : ""))
                    .apolloSectionFooter()
        }
    }

    // MARK: - Menus

    /// Reborn #1131: Interface → Menus → Action Menus.
    @ViewBuilder private var menusSection: some View {
        Section {
            SettingsLink {
                ActionMenusSettingsScreen()
            } label: {
                HStack {
                    Text("Action Menus")
                    Spacer()
                    Text(ActionMenuLayoutStore.interfaceSummary())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .apolloSearchRow("Action Menus", lastBeforeFooter: true)
        } header: {
            Text("Menus")
                .apolloSectionHeader()
        } footer: {
            Text("Reorder or hide the items in the ••• menus of feeds, posts and comments, and in the moderator menus.")
                .apolloSectionFooter()
        }
    }

    // MARK: - Display & Navigation

    @ViewBuilder private var displayNavigationSection: some View {
        Section {
            // Shared with General -> Post Rows.
            Toggle("Show User Profile Pictures", isOn: $settings.showUserProfilePictures)
                    .apolloSearchRow("Show User Profile Pictures")

            // Reborn #1136: shares the Profile Layout avatar key, so
            // changing it here also changes the profile header.
            ApolloSettingsPicker("Profile Picture Shape", selection: pictureShapeBinding,
                                 options: ProfileLayoutSettings.AvatarStyle.allCases.map { $0 },
                                 display: { $0.displayName },
                                 showsChevron: true)
                .apolloSearchRow("Profile Picture Shape")
                .accessibilityIdentifier("interface.avatarShape")

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

            // Also available on `AppearanceSettingsScreen`; reads/writes the same
            // `HeaderStyleStore`.
            // Liquid Glass only, as Reborn's (the edge effect is its glass).
            if LiquidGlass.isEnabled {
                ApolloSettingsPicker("Header Style", selection: headerStyleBinding,
                                     options: HeaderStyle.allCases.map { $0 },
                                     display: { $0.displayName },
                                     showsMenuChevrons: true)
                    .apolloSearchRow("Header Style", lastBeforeFooter: true)
            }
        } header: {
            Text("Display & Navigation")
                .apolloSectionHeader()
        } footer: {
            Text("User Profile Pictures adds avatars beside usernames in posts, comments, messages, inbox rows, and moderator lists. Return Button puts an arrow beside Back after a status bar tap scrolls to the top; tap it, the navigation bar, or the status bar again to go back to where you were. Liquid Glass is required for the remaining options.\n\nIn Liquid Glass, navigation titles stay centered unless expanded actions need room. Collapse Navigation Actions hides the actions behind an ellipsis until tapped; scrolling collapses them again. With it off, actions stay expanded. Center Title Between Buttons centers the title in the space between the back button and actions. Both options default to off. Header Style: Soft is the iOS 26 default; Hard is the iOS 27 default. Hidden removes the header edge effect entirely.")
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
