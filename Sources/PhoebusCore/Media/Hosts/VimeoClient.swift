// Vimeo support, using the three Vimeo hosts Apollo uses:
// player.vimeo.com/video/, vimeo.com/api/v2/video/, and
// i.vimeocdn.com/video/.
//
// Apollo's thumbnail host list includes Vimeo and Imgflip, so both get
// inline treatment in `PostMediaKind.classify`.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum VimeoURLParser {
    /// Extracts a numeric Vimeo video ID from a vimeo.com or
    /// player.vimeo.com URL.
    public static func extractVideoID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(), host.contains("vimeo.com") else {
            return nil
        }
        // player.vimeo.com/video/<id>, vimeo.com/<id>,
        // vimeo.com/channels/<name>/<id>, vimeo.com/groups/<name>/videos/<id>
        let components = url.pathComponents.filter { $0 != "/" }
        for component in components.reversed() {
            if let id = Int(component) {
                return String(id)
            }
        }
        return nil
    }

    /// Builds the embeddable player URL (Apollo's
    /// `https://player.vimeo.com/video/` prefix).
    public static func playerURL(forVideoID videoID: String) -> URL? {
        URL(string: "https://player.vimeo.com/video/\(videoID)")
    }
}

/// Imgflip link resolution, using Apollo's pattern and base URL:
///
///   `^(?:(?:https?:)?//)?(?:www\.)?(?:(?:i\.imgflip\.com)|(?:imgflip\.com/i))/([\w-]+)`
///   base image URL: `https://i.imgflip.com/`
public enum ImgflipURLParser {
    public static func extractID(from url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        if host == "i.imgflip.com", let first = path.first {
            // i.imgflip.com/<id>.jpg
            return first.split(separator: ".").first.map(String.init)
        }
        if host == "imgflip.com" || host == "www.imgflip.com", path.first == "i", path.count > 1 {
            return path[1]
        }
        return nil
    }

    public static func imageURL(forID id: String) -> URL? {
        URL(string: "https://i.imgflip.com/\(id).jpg")
    }
}
