import Foundation

/// The Reddit account preference "Blur mature (18+) images and media"
/// (`pref_no_profanity` on `/api/v1/me` and `/api/me.json`), kept per
/// account. "Blur NSFW Media → Reddit Setting" follows it, as
/// Apollo-Reborn's tag filters do.
public enum MatureMediaPreference {
    /// Lowercased username → the account's pref.
    public static let storage = SettingsStore<[String: Bool]>(
        key: "com.pendo324.Phoebus.matureMediaPreference") { [:] }

    public static func record(username: String, blursMatureMedia: Bool) {
        let key = username.lowercased()
        var prefs = storage.load()
        guard prefs[key] != blursMatureMedia else { return }
        prefs[key] = blursMatureMedia
        storage.save(prefs)
    }

    /// The active account's pref, or nil while it is unknown (signed
    /// out, or `/me` hasn't answered yet).
    public static func activeAccountValue(in prefs: [String: Bool]) -> Bool? {
        guard let username = FavoriteSubredditsAccountContext.currentUsernameProvider() else { return nil }
        return prefs[username.lowercased()]
    }
}

extension NSFWBlurOverride {
    /// Whether NSFW media is covered. An unknown account pref stays
    /// covered, so media is never wrongly exposed while it resolves.
    public func blursNSFW(accountPref: Bool?) -> Bool {
        switch self {
        case .always: return true
        case .never: return false
        case .redditSetting: return accountPref ?? true
        }
    }
}
