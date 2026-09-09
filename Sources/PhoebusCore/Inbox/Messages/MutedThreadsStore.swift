import Foundation

/// Apollo's per-post "Mute Notifications" action. Reddit's public API has
/// no endpoint to suppress inbox-reply notifications for a thread you are
/// only watching, so this is a local list of muted post fullnames that
/// local reminder features (see `RemindMeScreen`) consult.
public enum MutedThreadsStore {
    private static let key = "com.pendo324.Phoebus.mutedThreadFullnames"

    public static func isMuted(_ fullname: String) -> Bool {
        Set(load()).contains(fullname)
    }

    public static func setMuted(_ fullname: String, muted: Bool) {
        var set = Set(load())
        if muted {
            set.insert(fullname)
        } else {
            set.remove(fullname)
        }
        UserDefaults.standard.set(Array(set), forKey: key)
    }

    private static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }
}
