import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A community listed under "Content and activity": one the account is active
/// in, whose posts and comments can be shown on or hidden from the profile.
public struct ProfileActiveCommunity: Sendable, Equatable, Identifiable {
    public let id: String
    public let prefixedName: String
    public let iconURL: String?

    public init(id: String, prefixedName: String, iconURL: String? = nil) {
        self.id = id
        self.prefixedName = prefixedName
        self.iconURL = iconURL
    }

    init?(json: [String: Any]) {
        guard let id = json["id"] as? String, !id.isEmpty,
              let name = json["prefixedName"] as? String, !name.isEmpty else { return nil }
        self.init(id: id, prefixedName: name, iconURL: (json["styles"] as? [String: Any])?["icon"] as? String)
    }

    /// The account's own profile is the community `r/u_<name>`; reddit.com
    /// lists it as "Your profile posts".
    public var isProfile: Bool { prefixedName.hasPrefix("r/u_") }

    public var title: String { isProfile ? "Your profile posts" : prefixedName }
}

/// What the profile shows, as reddit.com's profile settings page reports it
/// (`identity.preferences`) and as it is staged for a save.
public struct ProfileVisibility: Sendable, Equatable {
    /// "Content and activity": everything, a chosen set of communities, or nothing.
    public enum Activity: Sendable, Equatable {
        case showAll
        case customize
        case hideAll
    }

    /// The staged choices. `visibleIDs` matters for `.customize` only.
    public struct Edits: Sendable, Equatable {
        public var activity: Activity
        public var visibleIDs: Set<String>
        public var showsNSFW: Bool
        public var showsFollowerCount: Bool

        public init(activity: Activity, visibleIDs: Set<String>, showsNSFW: Bool, showsFollowerCount: Bool) {
            self.activity = activity
            self.visibleIDs = visibleIDs
            self.showsNSFW = showsNSFW
            self.showsFollowerCount = showsFollowerCount
        }
    }

    /// The `input` of `UpdateProfilePrivacyPreferencesV2`.
    public struct PrivacyInput: Sendable, Equatable {
        public let shownSubredditIDs: [String]
        public let isHideAllContribution: Bool
        public let isHideProfileNsfw: Bool

        /// The page always sends `isShowTopSubreddits: true` with the rest.
        public var variables: [String: Any] {
            ["input": ["shownSubredditIds": shownSubredditIDs,
                       "isHideAllContribution": isHideAllContribution,
                       "isHideProfileNsfw": isHideProfileNsfw,
                       "isShowTopSubreddits": true] as [String: Any]]
        }
    }

    public let communities: [ProfileActiveCommunity]
    public let isHideAllContribution: Bool
    public let isHideProfileNsfw: Bool
    public let shownSubredditIDs: [String]
    public let showsFollowerCount: Bool
    /// The page greys these switches out when it reports their state DISABLED.
    public let isNSFWLocked: Bool
    public let isFollowerCountLocked: Bool
    public let isActivityLocked: Bool

    public init(communities: [ProfileActiveCommunity], isHideAllContribution: Bool, isHideProfileNsfw: Bool,
                shownSubredditIDs: [String], showsFollowerCount: Bool,
                isNSFWLocked: Bool = false, isFollowerCountLocked: Bool = false, isActivityLocked: Bool = false) {
        self.communities = communities
        self.isHideAllContribution = isHideAllContribution
        self.isHideProfileNsfw = isHideProfileNsfw
        self.shownSubredditIDs = shownSubredditIDs
        self.showsFollowerCount = showsFollowerCount
        self.isNSFWLocked = isNSFWLocked
        self.isFollowerCountLocked = isFollowerCountLocked
        self.isActivityLocked = isActivityLocked
    }

    /// Reads `identity.preferences`, `identity.preferencesState` and
    /// `identity.redditor.activeSubreddits` of the page's state.
    init?(state root: [String: Any]) {
        guard let identity = root["identity"] as? [String: Any],
              let preferences = identity["preferences"] as? [String: Any] else { return nil }
        let redditor = identity["redditor"] as? [String: Any]
        let locks = identity["preferencesState"] as? [String: Any]
        func disabled(_ key: String) -> Bool {
            (locks?[key] as? [String: Any])?["state"] as? String == "DISABLED"
        }
        self.init(
            communities: (redditor?["activeSubreddits"] as? [[String: Any]] ?? []).compactMap(ProfileActiveCommunity.init(json:)),
            isHideAllContribution: preferences["isHideAllContribution"] as? Bool ?? false,
            isHideProfileNsfw: preferences["isHideProfileNsfw"] as? Bool ?? false,
            shownSubredditIDs: preferences["shownSubredditIds"] as? [String] ?? [],
            showsFollowerCount: preferences["isShowFollowersCountEnabled"] as? Bool ?? false,
            isNSFWLocked: disabled("profileNSFWPreference"),
            isFollowerCountLocked: disabled("isShowFollowersCountEnabled"),
            isActivityLocked: disabled("isHideAllContribution"))
    }

    // MARK: Staging

    /// Hide all when the flag is set; else a customization when some, but not
    /// all, of the communities are chosen; else show all.
    public var edits: Edits {
        let ids = Set(communities.map(\.id))
        let chosen = Set(shownSubredditIDs).intersection(ids)
        let activity: Activity
        if isHideAllContribution {
            activity = .hideAll
        } else if !chosen.isEmpty && chosen.count < ids.count {
            activity = .customize
        } else {
            activity = .showAll
        }
        return Edits(activity: activity, visibleIDs: activity == .customize ? chosen : ids,
                     showsNSFW: !isHideProfileNsfw, showsFollowerCount: showsFollowerCount)
    }

    /// Chooses the communities that show. All of them is show all and none of
    /// them is hide all, as on reddit.com.
    public func settingVisible(_ visible: Set<String>, in edits: Edits) -> Edits {
        let chosen = visible.intersection(communities.map(\.id))
        var result = edits
        result.visibleIDs = chosen
        if chosen.isEmpty {
            result.activity = .hideAll
        } else if chosen.count == communities.count {
            result.activity = .showAll
        } else {
            result.activity = .customize
        }
        return result
    }

    /// Picks an option of "Content and activity" other than customize, which
    /// needs a choice of communities (`settingVisible`).
    public func settingActivity(_ activity: Activity, in edits: Edits) -> Edits {
        var result = edits
        result.activity = activity
        switch activity {
        case .showAll: result.visibleIDs = Set(communities.map(\.id))
        case .hideAll: result.visibleIDs = []
        case .customize: break
        }
        return result
    }

    /// What the page would send for these edits: `shownSubredditIds` is the
    /// chosen communities, and empty for show all and hide all.
    public func privacyInput(for edits: Edits) -> PrivacyInput {
        var hideAll = false
        var shown: [String] = []
        switch edits.activity {
        case .showAll:
            break
        case .hideAll:
            hideAll = true
        case .customize:
            shown = communities.map(\.id).filter(edits.visibleIDs.contains)
            if shown.isEmpty { hideAll = true }
            if shown.count == communities.count { shown = [] }
        }
        return PrivacyInput(shownSubredditIDs: shown, isHideAllContribution: hideAll, isHideProfileNsfw: !edits.showsNSFW)
    }

    public func hasPrivacyChanges(_ edits: Edits) -> Bool {
        let current = privacyInput(for: self.edits)
        let staged = privacyInput(for: edits)
        return current.isHideAllContribution != staged.isHideAllContribution
            || current.isHideProfileNsfw != staged.isHideProfileNsfw
            || current.shownSubredditIDs != staged.shownSubredditIDs
    }

    public func hasFollowerCountChange(_ edits: Edits) -> Bool { edits.showsFollowerCount != showsFollowerCount }

    public func hasChanges(_ edits: Edits) -> Bool { hasPrivacyChanges(edits) || hasFollowerCountChange(edits) }

    /// Merges what was applied into the state, as if the page were reloaded.
    public func applying(_ edits: Edits, privacy: Bool, followerCount: Bool) -> ProfileVisibility {
        let input = privacy ? privacyInput(for: edits) : nil
        return ProfileVisibility(
            communities: communities,
            isHideAllContribution: input?.isHideAllContribution ?? isHideAllContribution,
            isHideProfileNsfw: input?.isHideProfileNsfw ?? isHideProfileNsfw,
            shownSubredditIDs: input?.shownSubredditIDs ?? shownSubredditIDs,
            showsFollowerCount: followerCount ? edits.showsFollowerCount : showsFollowerCount,
            isNSFWLocked: isNSFWLocked, isFollowerCountLocked: isFollowerCountLocked, isActivityLocked: isActivityLocked)
    }
}

public enum ProfileVisibilityError: Error, LocalizedError, Equatable, Sendable {
    case requiresWebSession
    case rateLimited
    case rejected(String)

    public var errorDescription: String? {
        switch self {
        case .requiresWebSession:
            return "Changing what your profile shows needs a Reddit web sign-in."
        case .rateLimited:
            return "Reddit is rate limiting this. Wait a moment and try again."
        case .rejected(let message):
            return message
        }
    }
}

/// Profile Visibility over the Shreddit GraphQL endpoint reddit.com's profile
/// settings page uses, through a web session: `UpdateProfilePrivacyPreferencesV2`
/// sends the whole set each time, and the follower count is the account
/// preference `showFollowersCount` of `UpdateAccountPreferences`.
public enum ProfileVisibilityService {
    public static func save(_ input: ProfileVisibility.PrivacyInput, session: WebSessionCredential,
                            urlSession: URLSession? = nil) async throws {
        let json = try await perform(operation: "UpdateProfilePrivacyPreferencesV2", variables: input.variables,
                                     session: session, urlSession: urlSession)
        try check(json, field: "updateProfilePrivacyPreferencesV2", requiresPayload: true)
    }

    public static func saveFollowerCount(shown: Bool, session: WebSessionCredential,
                                         urlSession: URLSession? = nil) async throws {
        let json = try await perform(operation: "UpdateAccountPreferences",
                                     variables: ["input": ["showFollowersCount": shown]],
                                     session: session, urlSession: urlSession)
        try check(json, field: "updateAccountPreferences", requiresPayload: false)
    }

    private static func perform(operation: String, variables: [String: Any], session: WebSessionCredential,
                                urlSession: URLSession?) async throws -> [String: Any] {
        do {
            return try await ModmailWebService.perform(operation: operation, variables: variables, session: session,
                                                       referer: ProfileSocialLinksService.referer, urlSession: urlSession)
        } catch ModmailWebService.ServiceError.rateLimited {
            throw ProfileVisibilityError.rateLimited
        }
    }

    /// `data.<field>`: `{ok, errors}`. The account preferences reply has not
    /// been captured, so its payload is optional there: the page itself only
    /// looks at the top-level `errors`, which `perform` already refuses on.
    static func check(_ json: [String: Any], field: String, requiresPayload: Bool) throws {
        let payload = (json["data"] as? [String: Any])?[field] as? [String: Any]
        if payload == nil, requiresPayload {
            throw ProfileVisibilityError.rejected("Reddit's reply about your profile visibility could not be read.")
        }
        if let code = ModmailWebService.warningCode(in: json) {
            throw ProfileVisibilityError.rejected("Reddit accepted the request but did not apply it (\(code)).")
        }
        let failed = payload.map { $0["ok"] as? Bool == false || PollVoteService.hasErrors($0["errors"]) } ?? false
        guard !failed else {
            let first = (payload?["errors"] as? [Any])?.first
            let said = CommentSubmitFailure.sentence((first as? [String: Any])?["message"] as? String ?? (first as? String) ?? "")
            throw ProfileVisibilityError.rejected(said.isEmpty ? "Reddit didn't accept the change to what your profile shows." : said)
        }
        if requiresPayload, payload?["ok"] as? Bool != true {
            throw ProfileVisibilityError.rejected("Reddit didn't accept the change to what your profile shows.")
        }
    }
}
