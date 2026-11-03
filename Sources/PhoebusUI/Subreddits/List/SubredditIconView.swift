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
    @Environment(\.isSettingsPreview) private var isSettingsPreview
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
        // A settings preview draws the letter icon rather than look one up.
        if isSettingsPreview {
            icons = SubredditIconCache.Icons(classic: nil, community: nil)
            return
        }
        let repository = repository, subreddit = subreddit
        icons = await SubredditIconCache.shared.icons(for: subreddit) {
            try await repository.fetchSubredditInfo(name: subreddit)
        }
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
