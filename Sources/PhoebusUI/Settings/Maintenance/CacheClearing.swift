import Foundation
import PhoebusCore
#if canImport(WebKit)
import WebKit
#endif

/// What Clear Cache empties.
@MainActor
enum CacheClearing {
    /// Stock Clear Cache: downloaded images, link previews, avatars and
    /// temporary files.
    static func clearAppCache() async {
        URLCache.shared.removeAllCachedResponses()
        await ImageCache.shared.removeAll()
        DecodedImageCache.shared.removeAll()
        await AvatarCache.shared.clear()
        await LinkPreviewCache.shared.clear()
        let temp = FileManager.default.temporaryDirectory
        for url in (try? FileManager.default.contentsOfDirectory(at: temp, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Reborn's "Clear Tweak Caches": every cache with a public way to
    /// clear it. Reborn's also covers badge books and banned-profile
    /// dismissals, which Phoebus doesn't have; `SubredditIconCache` and
    /// `ImageCache` are session-only.
    static func clearTweakCaches() async {
        await AvatarCache.shared.clear()
        await LinkPreviewCache.shared.clear()
        URLCache.shared.removeAllCachedResponses()
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
