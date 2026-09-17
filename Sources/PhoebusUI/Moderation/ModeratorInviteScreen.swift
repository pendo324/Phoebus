import SwiftUI
import PhoebusCore

/// Moderator list and invite flow: invite, accept, decline and remove-invite.
///
/// Reddit's public API has no endpoint listing pending moderator invites, so the
/// "Invited Moderators" section shows only invites made this session (kept in
/// memory).
public struct ModeratorInviteScreen: View {
    let subreddit: String
    let repository: RedditRepository
    let isViewedByMod: Bool

    @State private var moderators: [ModeratorListedUser] = []
    @State private var sessionInvited: [String] = []
    @State private var errorMessage: String?
    @State private var showingInviteSheet = false
    @State private var showingMessageModsSheet = false

    public init(subreddit: String, repository: RedditRepository, isViewedByMod: Bool) {
        self.subreddit = subreddit
        self.repository = repository
        self.isViewedByMod = isViewedByMod
    }

    public var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            Section("Moderators") {
                ForEach(moderators) { mod in
                    HStack {
                        SettingsLink("u/\(mod.name)") {
                            UserProfileScreen(username: mod.name, repository: repository)
                        }
                        Spacer()
                    }
                    .swipeActions {
                        if isViewedByMod {
                            Button("Remove Invitation", role: .destructive) {
                                Task { await remove(mod.name) }
                            }
                        }
                    }
                }
            }
            if !sessionInvited.isEmpty {
                Section("Invited Moderators") {
                    ForEach(sessionInvited, id: \.self) { name in
                        HStack {
                            Text("u/\(name)")
                            Spacer()
                            Text("Pending").font(.caption).foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button("Remove Invitation", role: .destructive) {
                                Task { await revokeInvite(name) }
                            }
                        }
                    }
                }
            }
        }
        .apolloFlatListAppearance()
        .navigationTitle("Moderators")
        .toolbar {
            // A generic user gets an in-app way to message the mod team, alongside the
            // mod-only "Invite User as Mod" button.
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingMessageModsSheet = true
                } label: {
                    Label("Message Moderators", systemImage: "envelope")
                }
            }
            if isViewedByMod {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingInviteSheet = true
                    } label: {
                        Label("Invite User as Mod", systemImage: "person.badge.plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingMessageModsSheet) {
            NavigationStack {
                ComposeMessageScreen(to: "r/\(subreddit)", repository: repository) {
                    showingMessageModsSheet = false
                }
            }
        }
        .sheet(isPresented: $showingInviteSheet) {
            NavigationStack {
                InviteModeratorSheet(subreddit: subreddit, repository: repository) { username in
                    sessionInvited.append(username)
                    showingInviteSheet = false
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            moderators = try await repository.fetchPublicModerators(subreddit: subreddit)
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    private func remove(_ username: String) async {
        do {
            try await repository.removeModerator(username: username, subreddit: subreddit)
            moderators.removeAll { $0.name == username }
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    private func revokeInvite(_ username: String) async {
        do {
            try await repository.revokeModeratorInvite(username: username, subreddit: subreddit)
            sessionInvited.removeAll { $0 == username }
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}

/// Alert copy: "Invite User as Mod" (title), "Username to Invite" (field
/// placeholder), "Invite (Full Permissions)" (submit action).
struct InviteModeratorSheet: View {
    let subreddit: String
    let repository: RedditRepository
    let onInvited: (String) -> Void

    @State private var username = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            Section {
                TextField("Username to Invite", text: $username)
                    #if os(iOS)
                    .autocapitalization(.none)
                    #endif
            }
            Section {
                Button {
                    Task { await invite() }
                } label: {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text("Invite (Full Permissions)")
                    }
                }
                .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
            }
        }
        .apolloFlatListAppearance()
        .navigationTitle("Invite User as Mod")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func invite() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await repository.inviteModerator(username: username, subreddit: subreddit)
            onInvited(username)
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}
