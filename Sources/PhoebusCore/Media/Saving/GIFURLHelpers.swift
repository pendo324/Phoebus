import Foundation

/// CDN convention: Reddit transcodes every hosted "GIF"
/// (`preview.redd.it`/`i.redd.it` media items, and the Imgur-style
/// `.gifv` URLs Apollo also treats as GIFs) to a same-name `.mp4`
/// sibling alongside the raw GIF. Shared by `AnimatedGIFView`'s playback
/// fallback (`preferredGIFFallbackFormat`) and `GIFSaveService`'s save-format
/// branching (`gifSaveFormat`), so the URL rewrite lives here once.
public enum GIFURLHelpers {
    public static func mp4SiblingURL(for gifURL: URL) -> URL? {
        let lowerPath = gifURL.path.lowercased()
        guard lowerPath.hasSuffix(".gif") || lowerPath.hasSuffix(".gifv") else { return nil }
        // `URL.deletingPathExtension()`/`appendingPathExtension(_:)` are required
        // here: `NSString`'s path utilities collapse the `//` in `https://` to a
        // single `/`, corrupting the scheme.
        return gifURL.deletingPathExtension().appendingPathExtension("mp4")
    }
}
