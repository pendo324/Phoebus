import Foundation

/// Notification names posted across screens in PhoebusCore.
extension Notification.Name {
    /// Posted whenever `ProfileLayoutSettings` is saved, so every avatar
    /// re-reads the shared Profile Picture Shape.
    public static let apolloProfilePictureShapeChanged = Notification.Name("apollo.profilePictureShapeChanged")

    /// Posted when a tapped link resolved to a Reddit screen Apollo can
    /// render itself ("Open Reddit Links in Apollo"). A
    /// notification rather than a binding because link taps happen deep
    /// inside post/comment bodies with no path to the root navigation
    /// state; the root already owns a `navigationDestination(item:)`
    /// for this kind of target.
    public static let apolloOpenRedditTarget = Notification.Name("Phoebus.openRedditTarget")

    /// Re-tapping the already-selected tab pops that tab to its root,
    /// matching `UITabBarController`'s own behaviour. This rewrite
    /// draws both of its tab bars itself, so neither inherits that
    /// behaviour without this. A notification rather than a binding
    /// since the tab bars and the navigation state to clear live in
    /// different views; `userInfo["tab"]` carries the tab's id.
    public static let apolloTabReselected = Notification.Name("Phoebus.tabReselected")

    public static let apolloQuickAction = Notification.Name("apollo.quickAction")

    /// Gallery autoplay changed: an open grid starts/stops its tiles live.
    public static let apolloGalleryAutoplayChanged = Notification.Name("apollo.galleryAutoplayChanged")

    /// A post was marked read; `object` is its fullname.
    public static let apolloReadPostsChanged = Notification.Name("apollo.readPostsChanged")
    /// The active account's refresh token was refused (Reborn #1200).
    public static let apolloSessionExpired = Notification.Name("apollo.sessionExpired")
    /// A backup restore wrote accounts straight to the keychain.
    public static let apolloAccountsRestored = Notification.Name("Phoebus.accountsRestored")
    /// The active account was switched, added or removed.
    public static let apolloActiveAccountChanged = Notification.Name("Phoebus.activeAccountChanged")
}
