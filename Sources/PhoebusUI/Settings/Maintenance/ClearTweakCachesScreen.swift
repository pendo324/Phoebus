import SwiftUI
import PhoebusCore

/// Reborn's "Clear Tweak Caches" umbrella action and "Clear Custom Banners &
/// Icons".
///
/// Reborn's "Clear Tweak Caches?" alert says: "This removes cached profile
/// pictures, banners, link previews, badge books, and remembered banned-profile
/// dismissals." This clears every cache with a public way to clear it:
///  - `AvatarCache.clear()` (profile pictures)
///  - `LinkPreviewCache.clear()` (link previews)
///  - `URLCache.shared.removeAllCachedResponses()` (the HTTP disk cache behind
///    image/API responses, also cleared by `GeneralSettingsScreen`'s "Clear
///    Browser Cache")
///
/// The `internal` `SubredditIconCache` and `ImageCache` are session-only and
/// expose no `clear()`. There is no badge-book or banned-profile-dismissal
/// concept in Phoebus, so those parts of the description are N/A.
public struct ClearTweakCachesScreen: View {
    @State private var didClearTweakCaches = false
    @State private var didAcknowledgeBannersIcons = false

    public init() {}

    public var body: some View {
        List {
            Section {
                Button(didClearTweakCaches ? "Cleared" : "Clear Tweak Caches") {
                    Task {
                        await AvatarCache.shared.clear()
                        await LinkPreviewCache.shared.clear()
                        URLCache.shared.removeAllCachedResponses()
                        didClearTweakCaches = true
                    }
                }
                .disabled(didClearTweakCaches)
                .apolloSearchRow("Clear Tweak Caches", lastBeforeFooter: true)
            } header: {
                Text("Data")
                    .apolloSectionHeader()
            } footer: {
                Text("This removes cached profile pictures, link previews, and other locally cached artwork. Phoebus has no \"badge book\" trophy scraper or banned-profile-dismissal feature, so there is nothing to clear for those (real Apollo's version also clears those two).")
                    .apolloSectionFooter()
            }

            Section {
                Button(didAcknowledgeBannersIcons ? "Cleared" : "Clear Custom Banners & Icons") {
                    SubredditCustomArtStore.shared.clearAll()
                    didAcknowledgeBannersIcons = true
                }
                .disabled(didAcknowledgeBannersIcons)
                .apolloSearchRow("Clear Custom Banners & Icons", lastBeforeFooter: true)
            } footer: {
                Text("Locally saved custom subreddit banner and icon images will be removed. Official Reddit art will show again where available.")
                    .apolloSectionFooter()
            }
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle("Clear Tweak Caches")
    }
}
