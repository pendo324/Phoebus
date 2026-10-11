import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A stored web session's `name=value; name2=value2` header (see
/// `WebSessionCredential.cookieHeader`) as cookies for a private
/// `WKWebsiteDataStore`.
public enum WebSessionCookies {
    /// `skipping` drops cookies by name. A `__Host-` cookie must be host-only,
    /// so it is pinned to www.reddit.com; everything else gets the
    /// `.reddit.com` scope the sign-in harvested it under.
    public static func cookies(fromHeader header: String, skipping: Set<String> = [],
                               lifetime: TimeInterval = 24 * 60 * 60) -> [HTTPCookie] {
        header.components(separatedBy: ";").compactMap { pair -> HTTPCookie? in
            guard let eq = pair.firstIndex(of: "=") else { return nil }
            let name = String(pair[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(pair[pair.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !skipping.contains(name) else { return nil }
            return HTTPCookie(properties: [
                .name: name,
                .value: value,
                .domain: name.hasPrefix("__Host-") ? "www.reddit.com" : ".reddit.com",
                .path: "/",
                .secure: "TRUE",
                .expires: Date().addingTimeInterval(lifetime),
            ])
        }
    }
}
