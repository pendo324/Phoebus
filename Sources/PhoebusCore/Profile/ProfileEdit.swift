import Foundation

/// Phoebus's native "Edit Profile". A profile is the account's user subreddit
/// (`u_<name>`), so its display name, about text and toggles are subreddit
/// settings: read with `about/edit` and written back through `site_admin`,
/// which needs every setting on each call. "Allow People to Follow You" is an
/// account preference (`enable_followers`), not a subreddit setting.
public enum ProfileEditLimits {
    /// A display name over 30 characters makes `site_admin` answer HTTP 500
    /// (reddit.com's own editor allows 90 but saves through GraphQL, which needs
    /// a web session). The about limit is the reddit.com editor's.
    public static let displayName = 30
    public static let about = 200
}

/// Where the parts of a profile the editor leaves to the website are changed.
public enum ProfileEditLinks {
    /// reddit.com's profile settings: the avatar (a photo or Reddit's avatar
    /// builder), and anything else the editor doesn't cover.
    public static let webSettings = URL(string: "https://www.reddit.com/settings/profile")!
}

/// The fields the editor changes.
public struct ProfileEdits: Sendable, Equatable {
    public var displayName: String
    public var about: String
    public var isNSFW: Bool
    public var acceptsFollowers: Bool

    public init(displayName: String, about: String, isNSFW: Bool, acceptsFollowers: Bool) {
        self.displayName = displayName
        self.about = about
        self.isNSFW = isNSFW
        self.acceptsFollowers = acceptsFollowers
    }

    /// The text as Reddit would store it: edges trimmed, and a display name on
    /// one line.
    public var normalized: ProfileEdits {
        var copy = self
        copy.displayName = displayName
            .components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        copy.about = about.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }
}

public enum ProfileEditIssue: Sendable, Equatable {
    case displayNameTooLong(limit: Int)
    case aboutTooLong(limit: Int)

    public var message: String {
        switch self {
        case .displayNameTooLong(let limit): return "Display name can be up to \(limit) characters."
        case .aboutTooLong(let limit): return "About can be up to \(limit) characters."
        }
    }
}

public enum ProfileSettingsError: Error, LocalizedError, Sendable {
    case unreadable

    public var errorDescription: String? { "Reddit didn't send your profile settings." }
}

/// A save refused before it was sent, because Reddit would fail it.
public struct ProfileEditRefusal: Error, LocalizedError, Sendable, Equatable {
    public let issues: [ProfileEditIssue]

    public var errorDescription: String? { issues.map(\.message).joined(separator: " ") }
}

/// `GET /api/v1/me/prefs`, which holds the account's follow permission.
public enum ProfileFollowPreference {
    public static let key = "enable_followers"
    public static let path = "/api/v1/me/prefs"

    /// The preference as Reddit has it; nil when the response doesn't say.
    public static func parse(_ data: Data) -> Bool? {
        guard let root = try? JSONDecoder().decode([String: JSONValue].self, from: data),
              case .bool(let allowed)? = root[key] else { return nil }
        return allowed
    }

    /// The `PATCH /api/v1/me/prefs` body.
    public static func patchBody(_ allowed: Bool) -> [String: Any] { [key: allowed] }
}

/// A profile's settings as `GET /r/u_<name>/about/edit` returns them.
public struct ProfileSettings: Sendable, Equatable {
    /// The user subreddit's `t5_` fullname, which `site_admin` takes as `sr`.
    public let subredditFullname: String
    /// The editable fields as read.
    public let edits: ProfileEdits
    /// Every setting in `site_admin`'s own parameter names and form encoding.
    private let formValues: [String: String]

    /// `about/edit` names a few settings differently from the `site_admin`
    /// parameter that sets them. `default_set` is the "allow the community on
    /// r/all and in discovery" switch.
    static let renamedKeys: [String: String] = [
        "subreddit_id": "sr",
        "subreddit_type": "type",
        "content_options": "link_type",
        "default_set": "allow_top",
        "header_hover_text": "header-title",
        "language": "lang",
    ]

    public static func parse(_ data: Data, username: String) throws -> ProfileSettings {
        guard let root = try? JSONDecoder().decode([String: JSONValue].self, from: data),
              case .object(let settings)? = root["data"],
              case .string(let fullname)? = settings["subreddit_id"], !fullname.isEmpty else {
            throw ProfileSettingsError.unreadable
        }
        var values: [String: String] = [:]
        for (key, value) in settings {
            guard let text = value.formText else { continue }
            values[renamedKeys[key] ?? key] = text
        }
        func text(_ key: String) -> String {
            if case .string(let value)? = settings[key] { return value }
            return ""
        }
        func flag(_ key: String, default fallback: Bool) -> Bool {
            if case .bool(let value)? = settings[key] { return value }
            return fallback
        }
        // A profile with no display name carries Reddit's `u_<name>` fallback as its title.
        var title = text("title")
        if title.caseInsensitiveCompare("u_" + username) == .orderedSame { title = "" }
        return ProfileSettings(
            subredditFullname: fullname,
            edits: ProfileEdits(displayName: title, about: text("public_description"),
                                isNSFW: flag("over_18", default: false),
                                acceptsFollowers: flag("accept_followers", default: true)),
            formValues: values)
    }

    /// Whether `edits` differ from what was read, ignoring edge whitespace.
    public func hasChanges(_ edits: ProfileEdits) -> Bool {
        edits.normalized != self.edits.normalized
    }

    /// Whether a subreddit setting (everything but the follow permission) changed.
    public func hasSiteAdminChanges(_ edits: ProfileEdits) -> Bool {
        var compared = edits.normalized
        compared.acceptsFollowers = self.edits.acceptsFollowers
        return compared != self.edits.normalized
    }

    /// Whether the follow permission, an account preference, changed.
    public func hasFollowPreferenceChange(_ edits: ProfileEdits) -> Bool {
        edits.acceptsFollowers != self.edits.acceptsFollowers
    }

    /// The settings with the follow permission taken from the account's
    /// preference, which is where Reddit keeps it.
    public func settingFollowPermission(_ allowed: Bool) -> ProfileSettings {
        var values = formValues
        values["accept_followers"] = allowed ? "true" : "false"
        var edits = self.edits
        edits.acceptsFollowers = allowed
        return ProfileSettings(subredditFullname: subredditFullname, edits: edits, formValues: values)
    }

    /// Limits breached by a field that was edited; one left as Reddit has it
    /// is not held against the user.
    public func issues(for edits: ProfileEdits) -> [ProfileEditIssue] {
        let new = edits.normalized, old = self.edits.normalized
        var found: [ProfileEditIssue] = []
        if new.displayName != old.displayName,
           new.displayName.unicodeScalars.count > ProfileEditLimits.displayName {
            found.append(.displayNameTooLong(limit: ProfileEditLimits.displayName))
        }
        if new.about != old.about, new.about.unicodeScalars.count > ProfileEditLimits.about {
            found.append(.aboutTooLong(limit: ProfileEditLimits.about))
        }
        return found
    }

    /// The `site_admin` form: every setting read, with the editable fields
    /// replaced. `title` may not be empty, so a blank display name goes as the
    /// username, which is what the profile shows for one. A display name left
    /// alone is sent back as Reddit has it, and so is the follow permission:
    /// `site_admin` ignores `accept_followers` (see `ProfileFollowPreference`).
    public func siteAdminParameters(applying edits: ProfileEdits, username: String) -> [String: String] {
        let edits = edits.normalized
        var parameters = formValues
        parameters["api_type"] = "json"
        parameters["sr"] = subredditFullname
        parameters["name"] = "u_\(username)"
        if edits.displayName != self.edits.normalized.displayName {
            parameters["title"] = edits.displayName.isEmpty ? username : edits.displayName
        } else if (formValues["title"] ?? "").isEmpty {
            parameters["title"] = username
        }
        parameters["public_description"] = edits.about
        parameters["over_18"] = edits.isNSFW ? "true" : "false"
        return parameters
    }
}

private extension JSONValue {
    /// The value as a form field; nil for null, which `site_admin` reads as unset.
    var formText: String? {
        switch self {
        case .string(let text): return text
        case .bool(let flag): return flag ? "true" : "false"
        case .number(let number):
            return number == number.rounded() && abs(number) < 1e15 ? String(Int64(number)) : String(number)
        case .object, .array:
            guard let data = try? JSONSerialization.data(withJSONObject: plain, options: [.sortedKeys]) else { return nil }
            return String(data: data, encoding: .utf8)
        case .null: return nil
        }
    }
}
