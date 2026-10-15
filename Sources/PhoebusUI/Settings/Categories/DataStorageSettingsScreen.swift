import SwiftUI
import PhoebusCore

/// Data & Storage: backups and restores, the posts you save, and what
/// Phoebus keeps on the device. Apollo's Cache section and Saved rows,
/// Reborn's Automatic Backups, Backup & Restore, Clear Tweak Caches and Clear
/// Custom Banners & Icons are its sections; managing the backup files, saved
/// categories and Imgur uploads are drill-downs because each is a list.
public struct DataStorageSettingsScreen: View {
    @Setting(GeneralSettingsStore.storage) private var settings
    @Setting(LocalSavedSettings.self) private var localSaved
    /// The Clear Banners & Icons action waiting for its confirmation.
    @State private var confirmation: SettingsCategoryAction?
    @State private var choosingCacheToClear = false
    @State private var didClearCache = false

    public init() {}

    public var body: some View {
        List {
            AutomaticBackupSections()
            BackupRestoreSections(importURL: nil, importOnly: false)
            savedItemsSection
            storageSection
            uploadsSection
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle(SettingsCategory.dataStorage.title)
        .navigationBarTitleDisplayModeIfAvailable()
        .apolloSettingsActionConfirmation($confirmation) { action in
            action.perform()
        }
    }

    private var savedItemsSection: some View {
        Section {
            Toggle("Upvote on Save", isOn: $settings.upvoteOnSave)
                .apolloSearchRow("Upvote on Save")
            Toggle("Allow Save Categories", isOn: $settings.allowSaveCategories)
                .apolloSearchRow("Allow Save Categories")
            // Phoebus-only Local Saved: see `LocalSavedStore`.
            Toggle("Keep Local Copies of Saved Items", isOn: $localSaved.keepLocalCopies)
                .accessibilityIdentifier("settings.general.keepLocalCopiesOfSavedItems")
                .apolloSearchRow("Keep Local Copies of Saved Items")
            SettingsDrillDownRow(destination: .savedCategories, lastBeforeFooter: false)
        } header: {
            Text("Saved Items")
                .apolloSectionHeader()
        }
    }

    /// One Clear Cache row that offers every cache Phoebus can empty: stock's
    /// app cache and in-app browser cache, and Reborn's artwork and previews.
    private var storageSection: some View {
        Section {
            Button {
                choosingCacheToClear = true
            } label: {
                Text(didClearCache ? "Cache Cleared" : "Clear Cache")
                    .foregroundStyle(Color.apolloAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("settings.clearCache")
            // search: item "Clear Browser Cache"; item "Clear Caches"
            .apolloSearchRow("Clear Cache")
            .confirmationDialog("Clear Cache", isPresented: $choosingCacheToClear, titleVisibility: .visible) {
                Button("Clear Cache") { Task { await CacheClearing.clearAppCache(); didClearCache = true } }
                Button("Clear Artwork & Previews") { Task { await CacheClearing.clearTweakCaches(); didClearCache = true } }
                Button("Clear Browser Cache") { Task { await CacheClearing.clearBrowserCache(); didClearCache = true } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Clear Cache removes downloaded images, link previews, profile pictures and temporary files. Artwork & Previews removes only the pictures and previews; Browser Cache only the in-app browser's cached pages, not its sign-ins.")
            }
            // Reborn's "Clear Custom Banners & Icons".
            Button("Clear Banners & Icons") {
                confirmation = SettingsCategoryAction(
                    id: "clearBanners",
                    title: "Clear Custom Banners & Icons?",
                    message: "Locally saved custom subreddit banner and icon images will be removed. "
                        + "Official Reddit art will show again where available.",
                    confirmTitle: "Clear",
                    perform: { SubredditCustomArtStore.shared.clearAll() })
            }
            .foregroundStyle(Color.apolloAccent)
            .accessibilityIdentifier("settings.clearBanners")
            .apolloSearchRow("Clear Banners & Icons")
            SettingsDrillDownRow(destination: .cacheExplainer, lastBeforeFooter: true)
        } header: {
            Text("Storage")
                .apolloSectionHeader()
        } footer: {
            Text("Maximum of around 200 MB.")
                .apolloSectionFooter()
        }
    }

    private var uploadsSection: some View {
        Section {
            SettingsDrillDownRow(destination: .deleteImgurUploads, lastBeforeFooter: true)
        } header: {
            Text("Uploads")
                .apolloSectionHeader()
        }
    }
}
