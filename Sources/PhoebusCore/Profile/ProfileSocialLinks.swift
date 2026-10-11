import Foundation

/// The social link types this app knows (`SocialLinkType`), in the order
/// reddit.com's profile settings offer them: what the built-in platform table
/// and the icons are keyed on. The settings page's own platform list takes
/// precedence at runtime (`ProfileSocialPlatform`).
public enum ProfileSocialLinkType: String, CaseIterable, Sendable {
    case reddit = "REDDIT"
    case beacons = "BEACONS"
    case buyMeACoffee = "BUY_ME_A_COFFEE"
    case cameo = "CAMEO"
    case cashApp = "CASH_APP"
    case discord = "DISCORD"
    case facebook = "FACEBOOK"
    case indiegogo = "INDIEGOGO"
    case instagram = "INSTAGRAM"
    case kickstarter = "KICKSTARTER"
    case kofi = "KOFI"
    case linktree = "LINKTREE"
    case onlyFans = "ONLYFANS"
    case patreon = "PATREON"
    case payPal = "PAYPAL"
    case shopify = "SHOPIFY"
    case soundCloud = "SOUNDCLOUD"
    case spotify = "SPOTIFY"
    case substack = "SUBSTACK"
    case tikTok = "TIKTOK"
    case tumblr = "TUMBLR"
    case twitch = "TWITCH"
    case twitter = "TWITTER"
    case venmo = "VENMO"
    case youTube = "YOUTUBE"
    case custom = "CUSTOM"

    /// The name reddit.com's profile settings show.
    public var displayName: String {
        switch self {
        case .reddit: return "Reddit"
        case .beacons: return "Beacons"
        case .buyMeACoffee: return "Buy Me a Coffee"
        case .cameo: return "Cameo"
        case .cashApp: return "Cash App"
        case .discord: return "Discord"
        case .facebook: return "Facebook"
        case .indiegogo: return "Indiegogo"
        case .instagram: return "Instagram"
        case .kickstarter: return "Kickstarter"
        case .kofi: return "Kofi"
        case .linktree: return "Linktree"
        case .onlyFans: return "OnlyFans"
        case .patreon: return "Patreon"
        case .payPal: return "PayPal"
        case .shopify: return "Shopify"
        case .soundCloud: return "SoundCloud"
        case .spotify: return "Spotify"
        case .substack: return "Substack"
        case .tikTok: return "TikTok"
        case .tumblr: return "Tumblr"
        case .twitch: return "Twitch"
        case .twitter: return "Twitter"
        case .venmo: return "Venmo"
        case .youTube: return "Youtube"
        case .custom: return "Custom"
        }
    }

    /// What the type takes when the settings page hasn't said: a username, or
    /// display text and a URL.
    public var builtInInput: ProfileSocialPlatform.Input {
        switch self {
        case .discord, .facebook, .indiegogo, .kickstarter, .shopify, .spotify, .substack, .youTube, .custom:
            return .textAndURL(textLimit: ProfileSocialPlatform.textLimit, urlLimit: ProfileSocialPlatform.urlLimit)
        default:
            return .username(limit: ProfileSocialPlatform.usernameLimit)
        }
    }

    /// Whether the link is a display text plus a URL rather than a username.
    public var takesURL: Bool { ProfileSocialPlatform(self).takesURL }

    /// Schematic SF Symbol for the platform, in the style of `SocialLinkScraper`'s.
    public var systemImageName: String {
        switch self {
        case .custom: return "link"
        case .buyMeACoffee, .kofi: return "cup.and.saucer.fill"
        case .patreon, .kickstarter, .indiegogo: return "heart.fill"
        case .payPal, .cashApp, .venmo: return "dollarsign.circle.fill"
        case .instagram: return "camera.fill"
        case .twitter: return "at"
        case .tikTok: return "music.note"
        case .youTube: return "play.rectangle.fill"
        case .twitch: return "gamecontroller.fill"
        case .discord: return "bubble.left.and.bubble.right.fill"
        case .spotify, .soundCloud: return "music.note.list"
        case .facebook: return "person.2.fill"
        case .onlyFans: return "lock.fill"
        case .linktree, .beacons: return "link.circle.fill"
        case .tumblr: return "text.bubble.fill"
        case .reddit: return "person.crop.circle.fill"
        case .shopify: return "bag.fill"
        case .substack: return "newspaper.fill"
        case .cameo: return "video.fill"
        }
    }
}

/// A platform a link can be added for, and the fields it takes: the
/// `socialPlatforms` Reddit's settings page lists, or `builtIn` when the page
/// isn't available.
public struct ProfileSocialPlatform: Sendable, Equatable, Hashable, Identifiable {
    public enum Input: Sendable, Equatable, Hashable {
        /// Just a username (`handle`), from which Reddit builds the link.
        case username(limit: Int)
        /// Display text (`title`) and a web address (`outboundUrl`).
        case textAndURL(textLimit: Int, urlLimit: Int)
    }

    /// Reddit's limits for the fields, which the page restates per platform.
    public static let usernameLimit = 30
    public static let textLimit = 21
    public static let urlLimit = 250

    /// Reddit's type name, such as `INSTAGRAM`.
    public let type: String
    public let displayName: String
    public let input: Input

    public var id: String { type }

    public init(type: String, displayName: String, input: Input) {
        self.type = type
        self.displayName = displayName
        self.input = input
    }

    public init(_ known: ProfileSocialLinkType) {
        self.init(type: known.rawValue, displayName: known.displayName, input: known.builtInInput)
    }

    /// Whether the link is display text plus a URL rather than a username.
    public var takesURL: Bool {
        if case .textAndURL = input { return true }
        return false
    }

    public var systemImageName: String {
        ProfileSocialLinkType(rawValue: type)?.systemImageName ?? "link"
    }

    /// Every known type in the page's order, for when it can't be read.
    public static let builtIn: [ProfileSocialPlatform] = ProfileSocialLinkType.allCases.map(ProfileSocialPlatform.init)
}

/// A social link as Reddit holds it.
public struct ProfileSocialLink: Sendable, Equatable, Identifiable {
    /// Reddit's id, which removing a link takes.
    public let id: String
    /// Reddit's type as sent; `type` is nil for one this app doesn't know.
    public let rawType: String
    public let title: String
    public let handle: String?
    public let outboundURL: String?

    public var type: ProfileSocialLinkType? { ProfileSocialLinkType(rawValue: rawType) }

    public init(id: String, rawType: String, title: String, handle: String?, outboundURL: String?) {
        self.id = id
        self.rawType = rawType
        self.title = title
        self.handle = handle
        self.outboundURL = outboundURL
    }

    /// A link as Reddit's JSON gives it: `{id, type, title, handle, outboundUrl}`.
    init?(json link: [String: Any]) {
        guard let id = link["id"] as? String, !id.isEmpty, let type = link["type"] as? String else { return nil }
        func text(_ key: String) -> String? {
            guard let value = link[key] as? String, !value.isEmpty else { return nil }
            return value
        }
        self.init(id: id, rawType: type, title: text("title") ?? "", handle: text("handle"), outboundURL: text("outboundUrl"))
    }

    /// What a row shows under the type: the username, or the link's address.
    public var detail: String {
        if let handle, !handle.isEmpty { return handle }
        return outboundURL ?? ""
    }

    public var systemImageName: String { type?.systemImageName ?? "link" }

    /// What a row is called: the platform for a username link, otherwise the
    /// display text the link was given.
    public func heading(in platforms: [ProfileSocialPlatform]) -> String {
        let platform = platforms.first { $0.type == rawType }
        if let platform, !platform.takesURL { return platform.displayName }
        return title.isEmpty ? (platform?.displayName ?? rawType) : title
    }
}

public enum SocialLinkIssue: Sendable, Equatable {
    case missingUsername
    case usernameTooLong(limit: Int)
    case missingTitle
    case titleTooLong(limit: Int)
    case missingURL
    case invalidURL
    case urlTooLong(limit: Int)

    public var message: String {
        switch self {
        case .missingUsername: return "Enter a username."
        case .usernameTooLong(let limit): return "A username can be up to \(limit) characters."
        case .missingTitle: return "Enter the text to show for the link."
        case .titleTooLong(let limit): return "The text can be up to \(limit) characters."
        case .missingURL: return "Enter a link."
        case .invalidURL: return "Enter a web address, like https://example.com."
        case .urlTooLong(let limit): return "A link can be up to \(limit) characters."
        }
    }
}

/// A social link being added: a username for a platform that takes one, or
/// display text and a URL for one that takes those.
public struct SocialLinkDraft: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var platform: ProfileSocialPlatform
    public var handle: String
    public var title: String
    public var url: String

    public init(id: UUID = UUID(), platform: ProfileSocialPlatform = ProfileSocialPlatform(.instagram),
                handle: String = "", title: String = "", url: String = "") {
        self.id = id
        self.platform = platform
        self.handle = handle
        self.title = title
        self.url = url
    }

    public init(id: UUID = UUID(), type: ProfileSocialLinkType, handle: String = "", title: String = "", url: String = "") {
        self.init(id: id, platform: ProfileSocialPlatform(type), handle: handle, title: title, url: url)
    }

    /// A draft that re-creates an existing link, for editing it; nil for a
    /// type `platforms` doesn't list.
    public init?(editing link: ProfileSocialLink, platforms: [ProfileSocialPlatform] = ProfileSocialPlatform.builtIn) {
        guard let platform = platforms.first(where: { $0.type == link.rawType }) else { return nil }
        self.init(platform: platform, handle: link.handle ?? "", title: platform.takesURL ? link.title : "",
                  url: link.outboundURL ?? "")
    }

    /// The username as Reddit wants it: edges trimmed and no leading `@`.
    public var normalizedHandle: String {
        var text = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasPrefix("@") { text.removeFirst() }
        return text
    }

    /// The display text on one line.
    public var normalizedTitle: String {
        title.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    /// The address with `https://` added when none was typed; nil unless it is
    /// a web address.
    public var normalizedURL: String? {
        let text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { return nil }
        let candidate = text.contains("://") ? text : "https://" + text
        guard let parsed = URL(string: candidate), ["http", "https"].contains(parsed.scheme?.lowercased()),
              let host = parsed.host, host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".") else { return nil }
        return candidate
    }

    public var issues: [SocialLinkIssue] {
        switch platform.input {
        case .textAndURL(let textLimit, let urlLimit):
            var found: [SocialLinkIssue] = []
            if normalizedTitle.isEmpty {
                found.append(.missingTitle)
            } else if normalizedTitle.unicodeScalars.count > textLimit {
                found.append(.titleTooLong(limit: textLimit))
            }
            if url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                found.append(.missingURL)
            } else if let normalizedURL {
                if normalizedURL.unicodeScalars.count > urlLimit { found.append(.urlTooLong(limit: urlLimit)) }
            } else {
                found.append(.invalidURL)
            }
            return found
        case .username(let limit):
            if normalizedHandle.isEmpty { return [.missingUsername] }
            return normalizedHandle.unicodeScalars.count > limit ? [.usernameTooLong(limit: limit)] : []
        }
    }

    public var isValid: Bool { issues.isEmpty }

    /// The `SetProfileSocialLinks` input for this link, as the reddit.com
    /// editor sends it; nil while the draft isn't valid.
    public var input: [String: String]? {
        guard isValid else { return nil }
        if platform.takesURL {
            guard let normalizedURL else { return nil }
            return ["type": platform.type, "title": normalizedTitle, "outboundUrl": normalizedURL]
        }
        return ["type": platform.type, "handle": normalizedHandle]
    }

    /// Whether this would re-create `link` as it is.
    public func matches(_ link: ProfileSocialLink) -> Bool {
        guard link.rawType == platform.type else { return false }
        if platform.takesURL {
            return normalizedTitle == link.title && normalizedURL == link.outboundURL
        }
        return normalizedHandle.caseInsensitiveCompare(link.handle ?? "") == .orderedSame
    }

    /// What a row shows under the type.
    public var detail: String {
        platform.takesURL ? (normalizedURL ?? url) : normalizedHandle
    }
}

/// The social links being edited: Reddit's current list, with links staged to
/// be removed and added. Nothing reaches Reddit until the screen saves. An edit
/// to a saved link is its removal plus an addition, because Reddit only adds
/// and removes.
public struct SocialLinkEdits: Sendable, Equatable {
    /// Reddit allows five links on a profile.
    public static let maximum = 5

    public enum Row: Sendable, Equatable, Identifiable {
        case saved(ProfileSocialLink)
        case pending(SocialLinkDraft)

        public var id: String {
            switch self {
            case .saved(let link): return "saved-" + link.id
            case .pending(let draft): return "pending-" + draft.id.uuidString
            }
        }
    }

    /// What a save sends, in order: the removals, then each addition.
    public struct Plan: Sendable, Equatable {
        public let removing: [String]
        public let adding: [SocialLinkDraft]
        public var isEmpty: Bool { removing.isEmpty && adding.isEmpty }
    }

    public private(set) var current: [ProfileSocialLink]
    public private(set) var removed: [String] = []
    public private(set) var added: [SocialLinkDraft] = []

    public init(current: [ProfileSocialLink] = []) {
        self.current = current
    }

    /// The list as it will read after a save: the links kept, then the new ones.
    public var rows: [Row] {
        current.filter { !removed.contains($0.id) }.map(Row.saved) + added.map(Row.pending)
    }

    public var count: Int { rows.count }
    public var canAdd: Bool { count < Self.maximum }
    public var hasChanges: Bool { !removed.isEmpty || !added.isEmpty }
    public var plan: Plan { Plan(removing: removed, adding: added) }

    public mutating func add(_ draft: SocialLinkDraft) {
        guard draft.isValid, canAdd else { return }
        added.append(draft)
    }

    public mutating func remove(_ row: Row) {
        switch row {
        case .saved(let link):
            if !removed.contains(link.id) { removed.append(link.id) }
        case .pending(let draft):
            added.removeAll { $0.id == draft.id }
        }
    }

    /// Replaces a row with an edited draft. A draft that leaves a saved link as
    /// it was changes nothing.
    public mutating func replace(_ row: Row, with draft: SocialLinkDraft) {
        guard draft.isValid else { return }
        switch row {
        case .saved(let link):
            guard !draft.matches(link) else { return }
            remove(row)
            added.append(draft)
        case .pending(let old):
            guard let index = added.firstIndex(where: { $0.id == old.id }) else { return }
            added[index] = SocialLinkDraft(id: old.id, platform: draft.platform, handle: draft.handle,
                                           title: draft.title, url: draft.url)
        }
    }

    /// Reddit applied the staged removals and returned the list as it now is.
    public mutating func didRemove(_ list: [ProfileSocialLink]) {
        current = list
        removed = []
    }

    /// Reddit added the draft and returned the list as it now is.
    public mutating func didAdd(_ draftID: UUID, list: [ProfileSocialLink]) {
        current = list
        added.removeAll { $0.id == draftID }
    }
}
