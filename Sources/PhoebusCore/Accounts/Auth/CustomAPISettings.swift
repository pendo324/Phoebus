import Foundation

/// Apollo-Reborn's "Custom API" settings: user-configurable Reddit
/// OAuth client ID, redirect URI, and User-Agent, rather than hardcoded
/// build-time constants. Phoebus never ships its own credentials;
/// every user registers their own Reddit app.
public struct CustomAPISettings: Codable, Sendable, Equatable {
    /// `nil` means "use the build-time default".
    public var redditClientID: String?
    /// Confidential Reddit apps (vs installed/PKCE apps) have a client
    /// secret alongside the client ID. `nil`/empty means no secret,
    /// the common case for an installed app.
    public var redditClientSecret: String?
    public var redditRedirectURI: String?
    /// A personalized User-Agent (`platform:app_id:version (by
    /// /u/username)`), not a shared default, helps avoid API-key
    /// revocation fingerprinting.
    public var userAgent: String?
    /// Imgur requires a registered client ID for new integrations.
    /// `nil` means Imgur features are unavailable until the user
    /// supplies their own.
    public var imgurClientID: String?
    /// Img Chest is an alternative upload host Apollo-Reborn added.
    /// `nil` means uploads are unavailable until the user supplies a key.
    public var imgChestAPIKey: String?
    /// Giphy's GIF picker requires a registered Giphy API key.
    public var giphyAPIKey: String?

    // Reborn "Universal OAuth Sign-In".

    /// When `true`, OAuth sign-in uses a plain in-app `WKWebView`
    /// instead of `ASWebAuthenticationSession`, so any redirect URI
    /// (including http/https Web app clients) works.
    public var useCustomOAuthSignIn: Bool

    public static let `default` = CustomAPISettings(redditClientID: nil, redditClientSecret: nil, redditRedirectURI: nil, userAgent: nil, imgurClientID: nil, imgChestAPIKey: nil, giphyAPIKey: nil, useCustomOAuthSignIn: true)

    public init(redditClientID: String?, redditClientSecret: String? = nil, redditRedirectURI: String?, userAgent: String?, imgurClientID: String?, imgChestAPIKey: String? = nil, giphyAPIKey: String? = nil, useCustomOAuthSignIn: Bool = true) {
        self.redditClientID = redditClientID
        self.redditClientSecret = redditClientSecret
        self.redditRedirectURI = redditRedirectURI
        self.userAgent = userAgent
        self.imgurClientID = imgurClientID
        self.imgChestAPIKey = imgChestAPIKey
        self.giphyAPIKey = giphyAPIKey
        self.useCustomOAuthSignIn = useCustomOAuthSignIn
    }

    /// Custom decode so settings persisted before `useCustomOAuthSignIn`
    /// existed still decode, defaulting it to `false`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        redditClientID = (try? container.decodeIfPresent(String.self, forKey: .redditClientID))
        redditClientSecret = (try? container.decodeIfPresent(String.self, forKey: .redditClientSecret))
        redditRedirectURI = (try? container.decodeIfPresent(String.self, forKey: .redditRedirectURI))
        userAgent = (try? container.decodeIfPresent(String.self, forKey: .userAgent))
        imgurClientID = (try? container.decodeIfPresent(String.self, forKey: .imgurClientID))
        imgChestAPIKey = (try? container.decodeIfPresent(String.self, forKey: .imgChestAPIKey))
        giphyAPIKey = (try? container.decodeIfPresent(String.self, forKey: .giphyAPIKey))
        useCustomOAuthSignIn = (try? container.decodeIfPresent(Bool.self, forKey: .useCustomOAuthSignIn)) ?? true
    }
}

public enum CustomAPISettingsStore {
    private static let key = "com.pendo324.Phoebus.customAPISettings"

    /// Every save applies the keys to the live config, including the
    /// settings screens' `@Setting` writes, so a change takes effect
    /// without a relaunch.
    public static let storage = SettingsStore<CustomAPISettings>(key: key, mirror: { settings, _ in
        apply(settings)
    }) { CustomAPISettings.default }

    public static func load() -> CustomAPISettings { storage.load() }

    /// Persists the settings and applies them immediately to the live
    /// config, so a change takes effect without a relaunch.
    public static func save(_ settings: CustomAPISettings) {
        storage.save(settings)
        apply(settings)
    }

    /// Applies persisted settings to the live config, at launch and
    /// whenever `save` is called.
    public static func applyPersisted() {
        apply(load())
    }

    /// A pasted key often carries a stray space or newline, which Reddit
    /// rejects as a different client (Reborn #1236 trims keys on save).
    public static func trimmed(_ value: String?) -> String? {
        let t = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return t?.isEmpty == false ? t : nil
    }

    private static func apply(_ settings: CustomAPISettings) {
        RedditOAuthConfig.clientID = trimmed(settings.redditClientID) ?? RedditOAuthConfig.defaultClientID
        RedditOAuthConfig.clientSecret = trimmed(settings.redditClientSecret) ?? ""
        RedditOAuthConfig.redirectURI = trimmed(settings.redditRedirectURI) ?? RedditOAuthConfig.defaultRedirectURI
        RedditAPIClient.userAgentOverride = (settings.userAgent?.isEmpty == false) ? settings.userAgent : nil
        ImgurClient.clientID = (settings.imgurClientID?.isEmpty == false) ? settings.imgurClientID : nil
        ImgChestClient.apiKey = (settings.imgChestAPIKey?.isEmpty == false) ? settings.imgChestAPIKey : nil
        GiphyClient.apiKey = (settings.giphyAPIKey?.isEmpty == false) ? settings.giphyAPIKey : nil
    }
}

extension CustomAPISettings: StoredSettingsModel {
    public static var store: SettingsStore<CustomAPISettings> { CustomAPISettingsStore.storage }
}
