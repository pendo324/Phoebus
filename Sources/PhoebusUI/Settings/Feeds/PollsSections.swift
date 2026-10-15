import SwiftUI
import PhoebusCore

/// Polls: the Polls switch with its footer and a link to Web Sign-In, which polls
/// need, then "Option Text Alignment" as a value row. The sign-in itself is
/// Accounts & Security's.
struct PollsSections: View {
    @ObservedObject var accountManager: AccountManager
    @Setting(GeneralSettingsStore.storage) private var settings
    @State private var showingAlignment = false

    /// What the Web Sign-In link says about the active account's web session.
    private var webSignInStatus: String {
        guard let index = accountManager.activeIndex, index < accountManager.accounts.count else { return "No account" }
        return accountManager.accounts[index].webSession != nil ? "Ready" : "Not set up"
    }

    var body: some View {
        Group {
            Section {
                Toggle("Polls", isOn: $settings.pollsEnabled)
                    .apolloSearchRow("Polls")
                SettingsCrossLinkRow(link: .webSignIn, value: webSignInStatus,
                                     accountManager: accountManager, lastBeforeFooter: true)
            } header: {
                Text("Polls")
                    .apolloSectionHeader()
            } footer: {
                Text("Vote in polls and create your own, right inside Phoebus. Reddit's official app API doesn't offer polls, so voting and posting need the account signed in with a reddit.com web session. It is usually captured when you sign in; Web Sign-In shows whether it has been, and sets it up if not.\n\nExperimental — if anything looks off, please report it.")
                    .apolloSectionFooter()
            }

            Section {
                Button { showingAlignment = true } label: {
                    HStack {
                        Text("Option Text Alignment").foregroundStyle(.primary)
                        Spacer()
                        Text(settings.pollOptionAlignmentLeft ? "Left" : "Center")
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .apolloSearchRow("Option Text Alignment", lastBeforeFooter: true)
                // "Center" / "Left", the current one suffixed " (Current)".
                .confirmationDialog("Option Text Alignment", isPresented: $showingAlignment, titleVisibility: .visible) {
                    Button("Center" + (settings.pollOptionAlignmentLeft ? "" : " (Current)")) { $settings.update { $0.pollOptionAlignmentLeft = false } }
                    Button("Left" + (settings.pollOptionAlignmentLeft ? " (Current)" : "")) { $settings.update { $0.pollOptionAlignmentLeft = true } }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("How option text lines up next to its selection circle.")
                }
            } footer: {
                Text("How option text is aligned within the poll.")
                    .apolloSectionFooter()
            }
        }
    }
}
