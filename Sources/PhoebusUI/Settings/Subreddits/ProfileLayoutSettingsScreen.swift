import SwiftUI
import PhoebusCore

/// Reborn's "Profile Layout" screen: customizes `UserProfileScreen`'s header band.
/// See `ProfileLayoutSettings.swift`.
public struct ProfileLayoutSettingsScreen: View {
    @Setting(ProfileLayoutSettingsStore.storage) private var settings

    public init() {}

    public var body: some View {
        // The live profile preview card leads the screen.
        SettingsPreviewScreenLayout(screen: .profileLayout) {
            ProfileLayoutPreviewMock(settings: settings)
        } content: {
            Section {
                // "Profile Style" showing "Immersive", with a trailing chevron. Reborn's three
                // styles: Immersive / Compact / Native.
                ApolloSettingsPicker("Profile Style", selection: styleBinding,
                                 options: ProfileLayoutSettings.Style.allCases,
                                 display: { $0.displayName },
                                 showsChevron: true)
                    .apolloSearchRow("Profile Style")
                .accessibilityIdentifier("profileLayout.density")
                // Native has no Avatar row: with detailed profiles off the form is the style
                // alone.
                if settings.style != .native {
                ApolloSettingsPicker("Avatar", selection: avatarBinding,
                                 options: ProfileLayoutSettings.AvatarStyle.allCases.map { $0 },
                                 display: { $0.displayName },
                                 showsChevron: true)
                    .apolloSearchRow("Avatar")
                .accessibilityIdentifier("profileLayout.avatar")
                }
            }
            // The whole section goes for Native.
            if settings.style != .native {
            Section {
                Toggle("Banner", isOn: binding(\.showBanner))
                    .apolloSearchRow("Banner")
                    .accessibilityIdentifier("profileLayout.showBanner")
                Toggle("Stat Cards", isOn: binding(\.showStatCards))
                    .apolloSearchRow("Stat Cards")
                    .accessibilityIdentifier("profileLayout.showStatCards")
                Toggle("Social Links", isOn: binding(\.showSocialLinks))
                    .apolloSearchRow("Social Links")
                    .accessibilityIdentifier("profileLayout.showSocialLinks")
                Toggle("Badge Book", isOn: binding(\.badgeBookEnabled))
                    .apolloSearchRow("Badge Book")
                    .accessibilityIdentifier("profileLayout.badgeBookEnabled")
                Toggle("Follow & Message", isOn: binding(\.showActions))
                    .apolloSearchRow("Follow & Message")
                    .accessibilityIdentifier("profileLayout.showActions")
            } header: {
                Text("Show on Profiles")
                    .apolloPreviewScreenSectionHeader()
            }
            }
        }
        .apolloSettingsSearchScroll()
        .navigationTitle("Profile Layout")
    }

    private var styleBinding: Binding<ProfileLayoutSettings.Style> {
        Binding(
            get: { settings.style },
            set: {
                $settings.style.wrappedValue = $0
            }
        )
    }

    private var avatarBinding: Binding<ProfileLayoutSettings.AvatarStyle> {
        Binding(
            get: { settings.avatarStyle },
            set: {
                $settings.avatarStyle.wrappedValue = $0
            }
        )
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<ProfileLayoutSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: {
                $settings[dynamicMember: keyPath].wrappedValue = $0
            }
        )
    }
}
