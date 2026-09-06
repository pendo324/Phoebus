import SwiftUI
import PhoebusCore

/// Small circular subreddit icon shown beside the subreddit name on
/// aggregate feeds.
///
/// Apollo shows this icon precisely when the subreddit isn't implied by
/// context: on Home/Popular/All, not inside a specific subreddit's own feed.
/// A session-scoped cache gives one lookup per subreddit, reused for every
/// subsequent row.
public struct SubredditIconView: View {
    let subreddit: String
    let repository: RedditRepository
    let size: CGFloat

    @Setting(GeneralSettingsStore.storage) private var settings
    @State private var icons: SubredditIconCache.Icons?
    private var iconURLString: String? { icons?.url(useCommunityIcons: settings.useCommunityIcons) }
    /// The lookup finished and the subreddit has no icon to show.
    private var hasNoIcon: Bool { icons != nil && iconURLString == nil }
    #if canImport(UIKit)
    @ObservedObject private var customArt = SubredditCustomArtStore.shared
    private var customIcon: Image? {
        customArt.image(for: subreddit, kind: .icon).map { Image(uiImage: $0) }
    }
    #else
    private var customIcon: Image? { nil }
    #endif

    /// `false` draws nothing until the icon resolves, so a caller's
    /// own placeholder (the hub's 👽 tile) shows through.
    let drawsPlaceholder: Bool

    public init(subreddit: String, repository: RedditRepository, size: CGFloat = 16, drawsPlaceholder: Bool = true) {
        self.subreddit = subreddit
        self.repository = repository
        self.size = size
        self.drawsPlaceholder = drawsPlaceholder
    }

    public var body: some View {
        Group {
            // A user's own icon (Reborn #266) wins everywhere the
            // subreddit's icon is drawn.
            if let custom = customIcon {
                custom.resizable().scaledToFill()
                    .clipShape(Circle())
            } else if let iconURLString, let url = URL(string: iconURLString) {
                CachedAsyncImage(url: url)
                    .clipShape(Circle())
            } else if hasNoIcon, drawsPlaceholder {
                SubredditLetterIcon(subreddit: subreddit, size: size)
            } else if drawsPlaceholder {
                Circle()
                    .fill(Color.secondary.opacity(0.25))
            } else {
                Color.clear
            }
        }
        // No `.clipped()` here: it would square off the circular `clipShape` on any
        // icon whose aspect ratio is not 1:1.
        .frame(width: size, height: size)
        .task(id: subreddit) { await resolve() }
    }

    private func resolve() async {
        guard !subreddit.isEmpty else { return }
        if let known = await SubredditIconCache.shared.lookup(subreddit) {
            icons = known
            return
        }
        guard let info = try? await repository.fetchSubredditInfo(name: subreddit) else { return }
        let fetched = SubredditIconCache.Icons(classic: info.iconImage, community: info.communityIcon)
        await SubredditIconCache.shared.store(fetched, for: subreddit)
        icons = fetched
    }
}

/// Session-scoped subreddit-icon cache. Negative results are cached too, so a
/// subreddit with no icon isn't refetched for every row.
actor SubredditIconCache {
    static let shared = SubredditIconCache()

    /// Both of a subreddit's icons, so the Use Community Icons switch
    /// takes effect without a refetch.
    struct Icons: Sendable {
        let classic: String?
        let community: String?

        init(classic: String?, community: String?) {
            self.classic = SubredditIconCache.cleaned(classic)
            self.community = SubredditIconCache.cleaned(community)
        }

        func url(useCommunityIcons: Bool) -> String? {
            useCommunityIcons ? (community ?? classic) : classic
        }
    }

    private var icons: [String: Icons] = [:]

    func removeAll() { icons.removeAll() }

    /// Seeds the cache from subreddit objects already in hand.
    ///
    /// The cache is memory-only, so without seeding every launch would re-fetch
    /// `/r/<name>/about` once per subreddit before any icon appeared, even when
    /// the list loaded from disk. The cached listing already carries
    /// `communityIcon`/`iconImage` for every row, so the URLs are handed over
    /// directly. Anything already known is left alone, since a live
    /// `fetchSubredditInfo` result is fresher than a snapshot.
    func seed(from subreddits: [RedditSubreddit]) {
        for subreddit in subreddits {
            let key = subreddit.displayName.lowercased()
            guard icons[key] == nil else { continue }
            icons[key] = Icons(classic: subreddit.iconImage, community: subreddit.communityIcon)
        }
    }

    func cachedURL(for subreddit: String) -> String? {
        icons[subreddit.lowercased()]?.url(useCommunityIcons: GeneralSettingsStore.load().useCommunityIcons)
    }

    /// nil when the subreddit has not been looked up.
    func lookup(_ subreddit: String) -> Icons? {
        icons[subreddit.lowercased()]
    }

    /// Reddit HTML-escapes the URL in JSON; an empty one means none.
    static func cleaned(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw.replacingOccurrences(of: "&amp;", with: "&")
    }

    func store(_ value: Icons, for subreddit: String) {
        icons[subreddit.lowercased()] = value
    }
}

/// Apollo's badge for a subreddit without an icon: its first letter in
/// white bold on the accent colour (#3479F5 on the default theme).
struct SubredditLetterIcon: View {
    let subreddit: String
    let size: CGFloat

    private var letter: String {
        let name = subreddit.hasPrefix("u_") ? String(subreddit.dropFirst(2)) : subreddit
        return name.first.map { String($0).uppercased() } ?? "?"
    }

    var body: some View {
        Circle()
            .fill(Color.apolloAccent)
            .overlay {
                Text(letter)
                    .font(.system(size: size * 0.64, weight: .bold))
                    .foregroundStyle(.white)
            }
    }
}
