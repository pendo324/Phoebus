import SwiftUI
import PhoebusCore

/// The screen a root row opens: one switch over the thirteen categories,
/// exhaustive, so a category added to Core does not compile until it has a
/// screen. Each screen draws its own sections (Core's `sections` is the
/// list the smoke suite checks them against) and pushes its drill-downs
/// through `SettingsDrillDownRow`.
public struct SettingsCategoryScreen: View {
    let category: SettingsCategory
    let accountManager: AccountManager

    public init(category: SettingsCategory, accountManager: AccountManager) {
        self.category = category
        self.accountManager = accountManager
    }

    public var body: some View {
        switch category {
        case .accountsSecurity: AccountsSecuritySettingsScreen(accountManager: accountManager)
        case .appearance: AppearanceSettingsScreen()
        case .posts: PostsSettingsScreen(accountManager: accountManager)
        case .feed: FeedSettingsScreen()
        case .comments: CommentsSettingsScreen()
        case .media: MediaSettingsScreen()
        case .linksSharing: LinksSharingSettingsScreen()
        case .filters: FiltersSettingsScreen()
        case .inboxNotifications: InboxNotificationsSettingsScreen()
        case .gesturesHaptics: GesturesHapticsSettingsScreen()
        case .integrations: IntegrationsSettingsScreen()
        case .dataStorage: DataStorageSettingsScreen()
        case .about: AboutScreen(accountManager: accountManager)
        }
    }
}

extension SettingsRowRequirement {
    /// The requirements met here: iOS 27, a release channel, and a
    /// session wherever a Sign Out action is installed.
    static func available(signOut: SettingsSignOutAction?) -> Set<SettingsRowRequirement> {
        var available: Set<SettingsRowRequirement> = []
        if #available(iOS 27.0, *) { available.insert(.iOS27) }
        if BuildChannel.current != nil { available.insert(.releaseChannel) }
        if signOut != nil { available.insert(.session) }
        return available
    }
}

// MARK: - Sign Out

/// Ends the Reddit session. The Settings tab installs it on its stack, so
/// every screen pushed there (search results and shortcuts included)
/// offers the same Sign Out; where it is absent, so is the row.
public struct SettingsSignOutAction {
    private let action: @MainActor () -> Void

    public init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    @MainActor func callAsFunction() { action() }
}

private struct SettingsSignOutKey: EnvironmentKey {
    static var defaultValue: SettingsSignOutAction? { nil }
}

public extension EnvironmentValues {
    var settingsSignOut: SettingsSignOutAction? {
        get { self[SettingsSignOutKey.self] }
        set { self[SettingsSignOutKey.self] = newValue }
    }
}
