import Foundation
import PhoebusCore
#if canImport(WebKit)
import WebKit
#endif

/// What Clear Cache empties.
@MainActor
enum CacheClearing {
    /// Everything downloaded or looked up for pictures and previews, on disk
    /// and in memory: the HTTP cache, the byte and decoded image caches, the
    /// avatar, account-age and subreddit-icon lookups, link previews and the
    /// memory copy of custom banners and icons (the saved photos stay; Clear
    /// Banners & Icons removes those).
    private static func clearArtworkAndPreviews() async {
        URLCache.shared.removeAllCachedResponses()
        await ImageCache.shared.removeAll()
        DecodedImageCache.shared.removeAll()
        await AvatarCache.shared.clear()
        await AccountAgeCache.shared.clear()
        await SubredditIconCache.shared.removeAll()
        await LinkPreviewCache.shared.clear()
        SubredditCustomArtStore.shared.clearMemory()
    }

    /// Stock Clear Cache: downloaded images, link previews, avatars and
    /// temporary files.
    static func clearAppCache() async {
        await clearArtworkAndPreviews()
        let temp = FileManager.default.temporaryDirectory
        for url in (try? FileManager.default.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Reborn's "Clear Tweak Caches": the pictures and previews, without the
    /// temporary files. Reborn's also covers badge books and banned-profile
    /// dismissals, which Phoebus doesn't have.
    static func clearTweakCaches() async {
        await clearArtworkAndPreviews()
    }

    /// Stock Clear Browser Cache: the in-app browser's cached pages (not
    /// its cookies or sign-ins).
    static func clearBrowserCache() async {
        #if canImport(WebKit)
        await WKWebsiteDataStore.default().removeData(
            ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache,
                      WKWebsiteDataTypeOfflineWebApplicationCache, WKWebsiteDataTypeFetchCache],
            modifiedSince: .distantPast)
        #endif
    }
}
