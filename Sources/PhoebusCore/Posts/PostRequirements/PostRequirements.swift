import Foundation

/// A subreddit's moderator-set posting rules, from
/// `GET /api/v1/{subreddit}/post_requirements`. Every field is optional:
/// Reddit only sends what the moderators enabled, and unknown or null
/// fields are ignored. Phoebus-only; see docs/intentional-differences.md.
public struct PostRequirements: Decodable, Sendable, Equatable {
    public var titleRegexes: [String] = []
    public var titleBlacklistedStrings: [String] = []
    public var titleRequiredStrings: [String] = []
    public var titleTextMinLength: Int?
    public var titleTextMaxLength: Int?
    public var bodyRestrictionPolicy: String?
    public var bodyRegexes: [String] = []
    public var bodyBlacklistedStrings: [String] = []
    public var bodyRequiredStrings: [String] = []
    public var bodyTextMinLength: Int?
    public var bodyTextMaxLength: Int?
    public var linkRestrictionPolicy: String?
    public var domainBlacklist: [String] = []
    public var domainWhitelist: [String] = []
    public var linkRepostAge: Int?
    public var isFlairRequired = false
    public var galleryMinItems: Int?
    public var galleryMaxItems: Int?
    public var galleryCaptionsRequirement: String?
    public var galleryURLsRequirement: String?
    public var guidelinesText: String?
    public var guidelinesDisplayPolicy: String?

    enum CodingKeys: String, CodingKey {
        case titleRegexes = "title_regexes"
        case titleBlacklistedStrings = "title_blacklisted_strings"
        case titleRequiredStrings = "title_required_strings"
        case titleTextMinLength = "title_text_min_length"
        case titleTextMaxLength = "title_text_max_length"
        case bodyRestrictionPolicy = "body_restriction_policy"
        case bodyRegexes = "body_regexes"
        case bodyBlacklistedStrings = "body_blacklisted_strings"
        case bodyRequiredStrings = "body_required_strings"
        case bodyTextMinLength = "body_text_min_length"
        case bodyTextMaxLength = "body_text_max_length"
        case linkRestrictionPolicy = "link_restriction_policy"
        case domainBlacklist = "domain_blacklist"
        case domainWhitelist = "domain_whitelist"
        case linkRepostAge = "link_repost_age"
        case isFlairRequired = "is_flair_required"
        case galleryMinItems = "gallery_min_items"
        case galleryMaxItems = "gallery_max_items"
        case galleryCaptionsRequirement = "gallery_captions_requirement"
        case galleryURLsRequirement = "gallery_urls_requirement"
        case guidelinesText = "guidelines_text"
        case guidelinesDisplayPolicy = "guidelines_display_policy"
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func strings(_ key: CodingKeys) -> [String] {
            ((try? c.decodeIfPresent([String].self, forKey: key)) ?? nil) ?? []
        }
        func int(_ key: CodingKeys) -> Int? {
            if let value = (try? c.decodeIfPresent(Int.self, forKey: key)) ?? nil { return value }
            if let text = (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil { return Int(text) }
            return nil
        }
        func string(_ key: CodingKeys) -> String? {
            let value = (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil
            return value?.isEmpty == true ? nil : value
        }
        titleRegexes = strings(.titleRegexes)
        titleBlacklistedStrings = strings(.titleBlacklistedStrings)
        titleRequiredStrings = strings(.titleRequiredStrings)
        titleTextMinLength = int(.titleTextMinLength)
        titleTextMaxLength = int(.titleTextMaxLength)
        bodyRestrictionPolicy = string(.bodyRestrictionPolicy)
        bodyRegexes = strings(.bodyRegexes)
        bodyBlacklistedStrings = strings(.bodyBlacklistedStrings)
        bodyRequiredStrings = strings(.bodyRequiredStrings)
        bodyTextMinLength = int(.bodyTextMinLength)
        bodyTextMaxLength = int(.bodyTextMaxLength)
        linkRestrictionPolicy = string(.linkRestrictionPolicy)
        domainBlacklist = strings(.domainBlacklist)
        domainWhitelist = strings(.domainWhitelist)
        linkRepostAge = int(.linkRepostAge)
        isFlairRequired = ((try? c.decodeIfPresent(Bool.self, forKey: .isFlairRequired)) ?? nil) ?? false
        galleryMinItems = int(.galleryMinItems)
        galleryMaxItems = int(.galleryMaxItems)
        galleryCaptionsRequirement = string(.galleryCaptionsRequirement)
        galleryURLsRequirement = string(.galleryURLsRequirement)
        guidelinesText = string(.guidelinesText)
        guidelinesDisplayPolicy = string(.guidelinesDisplayPolicy)
    }

    /// The moderators' posting guidelines, trimmed; nil when there are none.
    public var guidelines: String? {
        let text = guidelinesText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    /// Whether the guidelines should start expanded. Reddit sends "all" for
    /// guidelines it shows to everyone; other values aren't documented, so
    /// anything that reads as "show" or "required" opens the note too.
    public var guidelinesStartExpanded: Bool {
        guard let policy = guidelinesDisplayPolicy?.lowercased() else { return false }
        return ["all", "full", "required", "always", "show", "visible"].contains(policy)
    }
}

/// What the user has written so far, as far as the rules care.
public struct PostDraft: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case text, link, image, video, gallery, poll }

    public var kind: Kind
    public var title: String
    public var body: String
    public var url: String
    public var flairSelected: Bool
    public var galleryItemCount: Int
    public var galleryHasCaptions: Bool
    public var galleryHasLinks: Bool

    public init(kind: Kind, title: String = "", body: String = "", url: String = "",
                flairSelected: Bool = false, galleryItemCount: Int = 0,
                galleryHasCaptions: Bool = false, galleryHasLinks: Bool = false) {
        self.kind = kind
        self.title = title
        self.body = body
        self.url = url
        self.flairSelected = flairSelected
        self.galleryItemCount = galleryItemCount
        self.galleryHasCaptions = galleryHasCaptions
        self.galleryHasLinks = galleryHasLinks
    }
}

/// One problem a draft has against the subreddit's rules. Only clear-cut
/// ones block posting; Reddit stays the authority on the rest.
public struct PostRequirementViolation: Sendable, Equatable {
    public enum Field: Sendable, Equatable { case title, body, link, flair, gallery }

    public let field: Field
    public let message: String
    public let isBlocking: Bool
}

extension PostRequirements {
    /// Ordered problems for `draft`: title, body, link, gallery, flair.
    /// Empty fields don't trip content rules (the composer already needs a
    /// title), and invalid regexes are ignored.
    public func violations(for draft: PostDraft) -> [PostRequirementViolation] {
        var found: [PostRequirementViolation] = []
        func add(_ field: PostRequirementViolation.Field, _ message: String, blocking: Bool = false) {
            found.append(PostRequirementViolation(field: field, message: message, isBlocking: blocking))
        }

        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            if let max = titleTextMaxLength, max > 0, title.count > max {
                add(.title, "Title is \(title.count - max) over the \(max)-character limit.", blocking: true)
            }
            if let min = titleTextMinLength, min > 0, title.count < min {
                add(.title, "Title needs at least \(min) characters.")
            }
            if let word = Self.firstContained(titleBlacklistedStrings, in: title) {
                add(.title, "Title can't contain \u{201C}\(word)\u{201D}.")
            }
            if !titleRequiredStrings.isEmpty, Self.firstContained(titleRequiredStrings, in: title) == nil {
                add(.title, "Title must contain one of: \(titleRequiredStrings.joined(separator: ", ")).")
            }
            if Self.violatesRegexes(titleRegexes, text: title) {
                add(.title, "Title doesn't match this community's required format.")
            }
        }

        if draft.kind == .text {
            let body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
            switch bodyRestrictionPolicy?.lowercased() {
            case "required" where body.isEmpty:
                add(.body, "This community requires text in the post.", blocking: true)
            case "notallowed" where !body.isEmpty:
                add(.body, "This community doesn't allow text in posts.", blocking: true)
            default:
                break
            }
            if !body.isEmpty {
                if let max = bodyTextMaxLength, max > 0, body.count > max {
                    add(.body, "Text is \(body.count - max) over the \(max)-character limit.")
                }
                if let min = bodyTextMinLength, min > 0, body.count < min {
                    add(.body, "Text needs at least \(min) characters.")
                }
                if let word = Self.firstContained(bodyBlacklistedStrings, in: body) {
                    add(.body, "Text can't contain \u{201C}\(word)\u{201D}.")
                }
                if !bodyRequiredStrings.isEmpty, Self.firstContained(bodyRequiredStrings, in: body) == nil {
                    add(.body, "Text must contain one of: \(bodyRequiredStrings.joined(separator: ", ")).")
                }
                if Self.violatesRegexes(bodyRegexes, text: body) {
                    add(.body, "Text doesn't match this community's required format.")
                }
            }
        }

        if draft.kind == .link {
            let link = draft.url.trimmingCharacters(in: .whitespacesAndNewlines)
            if linkRestrictionPolicy?.lowercased() == "notallowed" {
                add(.link, "This community doesn't allow link posts.")
            }
            if let host = Self.host(of: link) {
                if let domain = domainBlacklist.first(where: { Self.host(host, matches: $0) }) {
                    add(.link, "Links to \(domain) aren't allowed here.", blocking: true)
                } else if !domainWhitelist.isEmpty, !domainWhitelist.contains(where: { Self.host(host, matches: $0) }) {
                    add(.link, "Links must be from: \(domainWhitelist.joined(separator: ", ")).")
                }
            }
        }

        if draft.kind == .gallery {
            if let min = galleryMinItems, min > 0, draft.galleryItemCount < min {
                add(.gallery, "Galleries need at least \(min) images.")
            }
            if let max = galleryMaxItems, max > 0, draft.galleryItemCount > max {
                add(.gallery, "Galleries can have at most \(max) images.")
            }
            if Self.isRequired(galleryCaptionsRequirement), !draft.galleryHasCaptions {
                add(.gallery, "Every image needs a caption.")
            }
            if Self.isRequired(galleryURLsRequirement), !draft.galleryHasLinks {
                add(.gallery, "Every image needs a link.")
            }
        }

        if isFlairRequired, !draft.flairSelected {
            add(.flair, "This community requires a flair.", blocking: true)
        }
        return found
    }

    private static func isRequired(_ requirement: String?) -> Bool {
        requirement?.lowercased() == "required"
    }

    /// First list entry found in `text`, ignoring case.
    private static func firstContained(_ strings: [String], in text: String) -> String? {
        strings.first { !$0.isEmpty && text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// True when regexes are present and none of the valid ones matches.
    private static func violatesRegexes(_ patterns: [String], text: String) -> Bool {
        let regexes = patterns.compactMap { try? NSRegularExpression(pattern: $0) }
        guard !regexes.isEmpty else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return !regexes.contains { $0.firstMatch(in: text, range: range) != nil }
    }

    private static func host(of urlString: String) -> String? {
        guard !urlString.isEmpty else { return nil }
        let candidate = urlString.contains("://") ? urlString : "https://" + urlString
        guard let host = URL(string: candidate)?.host?.lowercased(), host.contains(".") else { return nil }
        return host
    }

    /// `host` is `domain` or one of its subdomains; a leading `www.` on
    /// either side is ignored.
    private static func host(_ host: String, matches domain: String) -> Bool {
        func bare(_ value: String) -> String {
            let lower = value.lowercased()
            return lower.hasPrefix("www.") ? String(lower.dropFirst(4)) : lower
        }
        let target = bare(domain)
        guard !target.isEmpty else { return false }
        let candidate = bare(host)
        return candidate == target || candidate.hasSuffix("." + target)
    }
}
