import Foundation

/// Reddit HTML-escapes image URLs in some JSON (`&amp;` for `&`), which would
/// break a signed `?width=..&s=..` URL.
public enum ImageURLCleaning {
    /// The URL with `&amp;` unescaped; nil for no URL or an empty one.
    public static func cleaned(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw.replacingOccurrences(of: "&amp;", with: "&")
    }
}
