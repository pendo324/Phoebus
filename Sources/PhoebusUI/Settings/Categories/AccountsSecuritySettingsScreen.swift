import SwiftUI
import PhoebusCore

/// Accounts & Security: who is signed in and how, the API keys that
/// sign-in and uploads need, the passcode, and signing out. Reborn's
/// Accounts & API Keys screen and Apollo's account switcher and Face ID &
/// Passcode screen are its sections.
public struct AccountsSecuritySettingsScreen: View {
    @ObservedObject var accountManager: AccountManager
    @Environment(\.settingsSignOut) private var signOut
    @StateObject private var switcher = AccountSwitcherModel()
    /// The Sign Out action waiting for its confirmation.
    @State private var confirmation: SettingsCategoryAction?

    public init(accountManager: AccountManager) {
        self.accountManager = accountManager
    }

    public var body: some View {
        List {
            AccountSwitcherSections(accountManager: accountManager, model: switcher, showsAddRow: true)
            SignInSections(accountManager: accountManager)
            PerAccountSettingsSections(accountManager: accountManager)
            APIKeySections()
            YouTubeSections()
            PasscodeSections()
            if let signOut {
                Section {
                    Button("Sign Out", role: .destructive) {
                        confirmation = SettingsCategoryAction(
                            id: "signOut",
                            title: "Sign Out?",
                            message: "Phoebus will forget the Reddit account signed in on this device. "
                                + "You can sign back in at any time.",
                            confirmTitle: "Sign Out",
                            perform: { signOut() })
                    }
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("settings.signOut")
                    .apolloSearchRow("Sign Out") // search: requires session
                }
            }
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle(SettingsCategory.accountsSecurity.title)
        .navigationBarTitleDisplayModeIfAvailable()
        .toolbar {
            // Reorders and removes accounts.
            if accountManager.accounts.count > 1 {
                ToolbarItem(placement: .primaryAction) { EditButton() }
            }
        }
        .apolloSettingsActionConfirmation($confirmation) { action in
            action.perform()
        }
    }
}
