import SwiftUI
import PhoebusCore

/// Reborn's "User Profiles" screen (#1352): the Profile Layout entry, then a
/// live preview of a comment and reply with the Show User Profile Pictures and
/// Profile Picture Shape rows that used to sit under Interface. The shape key
/// is shared with the profile header, so the picker here also reshapes it.
public struct UserProfilesSettingsScreen: View {
    @Setting(ProfileLayoutSettingsStore.storage) private var profileLayout
    @Setting(GeneralSettingsStore.storage) private var settings

    public init() {}

    public var body: some View {
        List {
            layoutSection
            picturesSection
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle("User Profiles")
        .navigationBarTitleDisplayModeIfAvailable()
    }

    private var layoutSection: some View {
        Section {
            SettingsLink {
                ProfileLayoutSettingsScreen()
            } label: {
                ValueRow(title: "Profile Layout", value: profileLayout.style.displayName)
            }
            .apolloSearchRow("Profile Layout", lastBeforeFooter: true)
            .accessibilityIdentifier("userProfiles.layout")
        }
    }

    private var picturesSection: some View {
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
                .apolloSearchRow("Profile Picture Shape", lastBeforeFooter: true)
                .accessibilityIdentifier("userProfiles.avatarShape")
        } header: {
            Text("Preview")
                .apolloSectionHeader()
        } footer: {
            Text("Show user profile pictures beside usernames in posts, comments, messages, inbox rows, and moderator lists. Shape also applies to profile headers and the profile tab icon.")
                .apolloSectionFooter()
        }
    }
}
