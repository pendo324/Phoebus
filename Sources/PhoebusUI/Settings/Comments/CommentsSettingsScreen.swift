import SwiftUI
import PhoebusCore

/// Reborn's Comments settings: Collapse Pinned Comments, Follow New
/// Live Comments and Deleted Comments in one untitled section with a
/// footer.
public struct CommentsSettingsScreen: View {
    @Setting(GeneralSettingsStore.storage) private var settings

    public init() {}

    public var body: some View {
        List {
            Section {
                Toggle("Collapse Pinned Comments", isOn: $settings.autoCollapsePinnedComments)
                    .apolloSearchRow("Collapse Pinned Comments")
                // `.apolloSearchRow` is `listRowInsets`-based, so it goes on the row
                // (this VStack), not on the inner `Toggle`.
                // The one blue switch in the set: RGB(75,150,247); every other toggle
                // is green RGB(103,206,103).
                SettingsDetailToggle("Follow New Live Comments",
                                     detail: "During Live Update comment sort, keep the newest at the top and show a jump button when you've scrolled down.",
                                     isOn: $settings.liveCommentsFollow,
                                     tint: Color(red: 75 / 255, green: 150 / 255, blue: 247 / 255))
                .apolloSearchRow("Follow New Live Comments")
                SettingsLink {
                    DeletedCommentsSettingsScreen()
                } label: {
                    Text("Deleted Comments")
                }
                .apolloSearchRow("Deleted Comments", lastBeforeFooter: true)
            } footer: {
                Text("Options for reading comment threads, including viewing removed comments.")
                    .apolloSectionFooter()
            }
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle("Comments")
        .navigationBarTitleDisplayModeIfAvailable()
    }
}
