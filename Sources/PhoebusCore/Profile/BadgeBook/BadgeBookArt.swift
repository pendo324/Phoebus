import Foundation

/// Reborn's bundled Badge Book art (`badgebook-catalog.json` and its `a_*` /
/// `t_*` icons): which bundled file draws a trophy or achievement, keyed as
/// Reborn's catalogue keys them.
public struct BadgeBookArt: Sendable {
    private var bySlug: [String: String] = [:]
    private var byTitle: [String: String] = [:]
    private var byImageName: [String: String] = [:]

    public init(catalogJSON: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: catalogJSON) as? [String: Any] else { return }
        for item in json["achievements"] as? [[String: Any]] ?? [] {
            guard let file = item["image"] as? String else { continue }
            if let base = Self.basename(item["image_url"] as? String) { byImageName[base] = file }
        }
        for item in json["trophies"] as? [[String: Any]] ?? [] {
            guard let file = item["image"] as? String else { continue }
            if let base = Self.basename(item["image_url"] as? String), byImageName[base] == nil { byImageName[base] = file }
            if let slug = Self.trophySlug(item["id"] as? String), bySlug[slug] == nil { bySlug[slug] = file }
            if let title = (item["title"] as? String)?.lowercased(), byTitle[title] == nil { byTitle[title] = file }
        }
    }

    /// The bundled file for a profile trophy: by its icon's slug, else its title.
    public func trophyFile(iconURL: String?, title: String?) -> String? {
        if let slug = Self.trophySlug(Self.basename(iconURL)), let file = bySlug[slug] { return file }
        if let title = title?.lowercased(), let file = byTitle[title] { return file }
        return nil
    }

    /// The bundled file for a catalogue image URL (achievements).
    public func file(imageURL: String?) -> String? {
        Self.basename(imageURL).flatMap { byImageName[$0] }
    }

    /// The last path component, without query or fragment, lowercased.
    static func basename(_ url: String?) -> String? {
        guard var s = url, !s.isEmpty else { return nil }
        if let q = s.firstIndex(of: "?") { s = String(s[..<q]) }
        if let h = s.firstIndex(of: "#") { s = String(s[..<h]) }
        let last = s.split(separator: "/").last.map(String.init)?.lowercased()
        return last?.isEmpty == false ? last : nil
    }

    /// Reborn's trophy slug: no extension, no leading 16-hex hash, nothing up to
    /// "trophy_image_for_", no trailing "-<size>".
    /// "14_year_club-70.png" and "d1fe…_trophy_image_for_14_year_club"
    /// both give "14_year_club".
    public static func trophySlug(_ name: String?) -> String? {
        guard var s = name?.lowercased(), !s.isEmpty else { return nil }
        if let dot = s.lastIndex(of: ".") { s = String(s[..<dot]) }
        if s.count > 17 {
            let hash = s.prefix(16)
            if s[s.index(s.startIndex, offsetBy: 16)] == "_", hash.allSatisfy({ "0123456789abcdef".contains($0) }) {
                s = String(s.dropFirst(17))
            }
        }
        if let marker = s.range(of: "trophy_image_for_") { s = String(s[marker.upperBound...]) }
        if let dash = s.lastIndex(of: "-"), s.index(after: dash) < s.endIndex,
           s[s.index(after: dash)...].allSatisfy(\.isNumber) {
            s = String(s[..<dash])
        }
        return s.isEmpty ? nil : s
    }
}
