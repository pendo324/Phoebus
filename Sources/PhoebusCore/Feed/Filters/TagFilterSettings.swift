import Foundation

/// Reborn's Tag Filters: global flags for enabled (off), NSFW (on) and
/// spoiler (on), plus per-subreddit overrides, a `{nsfw, spoiler}`
/// dictionary where an absent value means "use global". Everything
/// filtered blurs, covering the post's title and thumbnail together.
public struct TagFilterSettings: Codable, Sendable, Equatable {
    /// One subreddit's override. `nil` for a tag means "uses global".
    public struct Override: Codable, Sendable, Equatable {
        public var nsfw: Bool?
        public var spoiler: Bool?
        public init(nsfw: Bool? = nil, spoiler: Bool? = nil) {
            self.nsfw = nsfw
            self.spoiler = spoiler
        }

        /// The override's one-line summary for the settings row.
        public var summary: String {
            var parts: [String] = []
            if let nsfw { parts.append("NSFW: \(nsfw ? "on" : "off")") }
            if let spoiler { parts.append("Spoiler: \(spoiler ? "on" : "off")") }
            return parts.isEmpty ? "(uses global)" : parts.joined(separator: " · ")
        }
    }

    public var enabled: Bool
    public var nsfw: Bool
    public var spoiler: Bool
    /// Keyed by lower-cased subreddit name.
    public var subredditOverrides: [String: Override]

    public static let `default` = TagFilterSettings(enabled: false, nsfw: true, spoiler: true, subredditOverrides: [:])

    public init(enabled: Bool, nsfw: Bool, spoiler: Bool, subredditOverrides: [String: Override]) {
        self.enabled = enabled
        self.nsfw = nsfw
        self.spoiler = spoiler
        self.subredditOverrides = subredditOverrides
    }

    enum CodingKeys: String, CodingKey { case enabled, nsfw, spoiler, subredditOverrides }

    /// Tolerates older stored shapes.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? false
        nsfw = (try? c.decodeIfPresent(Bool.self, forKey: .nsfw)) ?? true
        spoiler = (try? c.decodeIfPresent(Bool.self, forKey: .spoiler)) ?? true
        if let overrides = try? c.decodeIfPresent([String: Override].self, forKey: .subredditOverrides) {
            subredditOverrides = overrides
        } else if let legacy = try? c.decodeIfPresent([String: Bool].self, forKey: .subredditOverrides) {
            subredditOverrides = legacy.mapValues { Override(nsfw: $0, spoiler: $0) }
        } else {
            subredditOverrides = [:]
        }
    }

    /// Whether the tag is filtered for this subreddit, honouring its override.
    public func tagOn(subreddit: String, nsfw isNSFWTag: Bool) -> Bool {
        let override = subredditOverrides[subreddit.lowercased()]
        if isNSFWTag, let v = override?.nsfw { return v }
        if !isNSFWTag, let v = override?.spoiler { return v }
        return isNSFWTag ? nsfw : spoiler
    }

    /// The tag filters' cover over a post's title and media.
    public func shouldBlur(subreddit: String, isNSFW: Bool, isSpoiler: Bool) -> Bool {
        guard enabled, isNSFW || isSpoiler else { return false }
        let filterNSFW = tagOn(subreddit: subreddit, nsfw: true)
        let filterSpoiler = tagOn(subreddit: subreddit, nsfw: false)
        return (isNSFW && filterNSFW) || (isSpoiler && filterSpoiler)
    }

    /// Whether a post's media is covered: Apollo always obscures spoiler
    /// media, and NSFW media per "Blur NSFW Media" (the account's Reddit
    /// pref unless overridden). The tag filters' cover applies on top,
    /// whatever the override says.
    public func shouldBlurMedia(subreddit: String, isNSFW: Bool, isSpoiler: Bool,
                                nsfwBlurOverride: NSFWBlurOverride, accountPref: Bool?) -> Bool {
        isSpoiler
            || (isNSFW && nsfwBlurOverride.blursNSFW(accountPref: accountPref))
            || shouldBlur(subreddit: subreddit, isNSFW: isNSFW, isSpoiler: isSpoiler)
    }
}

public enum TagFilterStore {
    private static let key = "com.pendo324.Phoebus.tagFilterSettings"

    public static let storage = SettingsStore<TagFilterSettings>(key: key) { TagFilterSettings.default }

    public static func load() -> TagFilterSettings { storage.load() }

    public static func save(_ settings: TagFilterSettings) { storage.save(settings) }

    public static func setOverride(subreddit: String, _ override: TagFilterSettings.Override?) {
        var settings = load()
        let key = subreddit.lowercased()
        if let override {
            settings.subredditOverrides[key] = override
        } else {
            settings.subredditOverrides.removeValue(forKey: key)
        }
        save(settings)
    }
}

extension TagFilterSettings: StoredSettingsModel {
    public static var store: SettingsStore<TagFilterSettings> { TagFilterStore.storage }
}
