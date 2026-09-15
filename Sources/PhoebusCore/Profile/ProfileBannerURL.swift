import Foundation

/// The uncropped original of a Reddit profile banner (upstream #1186).
///
/// `about.json`'s `subreddit.banner_img` is a server-side crop,
/// `https://styles.redditmedia.com/t5_<id>/styles/profileBanner_<x>.png?width=1280&height=384&crop=...&s=...`.
/// Dropping the query returns the full image. Only that exact shape
/// qualifies: any unknown parameter may carry authorization or
/// versioning, so those URLs are kept intact. Callers keep the supplied
/// URL as a fallback in case the original fails to load.
public enum ProfileBannerURL {
    static let cropKeys: Set<String> = ["width", "height", "crop", "auto", "format", "s"]

    public static func originalCandidate(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "styles.redditmedia.com",
              url.path.hasPrefix("/t5_"),
              url.lastPathComponent.hasPrefix("profileBanner_"),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil, components.port == nil,
              let items = components.queryItems, !items.isEmpty else { return url }
        var sized = false
        for item in items {
            guard cropKeys.contains(item.name) else { return url }
            if ["width", "height", "crop"].contains(item.name) { sized = true }
        }
        guard sized, url.path.contains("/styles/profileBanner_") else { return url }
        components.query = nil
        return components.url ?? url
    }
}
