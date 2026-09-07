import SwiftUI
import PhoebusCore

/// Reborn's "Fully working Imgur integration": fetches an Imgur album's
/// images and renders them as a swipeable gallery (reusing
/// `GalleryMediaView`, the paging UI of Reddit's native galleries) instead
/// of a plain link. Requires the user's own Imgur client ID (Settings >
/// Custom API); shows a configuration hint when it is absent.
struct ImgurAlbumView: View {
    let albumID: String
    @State private var album: ImgurAlbum?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let album, !album.images.isEmpty {
                GalleryMediaView(urls: album.images.compactMap { URL(string: $0.link) })
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            album = try await ImgurClient.fetchAlbum(id: albumID)
        } catch ImgurClient.ClientError.notConfigured {
            errorMessage = "Set your Imgur Client ID in Settings > Custom API to view this album."
        } catch {
            errorMessage = "Couldn't load this Imgur album."
        }
    }
}
