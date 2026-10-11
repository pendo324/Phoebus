import Foundation

/// What reddit.com/settings/profile hands its page script: the social links
/// the profile has now, with the ids removing one takes, and the platforms a
/// link can be added for, and what the profile shows (Profile Visibility). The
/// page carries them as the entity-escaped JSON `initialState` attribute of its
/// `<settings-profile-section>` and `<settings-profile-visibility-section>`
/// elements.
public struct ProfileSettingsPage: Sendable, Equatable {
    public let socialLinks: [ProfileSocialLink]
    /// The page's `socialPlatforms`; empty when it lists none this app can read.
    public let platforms: [ProfileSocialPlatform]

    /// The page's `identity.preferences`; nil when it carries none.
    public let visibility: ProfileVisibility?

    public init(socialLinks: [ProfileSocialLink], platforms: [ProfileSocialPlatform], visibility: ProfileVisibility? = nil) {
        self.socialLinks = socialLinks
        self.platforms = platforms
        self.visibility = visibility
    }

    static let elementName = "<settings-profile-section"
    static let visibilityElementName = "<settings-profile-visibility-section"

    /// Reads the page's HTML; nil when it has no profile settings element, as
    /// with a sign-in page, or its state can't be read.
    public static func parse(html: String) -> ProfileSettingsPage? {
        guard let root = state(ofElementAt: elementName, in: html),
              let profile = ((root["identity"] as? [String: Any])?["redditor"] as? [String: Any])?["profile"] as? [String: Any]
        else { return nil }
        let links = (profile["socialLinks"] as? [[String: Any]] ?? []).compactMap(ProfileSocialLink.init(json:))
        let platforms = (root["socialPlatforms"] as? [[String: Any]] ?? []).compactMap(platform)
        // Every section carries the same state; the visibility section's own is preferred.
        let visibility = state(ofElementAt: visibilityElementName, in: html).flatMap { ProfileVisibility(state: $0) }
            ?? ProfileVisibility(state: root)
        return ProfileSettingsPage(socialLinks: links, platforms: platforms, visibility: visibility)
    }

    private static func state(ofElementAt opening: String, in html: String) -> [String: Any]? {
        guard let state = attributes(ofElementAt: opening, in: html)?["initialstate"] else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(state.utf8))) as? [String: Any]
    }

    /// `{type, displayName, fields: [{type: USERNAME|DISPLAY_TEXT|URL, limit}]}`.
    /// A platform whose fields aren't ones this app can fill is left out.
    private static func platform(_ json: [String: Any]) -> ProfileSocialPlatform? {
        guard let type = json["type"] as? String, !type.isEmpty else { return nil }
        var limits: [String: Int] = [:]
        for field in json["fields"] as? [[String: Any]] ?? [] {
            if let kind = field["type"] as? String { limits[kind] = field["limit"] as? Int }
        }
        let name = (json["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? ProfileSocialLinkType(rawValue: type)?.displayName ?? type
        if let username = limits["USERNAME"] {
            return ProfileSocialPlatform(type: type, displayName: name, input: .username(limit: username))
        }
        if let urlLimit = limits["URL"] {
            return ProfileSocialPlatform(
                type: type, displayName: name,
                input: .textAndURL(textLimit: limits["DISPLAY_TEXT"] ?? ProfileSocialPlatform.textLimit, urlLimit: urlLimit))
        }
        return nil
    }

    // MARK: HTML

    /// The attributes of the first element starting with `opening`, by
    /// lowercased name, with their entities decoded.
    static func attributes(ofElementAt opening: String, in html: String) -> [String: String]? {
        var search = html.startIndex..<html.endIndex
        while let found = html.range(of: opening, options: .caseInsensitive, range: search) {
            var index = found.upperBound
            // Not a longer element name, such as `<settings-profile-section-x`.
            if index < html.endIndex, !html[index].isWhitespace, html[index] != ">", html[index] != "/" {
                search = found.upperBound..<html.endIndex
                continue
            }
            return scanAttributes(in: html, from: &index)
        }
        return nil
    }

    private static func scanAttributes(in html: String, from index: inout String.Index) -> [String: String]? {
        var result: [String: String] = [:]
        let end = html.endIndex
        func skipSpaces() { while index < end, html[index].isWhitespace { index = html.index(after: index) } }
        while true {
            skipSpaces()
            guard index < end else { return nil }
            if html[index] == ">" { return result }
            if html[index] == "/" {
                index = html.index(after: index)
                continue
            }
            let nameStart = index
            while index < end, !html[index].isWhitespace, !"=/>".contains(html[index]) { index = html.index(after: index) }
            let name = html[nameStart..<index].lowercased()
            skipSpaces()
            var value = ""
            if index < end, html[index] == "=" {
                index = html.index(after: index)
                skipSpaces()
                guard index < end else { return nil }
                if html[index] == "\"" || html[index] == "'" {
                    let quote = html[index]
                    index = html.index(after: index)
                    let valueStart = index
                    while index < end, html[index] != quote { index = html.index(after: index) }
                    guard index < end else { return nil }
                    value = String(html[valueStart..<index])
                    index = html.index(after: index)
                } else {
                    let valueStart = index
                    while index < end, !html[index].isWhitespace, html[index] != ">" { index = html.index(after: index) }
                    value = String(html[valueStart..<index])
                }
            }
            result[name] = decodeEntities(value)
        }
    }

    private static let namedEntities: [String: Character] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'"]

    /// One pass, so `&amp;quot;` reads as `&quot;` and not as a quote.
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            index = text.index(after: index)
            guard character == "&", let semicolon = text[index...].prefix(10).firstIndex(of: ";") else {
                out.append(character)
                continue
            }
            let body = String(text[index..<semicolon])
            let decoded: Character?
            if body.hasPrefix("#") {
                let digits = body.dropFirst()
                let value = digits.first == "x" || digits.first == "X" ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
                decoded = value.flatMap(Unicode.Scalar.init).map(Character.init)
            } else {
                decoded = namedEntities[body]
            }
            if let decoded {
                out.append(decoded)
                index = text.index(after: semicolon)
            } else {
                out.append(character)
            }
        }
        return out
    }
}
