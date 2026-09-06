import Foundation

/// "Open in App" deep-link routing for non-Reddit links (Apollo-Reborn).
/// Routes via Universal Links, not custom URL schemes, so there is no
/// `canOpenURL` probe: iOS opens the app when installed and falls back to the
/// web view otherwise.
public enum DedicatedAppLink {
    /// A service that can claim its own links, only those that route
    /// through Universal Links. Steam and YouTube use their own custom
    /// schemes (`SteamURLParser`/`YouTubeURLParser.nativeAppURL`) instead.
    public enum Service: String, Sendable, CaseIterable, Identifiable {
        case bluesky
        case github

        public var id: String { rawValue }

        /// Row titles are plain app names in alphabetical order. The section
        /// footer carries the explanation, so the rows do not repeat it.
        public var displayName: String {
            switch self {
            case .bluesky: return "Bluesky"
            case .github: return "GitHub"
            }
        }

        /// The registrable domains this service claims. A subdomain
        /// matches too, for example "gist.github.com matches
        /// github.com".
        public var domains: [String] {
            switch self {
            case .bluesky: return ["bsky.app"]
            case .github: return ["github.com"]
            }
        }

        /// Reborn's defaults keys.
        public var defaultsKey: String {
            switch self {
            case .bluesky: return "OpenLinksInBlueskyApp"
            case .github: return "OpenLinksInGitHubApp"
            }
        }
    }

    /// Case-insensitive host match against registrable domains, also
    /// matching any subdomain.
    public static func host(_ host: String?, matches domains: [String]) -> Bool {
        guard let host, !host.isEmpty else { return false }
        let lowered = host.lowercased()
        for domain in domains {
            if lowered == domain || lowered.hasSuffix("." + domain) { return true }
        }
        return false
    }

    /// The service that claims a URL, if any.
    public static func service(for url: URL) -> Service? {
        Service.allCases.first { host(url.host, matches: $0.domains) }
    }

    /// The `https://` URL to hand to Universal Links.
    /// The `https://` URL to hand to Universal Links. The scheme is forced to
    /// https, because a Universal Link only resolves for https; an `http://` link
    /// would otherwise silently never open the app.
    public static func universalLinkURL(for url: URL) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        return components?.url
    }

    /// Where an enabled "Open in App" service would open `url`: Bluesky, GitHub
    /// and Steam through their https Universal Links (Steam normalised to the
    /// store host), YouTube videos through `vnd.youtube://`. Nil when no enabled
    /// service claims it.
    public static func appTarget(for url: URL, defaults: UserDefaults = .standard,
                                 youTubeEnabled: Bool) -> (url: URL, universalLinksOnly: Bool)? {
        if shouldOpenInApp(url, defaults: defaults) != nil, let universal = universalLinkURL(for: url) {
            return (universal, true)
        }
        if defaults.bool(forKey: "OpenLinksInSteamApp"),
           host(url.host, matches: ["steampowered.com", "steamcommunity.com"]),
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.scheme = "https"
            if let h = components.host?.lowercased(), h == "steampowered.com" || h == "www.steampowered.com" {
                components.host = "store.steampowered.com"
            }
            if let steam = components.url { return (steam, true) }
        }
        if youTubeEnabled, let videoID = YouTubeURLParser.extractVideoID(from: url),
           let app = URL(string: "vnd.youtube://\(videoID)") {
            return (app, false)
        }
        return nil
    }

    /// Whether a URL should be routed to its app right now: the per-service
    /// toggle must be on. All of these default OFF (opt-in).
    public static func shouldOpenInApp(_ url: URL, defaults: UserDefaults = .standard) -> Service? {
        guard let service = service(for: url) else { return nil }
        guard defaults.bool(forKey: service.defaultsKey) else { return nil }
        return service
    }
}

/// The four toggles Apollo-Reborn's "Open in App" screen shows: Bluesky,
/// GitHub, Steam, YouTube. X/Twitter is absent since Apollo already ships
/// a native "Open Tweets in" picker. Only the two Universal-Links services
/// carry a raw defaults key here; Steam and YouTube's actual state lives
/// elsewhere (YouTube in `GeneralSettings`), so this enum must not add a
/// second key for them or the toggle and the reader would disagree.
public enum OpenInAppToggle: String, Sendable, CaseIterable, Identifiable {
    case bluesky
    case github
    case steam
    case youtube

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .bluesky: return "Bluesky"
        case .github: return "GitHub"
        case .steam: return "Steam"
        case .youtube: return "YouTube"
        }
    }

    /// The raw `UserDefaults` key, for the services stored that way.
    /// `nil` means the setting lives in `GeneralSettings` instead.
    public var rawDefaultsKey: String? {
        switch self {
        case .bluesky: return "OpenLinksInBlueskyApp"
        case .github: return "OpenLinksInGitHubApp"
        case .steam: return "OpenLinksInSteamApp"
        case .youtube: return nil
        }
    }

    /// Defaults to OFF for all of these (opt-in), as in Reborn; the
    /// `openVideosInYouTubeApp` default matches.
    public var isEnabled: Bool {
        get {
            if let key = rawDefaultsKey { return UserDefaults.standard.bool(forKey: key) }
            return GeneralSettingsStore.load().openVideosInYouTubeApp
        }
        nonmutating set {
            if let key = rawDefaultsKey {
                UserDefaults.standard.set(newValue, forKey: key)
                return
            }
            var settings = GeneralSettingsStore.load()
            settings.openVideosInYouTubeApp = newValue
            GeneralSettingsStore.save(settings)
        }
    }
}
