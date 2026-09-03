import Foundation

/// Shared cache for feed data between the main app and the widget
/// extension, backed by an App Group container. Lets the widget show the
/// user's personalized feed instead of only the public unauthenticated
/// API; without the App Group, `TopPostWidget` uses its public-API fallback.
public enum SharedFeedCache {
    /// The group identifier in both .entitlements files.
    public static let appGroupID = "group.com.pendo324.Phoebus"

    /// The group this install actually has. Re-signing services rename every
    /// app group to `<group>.<TEAMID>`, recording the new names under
    /// `ALTAppGroups` in the Info.plist, so the declared name has no container
    /// on a re-signed install. The extension reads the host app's Info.plist
    /// too, in case only the app's was rewritten.
    ///
    /// A certificate signer can't create groups; it signs with the
    /// provisioning profile's own entitlements, whose groups have the
    /// certificate's names. The app can't ask iOS which groups it was given,
    /// but the signer embeds that profile (`embedded.mobileprovision`), so its
    /// groups are tried too.
    public static let resolvedAppGroupID: String = {
        let bundles = [Bundle.main.bundleURL, hostAppBundleURL()].compactMap { $0 }
        return resolveAppGroupID(
            infoDictionaries: bundles.map { Bundle(url: $0)?.infoDictionary },
            profileGroups: bundles.flatMap { EmbeddedProfile(bundleURL: $0)?.appGroups ?? [] }
        ) { group in
            #if canImport(Darwin)
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil
            #else
            false
            #endif
        }
    }()

    /// The first candidate with a container: `ALTAppGroups`' rename of
    /// `appGroupID`, then the declared name, then the embedded profile's
    /// groups in order (the app and widget share one profile, so they
    /// settle on the same group).
    public static func resolveAppGroupID(infoDictionaries: [[String: Any]?], profileGroups: [String] = [],
                                         hasContainer: (String) -> Bool) -> String {
        let renamed = infoDictionaries.compactMap { $0?["ALTAppGroups"] as? [String] }
            .flatMap { $0 }
            .filter { $0 == appGroupID || $0.hasPrefix(appGroupID + ".") }
            .sorted { $0.count < $1.count }
        let candidates = renamed + [appGroupID] + profileGroups.sorted()
        return candidates.first(where: hasContainer) ?? renamed.first ?? appGroupID
    }

    /// From inside an app extension (`App.app/PlugIns/X.appex`), the
    /// containing app's bundle.
    static func hostAppBundleURL() -> URL? {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "appex" else { return nil }
        return url.deletingLastPathComponent().deletingLastPathComponent()
    }

    private static let topPostKey = "cachedTopPost"
    private static let cachedAtKey = "cachedTopPostDate"
    /// A POOL, not one post. The widget suite rotates through a pool of
    /// posts, and Home is the one source with no public endpoint, so it can
    /// only come from what the app already fetched.
    private static let postsKey = "cachedHomePosts"
    private static let credentialsKey = "widgetCredentials"

    /// Files in the shared App Group container, not `UserDefaults`: on the
    /// simulator `cfprefsd` resolves the suite to a per-process domain, so
    /// the two processes disagree about where the data lives.
    private static var containerURL: URL? {
        // App Groups are a Darwin concept; the Linux build of this
        // package (smoke tests, CI) has no such container and simply
        // does not share anything.
        #if canImport(Darwin)
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: resolvedAppGroupID)
        #else
        return nil
        #endif
    }

    private static func url(for key: String) -> URL? {
        containerURL?.appendingPathComponent("\(key).json")
    }

    private static func write(_ data: Data?, key: String) {
        guard let url = url(for: key) else { return }
        guard let data else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        // Atomic so a widget reading mid-write never sees a truncated
        // file and decodes it as "no credentials". Encrypted at rest
        // (this holds the widget's credentials), but readable after the
        // first unlock, since widgets refresh in the background.
        #if os(iOS)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try? data.write(to: url, options: .atomic)
        #endif
    }

    private static func read(key: String) -> Data? {
        guard let url = url(for: key) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Called by the main app after each successful home-feed load, so
    /// the widget has fresh personalized data to show without needing
    /// its own authenticated network access.
    public static func store(topPost: RedditPost) {
        guard let data = try? JSONEncoder.reddit.encode(topPost) else { return }
        write(data, key: topPostKey)
        write(try? JSONEncoder.reddit.encode(Date()), key: cachedAtKey)
    }

    /// Stores the home feed's leading posts for the rotating widgets.
    ///
    /// Capped because this crosses an App Group container; 50 matches the
    /// largest pool any widget asks for.
    public static func store(posts: [RedditPost]) {
        let capped = Array(posts.prefix(50))
        guard let data = try? JSONEncoder.reddit.encode(capped) else { return }
        write(data, key: postsKey)
        write(try? JSONEncoder.reddit.encode(Date()), key: cachedAtKey)
        // Keep the single-post key in step so the single-post widget and the
        // pool never disagree about what "top" means.
        if let first = capped.first { store(topPost: first) }
    }

    /// The cached home pool, newest-first as the feed returned it.
    public static func loadPosts() -> [RedditPost]? {
        guard let data = read(key: postsKey) else { return nil }
        return (try? JSONDecoder.reddit.decode(LossyArray<RedditPost>.self, from: data))?.elements
    }

    /// Returns the cached post plus how long ago it was cached, or nil
    /// if the App Group isn't set up yet or nothing has been cached.
    public static func loadTopPost() -> (post: RedditPost, cachedAt: Date)? {
        guard let data = read(key: topPostKey),
              let post = try? JSONDecoder.reddit.decode(RedditPost.self, from: data),
              let dateData = read(key: cachedAtKey),
              let cachedAt = try? JSONDecoder.reddit.decode(Date.self, from: dateData) else {
            return nil
        }
        return (post, cachedAt)
    }

    // MARK: - Widget credentials

    /// The signed-in account's transport credentials, shared with the widget
    /// extension so its own fetches are authenticated (Reddit's public JSON
    /// endpoints return 403 without credentials). The widget cannot sign in
    /// itself, so this stands in for Reborn's widget Setup Code.
    public struct WidgetCredentials: Codable, Sendable {
        /// Cookie header for the keyless/"Web JSON" transport.
        public var cookieHeader: String?
        /// OAuth bearer, when the account signed in that way.
        public var accessToken: String?
        /// When the bearer stops working. Cookies carry no expiry we
        /// can see, so this is nil for them.
        public var expiration: Date?
        /// Browser UA for cookie auth, OAuth UA for bearer auth; the two
        /// transports must not share an identity (see
        /// `RedditAPIClient.authorizedRequest`).
        public var userAgent: String
        /// What the widget needs to renew an expired bearer itself: the bearer
        /// lasts an hour and widgets refresh while the app is closed.
        public var refreshToken: String?
        public var clientID: String?
        public var clientSecret: String?

        public init(cookieHeader: String?, accessToken: String?,
                    expiration: Date?, userAgent: String,
                    refreshToken: String? = nil, clientID: String? = nil, clientSecret: String? = nil) {
            self.cookieHeader = cookieHeader
            self.accessToken = accessToken
            self.expiration = expiration
            self.userAgent = userAgent
            self.refreshToken = refreshToken
            self.clientID = clientID
            self.clientSecret = clientSecret
        }

        public var hasFreshBearer: Bool {
            guard let accessToken, !accessToken.isEmpty else { return false }
            return expiration.map { Date() < $0 } ?? true
        }

        public var hasCookie: Bool { cookieHeader?.isEmpty == false }

        public var canRefreshBearer: Bool {
            refreshToken?.isEmpty == false && clientID?.isEmpty == false
        }

        public var isUsable: Bool {
            hasFreshBearer || hasCookie || canRefreshBearer
        }
    }

    /// Publishes (or clears, passing nil) the widget's credentials.
    public static func store(credentials: WidgetCredentials?) {
        write(credentials.flatMap { try? JSONEncoder.reddit.encode($0) }, key: credentialsKey)
    }

    public static func loadCredentials() -> WidgetCredentials? {
        guard let data = read(key: credentialsKey) else { return nil }
        return try? JSONDecoder.reddit.decode(WidgetCredentials.self, from: data)
    }

    /// How this install shares with its widgets, for Widget Setup.
    public struct SharingStatus: Sendable {
        public let appGroup: String
        public let appGroupAvailable: Bool
        /// The App ID this install was signed as, when it differs from
        /// its bundle identifier; nil when they agree.
        public let mismatchedAppID: String?
    }

    public static var sharingStatus: SharingStatus {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let mismatch = EmbeddedProfile(bundleURL: Bundle.main.bundleURL)
            .flatMap { $0.signsAsItself(bundleIdentifier: bundleID) ? nil : $0.appID }
        return SharingStatus(appGroup: resolvedAppGroupID, appGroupAvailable: containerURL != nil,
                             mismatchedAppID: mismatch)
    }
}

extension JSONEncoder {
    public static let reddit: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()
}

/// The provisioning profile a signer embedded in a bundle
/// (`embedded.mobileprovision`): a signed container around a plist,
/// whose entitlements say what the install was granted.
public struct EmbeddedProfile: Sendable {
    public let appGroups: [String]
    /// The App ID the profile signs every bundle as, without the team
    /// prefix: `com.example.app`, or a wildcard such as `*`.
    public let appID: String?

    public init?(bundleURL: URL) {
        guard let data = try? Data(contentsOf: bundleURL.appendingPathComponent("embedded.mobileprovision")) else { return nil }
        self.init(profileData: data)
    }

    /// The plist sits in the container unencrypted, so it is cut out
    /// between its own `<?xml` and `</plist>`.
    public init?(profileData data: Data) {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                from: data.subdata(in: start.lowerBound..<end.upperBound), format: nil) as? [String: Any]
        else { return nil }
        let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]
        appGroups = entitlements["com.apple.security.application-groups"] as? [String] ?? []
        appID = (entitlements["application-identifier"] as? String).map { identifier in
            guard let dot = identifier.firstIndex(of: ".") else { return identifier }
            return String(identifier[identifier.index(after: dot)...])
        }
    }

    /// Whether a bundle signed with this profile is known to the system
    /// by its own identifier. Shortcuts' daemon names a caller by the
    /// `application-identifier` it was signed with, not by its
    /// `CFBundleIdentifier`, and turns away callers whose name matches
    /// no installed app. Configurable widgets resolve their settings
    /// through that daemon, so under a mismatched explicit App ID they
    /// never get past the placeholder.
    public func signsAsItself(bundleIdentifier: String) -> Bool {
        guard let appID else { return true }
        if appID.hasSuffix("*") { return bundleIdentifier.hasPrefix(appID.dropLast()) }
        return appID == bundleIdentifier
    }
}
