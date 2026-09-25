import SwiftUI
import PhoebusCore

/// Polls: the Polls switch with its footer, "Option Text Alignment" as a value
/// row, and a "Reddit Sign-In" section whose cell and footer depend on the active
/// account's web session.
public struct PollsSettingsScreen: View {
    @ObservedObject private var accountManager: AccountManager
    @Setting(GeneralSettingsStore.storage) private var settings
    @State private var showingAlignment = false
    @State private var showingSignedInSheet = false
    @State private var showingWebLogin = false

    public init(accountManager: AccountManager) { self.accountManager = accountManager }

    private var activeUsername: String? {
        guard let index = accountManager.activeIndex, index < accountManager.accounts.count else { return nil }
        return accountManager.accounts[index].username
    }

    private var activeHasSession: Bool {
        guard let index = accountManager.activeIndex, index < accountManager.accounts.count else { return false }
        return accountManager.accounts[index].webSession != nil
    }

    public var body: some View {
        List {
            Section {
                Toggle("Polls", isOn: $settings.pollsEnabled)
                    .apolloSearchRow("Polls", lastBeforeFooter: true)
            } footer: {
                Text("Vote in polls and create your own, right inside Phoebus. Reddit's official app API doesn't offer polls, so Apollo Reborn handles them through your reddit.com web session — captured automatically when you sign in, so there's usually nothing to set up.\n\nExperimental — if anything looks off, please report it.")
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
            } footer: {
                Text("How option text is aligned within the poll.")
                    .apolloSectionFooter()
            }

            Section {
                signInCell
                    // Kept on Apollo's row insets (with a rule) rather than the system default. The
                    // signed-out case is not a control but gets the same geometry so its title lines
                    // up with every other row.
                    .apolloPlainSettingsRowInsets(rule: false)
            } header: {
                Text("Reddit Sign-In")
                    .apolloSectionHeader()
            } footer: {
                Text(signInFooter)
                    .apolloSectionFooter()
            }
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle("Polls")
        .navigationBarTitleDisplayModeIfAvailable()
        // "Center" / "Left", the current one suffixed " (Current)".
        .confirmationDialog("Option Text Alignment", isPresented: $showingAlignment, titleVisibility: .visible) {
            Button("Center" + (settings.pollOptionAlignmentLeft ? "" : " (Current)")) { $settings.update { $0.pollOptionAlignmentLeft = false } }
            Button("Left" + (settings.pollOptionAlignmentLeft ? " (Current)" : "")) { $settings.update { $0.pollOptionAlignmentLeft = true } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("How option text lines up next to its selection circle.")
        }
        // The signed-in confirmation sheet.
        .confirmationDialog("u/\(activeUsername ?? "") is signed in", isPresented: $showingSignedInSheet, titleVisibility: .visible) {
            Button("Sign In Again") { showingWebLogin = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sign in again only if polls have stopped working.")
        }
        .sheet(isPresented: $showingWebLogin) {
            NavigationStack {
                WebSessionLoginScreen(
                    requiredUsername: activeUsername,
                    onSuccess: { credential in
                        accountManager.addWebSessionAccount(credential)
                        showingWebLogin = false
                    },
                    onCancel: { showingWebLogin = false })
            }
        }
    }

    @ViewBuilder
    private var signInCell: some View {
        if let username = activeUsername {
            if activeHasSession {
                Button { showingSignedInSheet = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("u/\(username)").foregroundStyle(.primary)
                            Text("Ready to vote and post").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        // A green check reads as "connected" at a glance.
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
            } else {
                Button { showingWebLogin = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Set Up Reddit Sign-In").foregroundStyle(Color.apolloAccent)
                            Text("One quick sign-in for u/\(username)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("No Account Signed In").foregroundStyle(.secondary)
                Text("Sign in to a Reddit account to use polls.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var signInFooter: String {
        guard let username = activeUsername else {
            return "Sign in to a Reddit account in Phoebus first — polls act as whichever account you're using."
        }
        if activeHasSession {
            return "You're all set. Voting and posting happen silently from now on. If polls ever stop working, tap above to sign in again."
        }
        return "u/\(username) needs a one-time reddit.com sign-in for polls. This is usually captured automatically at sign-in — you'll only see it here if you signed in before polls existed, or through Apple's system login. After this, voting and posting are instant.\n\nYou sign in on reddit.com directly; Phoebus never sees your password."
    }
}
