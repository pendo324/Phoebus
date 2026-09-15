import SwiftUI
import PhoebusCore

/// Moderator user-management screen.
///
/// Apollo reaches banned, muted and approved-submitter lists as three separate
/// menu rows. This screen shares one implementation but opens scoped to one list
/// per row, so there is no segmented control.
public struct ModeratorUsersScreen: View {
    /// Lives in PhoebusCore so the per-list titles and icon names are assertable
    /// without importing the UI layer.
    public typealias UserListKind = ModeratorUserList

    let subreddit: String
    let repository: RedditRepository

    @State private var selectedTab: UserListKind
    @State private var users: [ModeratorListedUser] = []
    @State private var errorMessage: String?
    @State private var showingAddSheet = false

    public init(subreddit: String, repository: RedditRepository, kind: UserListKind = .banned) {
        self.subreddit = subreddit
        self.repository = repository
        _selectedTab = State(initialValue: kind)
    }


    public var body: some View {
        VStack(spacing: 0) {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                ForEach(users) { user in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("u/\(user.name)").font(.headline)
                        if let reason = user.banReason, !reason.isEmpty {
                            Text(reason).font(.caption).foregroundStyle(.secondary)
                        }
                        if let note = user.note, !note.isEmpty {
                            Text(note).font(.caption2).foregroundStyle(.tertiary)
                        }
                        if let daysLeft = user.daysLeft {
                            Text("\(daysLeft) days left").font(.caption2).foregroundStyle(.orange)
                        }
                    }
                    .swipeActions {
                        Button("Remove", role: .destructive) {
                            Task { await remove(user) }
                        }
                    }
                }
            }
        }
        .apolloFlatListAppearance()
        .navigationTitle(selectedTab.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                    .accessibilityLabel("Add")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            NavigationStack {
                AddModeratorUserScreen(subreddit: subreddit, kind: selectedTab, repository: repository) {
                    showingAddSheet = false
                    Task { await load() }
                }
            }
        }
        .task(id: selectedTab) { await load() }
    }

    private func load() async {
        do {
            switch selectedTab {
            case .banned: users = try await repository.fetchBannedUsers(subreddit: subreddit)
            case .muted: users = try await repository.fetchMutedUsers(subreddit: subreddit)
            case .approved: users = try await repository.fetchApprovedSubmitters(subreddit: subreddit)
            }
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    private func remove(_ user: ModeratorListedUser) async {
        do {
            switch selectedTab {
            case .banned: try await repository.unbanUser(username: user.name, subreddit: subreddit)
            case .muted: try await repository.unmuteUser(username: user.name, subreddit: subreddit)
            case .approved: try await repository.removeApprovedSubmitter(username: user.name, subreddit: subreddit)
            }
            users.removeAll { $0.id == user.id }
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}

/// Add-user sheet; bans include reason, private mod note and duration.
struct AddModeratorUserScreen: View {
    let subreddit: String
    let kind: ModeratorUsersScreen.UserListKind
    let repository: RedditRepository
    let onDone: () -> Void

    @State private var username = ""
    @State private var reason = ""
    @State private var note = ""
    /// Separate "Note to User" field, shown to the banned user, distinct from the
    /// private mod note.
    @State private var banMessage = ""
    @State private var isPermanent = true
    @State private var durationDays = 3
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    /// Lets a mod pick one of the subreddit's rules as the ban reason, with a free-text
    /// "other reason" fallback.
    @State private var subredditRules: [SubredditRule] = []
    @State private var selectedRule: SubredditRule?

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            if kind == .muted {
                // Mute has its own "Reason (optional and private)" field, a private mod note
                // distinct from a ban's.
                Section("Reason (optional and private)") {
                    TextField("Visible only to other moderators", text: $note)
                }
            }
            Section {
                TextField("Username", text: $username)
                    #if os(iOS)
                    .autocapitalization(.none)
                    #endif
            }

            if kind == .banned {
                Section("Ban Reason") {
                    if !subredditRules.isEmpty {
                        Picker("Subreddit Rule", selection: $selectedRule) {
                            Text("Other (free text)").tag(SubredditRule?.none)
                            ForEach(subredditRules) { rule in
                                Text(rule.shortName).tag(SubredditRule?.some(rule))
                            }
                        }
                    }
                    if selectedRule == nil {
                        TextField("Ban Reason", text: $reason)
                    }
                }
                Section("Note to User") {
                    // Shown to the banned user, distinct from the private mod note below.
                    TextField("Message the banned user will see", text: $banMessage, axis: .vertical)
                }
                Section("Private Mod Note") {
                    TextField("Visible only to other moderators", text: $note)
                }
                Section("Duration") {
                    Toggle("Permanent", isOn: $isPermanent)
                    if !isPermanent {
                        Stepper("Duration: \(durationDays) days", value: $durationDays, in: 1...999)
                    }
                    // Live summary footer ("Permanently ban <user>" or N-day equivalent) confirming
                    // the ban's scope before submitting.
                    Text(isPermanent ? "This will permanently ban \(username.isEmpty ? "this user" : username)." : "This will ban \(username.isEmpty ? "this user" : username) for \(durationDays) day\(durationDays == 1 ? "" : "s").")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button {
                    Task { await submit() }
                } label: {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text("Add")
                    }
                }
                .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
            }
        }
        .apolloFlatListAppearance()
        .navigationTitle("Add \(kind.rawValue.dropLast()) User")
        .task {
            guard kind == .banned else { return }
            subredditRules = (try? await repository.fetchSubredditRules(name: subreddit)) ?? []
        }
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            switch kind {
            case .banned:
                try await repository.banUser(
                    username: username,
                    subreddit: subreddit,
                    reason: selectedRule?.violationReason ?? reason,
                    note: note,
                    banMessage: banMessage,
                    durationDays: isPermanent ? nil : durationDays
                )
            case .muted:
                try await repository.muteUser(username: username, subreddit: subreddit, note: note)
            case .approved:
                try await repository.addApprovedSubmitter(username: username, subreddit: subreddit)
            }
            onDone()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}
