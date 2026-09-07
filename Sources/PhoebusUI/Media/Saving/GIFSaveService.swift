import Foundation
import PhoebusCore
#if canImport(Photos)
import Photos
#endif

/// Backs the "Save GIFs as…" setting (`GeneralSettings.gifSaveFormat`): an
/// animated-GIF post is saved as the raw GIF, as the CDN's MP4 transcode, or
/// the user is asked each time.
///
/// Distinct from `preferredGIFFallbackFormat`, which only governs inline
/// playback; this only affects what is written to the photo library.
public enum GIFSaveService {
    public enum SaveError: LocalizedError {
        case noVideoAvailable
        case photosAccessDenied
        case downloadFailed
        case incompleteGIF

        public var errorDescription: String? {
            switch self {
            case .noVideoAvailable: return "This GIF has no video version to save."
            case .photosAccessDenied: return "Phoebus needs permission to save to your photo library."
            case .downloadFailed: return "Couldn't save the GIF."
            // Reborn's message wording.
            case .incompleteGIF: return "The GIF file is incomplete. Download it again and retry."
            }
        }
    }

    /// A `.gif`/`.gifv` URL's same-name `.mp4` sibling is Reddit's transcoded
    /// video of the same media. Delegates to the shared `GIFURLHelpers` so it
    /// can't drift from `AnimatedGIFView`.
    public static func mp4SiblingURL(for gifURL: URL) -> URL? {
        GIFURLHelpers.mp4SiblingURL(for: gifURL)
    }

    /// The "Automatic" option: use the CDN's MP4 transcode when one exists and
    /// the raw GIF is large enough to be worth replacing; otherwise save a plain
    /// GIF. Byte size stands in for length, since a HEAD request can't report
    /// animation duration.
    static let automaticSizeThresholdBytes = 3_000_000

    /// Saves according to `format`. `.askEachTime` is not handled here: the
    /// call site must present its own GIF-vs-Video chooser and call
    /// `saveAsGIF`/`saveAsVideo` with the pick.
    public static func save(gifURL: URL, format: GIFSaveFormat, useApolloAlbum: Bool) async throws {
        switch format {
        case .alwaysGIF, .askEachTime:
            try await saveAsGIF(gifURL: gifURL, useApolloAlbum: useApolloAlbum)
        case .alwaysVideo:
            do {
                try await saveAsVideo(gifURL: gifURL, useApolloAlbum: useApolloAlbum)
            } catch SaveError.noVideoAvailable {
                // Never lose the media outright because no video transcode exists.
                try await saveAsGIF(gifURL: gifURL, useApolloAlbum: useApolloAlbum)
            }
        case .automatic:
            if mp4SiblingURL(for: gifURL) != nil, await remoteContentLength(of: gifURL) ?? 0 > automaticSizeThresholdBytes {
                do {
                    try await saveAsVideo(gifURL: gifURL, useApolloAlbum: useApolloAlbum)
                    return
                } catch SaveError.noVideoAvailable {
                    // fall through to GIF below
                }
            }
            try await saveAsGIF(gifURL: gifURL, useApolloAlbum: useApolloAlbum)
        }
    }

    public static func saveAsGIF(gifURL: URL, useApolloAlbum: Bool) async throws {
        #if canImport(Photos)
        guard await PhotoAlbumSaver.requestAccess() else {
            throw SaveError.photosAccessDenied
        }
        let (data, response) = try await URLSession.shared.data(from: gifURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SaveError.downloadFailed
        }
        // As in Reborn, validate before writing: the bytes must be a complete GIF,
        // never a host's HTML error page or a truncated download, and are written
        // with the GIF type so Photos keeps the animation.
        guard isCompleteGIF(data) else { throw SaveError.incompleteGIF }
        try await PhotoAlbumSaver.save(.gifData(data), useApolloAlbum: useApolloAlbum)
        #endif
    }

    /// GIF87a/GIF89a header and the 0x3B trailer.
    public static func isCompleteGIF(_ data: Data) -> Bool {
        guard data.count > 13, data.last == 0x3B else { return false }
        let header = [UInt8](data.prefix(6))
        return header == Array("GIF89a".utf8) || header == Array("GIF87a".utf8)
    }

    public static func saveAsVideo(gifURL: URL, useApolloAlbum: Bool) async throws {
        guard let mp4URL = mp4SiblingURL(for: gifURL) else {
            throw SaveError.noVideoAvailable
        }
        #if canImport(Photos)
        guard await PhotoAlbumSaver.requestAccess() else {
            throw SaveError.photosAccessDenied
        }
        #endif
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let file = temporaryDirectory.appendingPathComponent("apollo-gif-video-\(UUID().uuidString).mp4")
        let (downloaded, response) = try await URLSession.shared.download(from: mp4URL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            try? FileManager.default.removeItem(at: downloaded)
            throw SaveError.noVideoAvailable
        }
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: downloaded, to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #if canImport(Photos)
        try await PhotoAlbumSaver.save(.video(file), useApolloAlbum: useApolloAlbum)
        #endif
    }

    private static func remoteContentLength(of url: URL) async -> Int? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        return http.expectedContentLength > 0 ? Int(http.expectedContentLength) : nil
    }
}
