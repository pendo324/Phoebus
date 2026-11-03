import SwiftUI
import PhoebusCore

/// The hold menu on one piece of media in a post or comment (Reborn
/// `Apollo-Reborn#1400`, `#1435`): the rows `MediaHoldMenu.items` chooses for
/// the item held. Saves go through `SaveAllMediaJob`, so "Save to Phoebus
/// Album" and "Download GIFs as…" apply; nothing here writes to Reddit.
struct MediaHoldMenuContent: View {
    let subject: MediaHoldMenu.Subject
    /// The album's images, for Save All Media.
    var albumURLs: [URL] = []

    var body: some View {
        ForEach(MediaHoldMenu.items(for: subject), id: \.action) { item in
            switch item.action {
            case .share:
                ShareLink(item: subject.shareURL) { label(item.action) }
            default:
                Button { perform(item.action) } label: { label(item.action) }
                    .disabled(!item.isEnabled)
            }
        }
    }

    private func label(_ action: MediaHoldMenu.Action) -> some View {
        Label(action.title, systemImage: action.symbol)
    }

    private func perform(_ action: MediaHoldMenu.Action) {
        let url = subject.mediaURL
        switch action {
        case .copyImage, .copyGIF:
            Task {
                if let data = await MediaBytes.data(for: url) { PasteboardHelper.copyImage(data) }
            }
        case .copyLink:
            PasteboardHelper.copy(url: subject.shareURL)
        case .saveImage:
            SaveAllMediaJob.shared.start([.image(url)])
        case .saveGIF:
            SaveAllMediaJob.shared.start([.gif(url)])
        case .saveVideo:
            Task { SaveAllMediaJob.shared.start([.video(await Self.progressiveURL(for: url))]) }
        case .saveAllMedia:
            SaveAllMediaJob.shared.start(albumURLs.map { .image($0) })
        case .share:
            break
        }
    }

    /// A v.redd.it video plays as an HLS playlist but saves from its progressive
    /// tracks, which the manifest names; any other URL is already a file.
    private static func progressiveURL(for url: URL) async -> URL {
        guard RedditVideoStream.assetID(fromVRedditURL: url) != nil, url.pathExtension.lowercased() != "mp4" else { return url }
        return await VideoDownloader.resolvePosterURL(forRedditVideo: url) ?? url
    }
}

private struct MediaHoldMenuModifier: ViewModifier {
    let subject: MediaHoldMenu.Subject
    let albumURLs: [URL]
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            // Nested in the comment's or post's own menu: the deeper hold wins.
            content.contextMenu { MediaHoldMenuContent(subject: subject, albumURLs: albumURLs) }
        } else {
            content
        }
    }
}

extension View {
    /// Gives this media Reborn's hold menu. `isEnabled` is fixed for a view's
    /// lifetime (a viewer that is already fullscreen has its own menu).
    func mediaHoldMenu(_ subject: MediaHoldMenu.Subject, albumURLs: [URL] = [], isEnabled: Bool = true) -> some View {
        modifier(MediaHoldMenuModifier(subject: subject, albumURLs: albumURLs, isEnabled: isEnabled))
    }
}
