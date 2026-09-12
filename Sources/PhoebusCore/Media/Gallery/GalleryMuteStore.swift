import Foundation

/// Whether gallery videos play muted, shared by every page and remembered
/// across launches.
///
/// Reborn keeps one flag for the whole viewer and every player reads it as
/// it is created, so a page that builds its player later still sees it.
/// Mute is sticky across pages and launches. The default is muted, because
/// audio starting unprompted in a scrolling gallery is the worse surprise.
public enum GalleryMuteStore {
    /// Reborn's key (`ApolloGalleryVideosMuted`), so existing choices carry over.
    public static let key = "ApolloGalleryVideosMuted"

    public static var isMuted: Bool {
        get {
            // Absent means muted: read the object first, so a missing value is YES
            // rather than `boolForKey`'s default of NO.
            guard UserDefaults.standard.object(forKey: key) != nil else { return true }
            return UserDefaults.standard.bool(forKey: key)
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
