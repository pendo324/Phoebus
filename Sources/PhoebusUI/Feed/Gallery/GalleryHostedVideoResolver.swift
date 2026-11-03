import Foundation
import PhoebusCore

/// Looks up the playable stream of a sports-clip or Streamable post for Gallery
/// View (`Apollo-Reborn#1389`). One lookup per clip is shared by the grid tile
/// and the viewer, and results are kept for the session.
///
/// A failure the grid alone saw is not final: the grid stops asking, but
/// opening the clip still makes the viewer's own attempt.
@MainActor
final class GalleryHostedVideoResolver {
    static let shared = GalleryHostedVideoResolver()

    private var resolved: [String: URL] = [:]
    private var inFlight: [String: Task<URL?, Never>] = [:]
    private var gridFailed = Set<String>()

    func cachedURL(for host: GalleryHostedVideo) -> URL? { resolved[host.key] }

    func resolve(_ host: GalleryHostedVideo, forGrid: Bool) async -> URL? {
        let key = host.key
        if let url = resolved[key] { return url }
        if forGrid, gridFailed.contains(key), inFlight[key] == nil { return nil }
        if let running = inFlight[key] { return await running.value }
        let task = Task { await Self.lookup(host) }
        inFlight[key] = task
        let url = await task.value
        inFlight[key] = nil
        if let url { resolved[key] = url } else { gridFailed.insert(key) }
        return url
    }

    private static func lookup(_ host: GalleryHostedVideo) async -> URL? {
        switch host {
        case .streamable(let id):
            return try? await StreamableClient.shared.resolvePlayableURL(forID: id)
        case .sportsClip(let pageURL):
            guard let metadata = try? await OpenGraphClient.fetchMetadata(for: pageURL),
                  let urlString = metadata.videoURLString else { return nil }
            return URL(string: urlString)
        }
    }
}
