import SwiftUI
import PhoebusCore

#if DEBUG
/// Debug-only modmail fixture injection. New modmail needs an OAuth account that
/// moderates something; this loads a fixture in Reddit's shape through the same
/// `ModmailConversationDetail.decode` the network path uses, so the real decode
/// and rendering are exercised without one. Compiled out of release builds.
enum ModmailFixture {
    static func load() -> ModmailConversationDetail? {
        guard let raw = ProcessInfo.processInfo.environment["APOLLO_MODMAIL_FIXTURE"],
              let data = raw.data(using: .utf8) else { return nil }
        return try? ModmailConversationDetail.decode(from: data)
    }
}
#endif

/// Modmail inbox: search-as-you-type over subject/conversation ID, and a subreddit
/// selector (filter to one moderated subreddit, since modmail spans all of them).
/// Five tabs (`ModmailInboxTab`, with verbatim per-tab empty-state strings):
/// Notifications / Mod Discussions / Highlighted / Archived / In Progress.
public struct ModmailListScreen: View {
    let repository: RedditRepository

    @State private var conversations: [ModmailConversation] = []
    @State private var errorMessage: String?
    @State private var searchQuery = ""
    @State private var selectedSubreddit: String?
    @State private var selectedTab: ModmailInboxTab = .notifications
    @State private var sortOrder: ModmailSortOption = .recent
    @State private var nextPage: String?
    @State private var isLoadingMore = false
    /// Bumped per reload, so a page for the previous mailbox or sort cannot be
    /// appended to the new one.
    @State private var loadGeneration = 0

    public init(repository: RedditRepository) {
        self.repository = repository
    }

    public var body: some View {
        VStack(spacing: 0) {
            List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            if filteredConversations.isEmpty && errorMessage == nil {
                // Apollo's per-tab empty-state copy; see `ModmailInboxTab.emptyStateText`.
                Text(selectedTab.emptyStateText).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(filteredConversations) { conversation in
                modmailRow(conversation)
                    .onAppear {
                        if conversation.id == conversations.last?.id { Task { await loadMore() } }
                    }
            }
            }
        }
        // Filters the already-fetched conversation list; bottom bar on glass.
        .apolloGlassSearchField(text: $searchQuery, prompt: "Search modmail")
        // Flat, not inset-grouped. Apollo's content lists are edge-to-edge: rows start
        // flush left and separators span nearly the full width. SwiftUI's default would
        // render a rounded card in a gutter, which reads as a settings table.
        .listStyle(.plain)
        // A title-view dropdown (a label plus disclosure chevron), not a segmented
        // control. The mailboxes are menu items, not tabs.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Menu {
                    ApolloSettingsPicker("Mailbox", selection: $selectedTab,
                                 options: ModmailInboxTab.allCases.map { $0 },
                                 display: { $0.title })
                } label: {
                    // Moderator-area button: text + chevron.
                    HStack(spacing: 4) {
                        Text(selectedTab.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                // The five sort orders. Apollo gives every sort its own icon; a Picker renders
                // only checkmarks, so these are plain Buttons carrying the per-option glyph, with
                // the checkmark drawn explicitly.
                Menu {
                    ForEach(ModmailSortOption.allCases) { option in
                        Button {
                            sortOrder = option
                        } label: {
                            // Icon rows carry no checkmark; only icon-less rows get one, as in Apollo's glass
                            // sort menu.
                            Label(
                                option.title,
                                systemImage: ApolloMenuIcon.symbol(option.apolloIconName, fallback: "circle")
                            )
                        }
                    }
                } label: {
                    Image(systemName: ApolloMenuIcon.symbol(
                        sortOrder.apolloIconName, fallback: "arrow.up.arrow.down"))
                }

                // More-options button. Subreddit filtering lives here rather than in its own
                // always-visible control.
                Menu {
                    Button {
                        Task { await markAllRead() }
                    } label: {
                        // Icon `option-mark-all-read`.
                        Label("Mark All Read", systemImage: ApolloMenuIcon.symbol(
                            "option-mark-all-read", fallback: "envelope.open"))
                    }
                    if !availableSubreddits.isEmpty {
                        Picker("Subreddit", selection: $selectedSubreddit) {
                            Text("All Subreddits").tag(String?.none)
                            ForEach(availableSubreddits, id: \.self) { name in
                                Text("r/\(name)").tag(String?.some(name))
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                    .accessibilityLabel("More")
                }
            }
        }
        .task(id: selectedTab) { await load() }
        .task(id: sortOrder) { await load() }
        .refreshable { await load() }
    }

    private var availableSubreddits: [String] {
        Array(Set(conversations.compactMap(\.subredditName))).sorted()
    }

    private var filteredConversations: [ModmailConversation] {
        var result = conversations
        if let selectedSubreddit {
            result = result.filter { $0.subredditName == selectedSubreddit }
        }
        if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            result = result.filter { $0.subject.range(of: searchQuery, options: .caseInsensitive) != nil }
        }
        return result
    }

    private func modmailRow(_ conversation: ModmailConversation) -> some View {
        SettingsLink {
            ModmailThreadScreen(conversation: conversation, repository: repository)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    // Reddit reports unread via `lastUnread` being present, not a bool.
                    if conversation.isUnread {
                        Circle()
                            .fill(Color.apolloAccent)
                            .frame(width: 8, height: 8)
                    }
                    if conversation.isHighlighted {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    Text(conversation.subject)
                        .font(.headline)
                        .fontWeight(conversation.isUnread ? .bold : .semibold)
                }
                HStack {
                    if let subredditName = conversation.subredditName {
                        Text("r/\(subredditName)")
                    }
                    if let participant = conversation.participantName {
                        Text("u/\(participant)")
                    }
                    Text(conversation.numMessages.apolloCounted("message", "messages"))
                    if conversation.isArchived {
                        Image(systemName: "archivebox.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        // Quick actions are swipe or long-press, not buried in a detail screen.
        .swipeActions(edge: .leading) {
            Button {
                Task { await setHighlight(!conversation.isHighlighted, on: conversation) }
            } label: {
                Label(conversation.isHighlighted ? "Unhighlight" : "Highlight",
                      systemImage: conversation.isHighlighted ? "star.slash" : "star")
            }
            .tint(.yellow)
        }
        .swipeActions(edge: .trailing) {
            Button {
                Task { await setArchived(!conversation.isArchived, on: conversation) }
            } label: {
                Label(conversation.isArchived ? "Unarchive" : "Archive",
                      systemImage: conversation.isArchived ? "tray.and.arrow.up" : "archivebox")
            }
            .tint(.orange)
            Button {
                Task { await markUnread(conversation) }
            } label: {
                Label("Unread", systemImage: "envelope.badge")
            }
            .tint(.blue)
        }
    }

    private func loadMore() async {
        guard let after = nextPage, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let generation = loadGeneration
        guard let page = try? await repository.fetchModmailConversationPage(
            state: selectedTab.apiState, sort: sortOrder, after: after),
              generation == loadGeneration else { return }
        let known = Set(conversations.map(\.id))
        conversations += page.conversations.filter { !known.contains($0.id) }
        nextPage = page.next
    }

    private func load() async {
        #if DEBUG
        // Same debug fixture hook as the thread screen.
        if let decoded = ModmailFixture.load() {
            conversations = [decoded.conversation]
            errorMessage = nil
            return
        }
        #endif
        loadGeneration += 1
        let generation = loadGeneration
        do {
            let page = try await repository.fetchModmailConversationPage(
                state: selectedTab.apiState, sort: sortOrder)
            guard generation == loadGeneration else { return }
            conversations = page.conversations
            nextPage = page.next
            errorMessage = nil
        } catch is RedditRepository.ModmailRequiresOAuthError {
            errorMessage = RedditRepository.ModmailRequiresOAuthError().errorDescription
        } catch let error as ModmailWebService.ServiceError {
            // The web transport's failures are specific and actionable, unlike the generic
            // "Error fetching modmail": an expired cookie needs a re-sign-in, and a silent
            // rejection means Reddit accepted the call and ignored it.
            errorMessage = error.errorDescription
        } catch {
            // Error copy.
            errorMessage = "Error fetching modmail"
        }
    }


    /// Apollo's mark-all-read action, with its failure string "Error marking all
    /// read".
    private func markAllRead() async {
        do {
            try await repository.markAllModmailRead(state: selectedTab.apiState)
            await load()
        } catch let error as ModmailWebService.ServiceError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Error marking all read"
        }
    }

    // Quick actions
    //
    // Each reloads on success rather than mutating the local array: archiving can
    // remove a conversation from the current tab entirely, and a local edit would
    // leave a stale row.

    private func setHighlight(_ highlighted: Bool, on conversation: ModmailConversation) async {
        do {
            if highlighted {
                try await repository.highlightModmail(conversationID: conversation.id)
            } else {
                try await repository.unhighlightModmail(conversationID: conversation.id)
            }
            await load()
        } catch let error as ModmailWebService.ServiceError {
            // A `.silentlyRejected` is the archive trap: Reddit answered ok:true and did
            // nothing. Reporting the real reason beats "Error archiving.", which implies a
            // transient failure worth retrying.
            errorMessage = error.errorDescription
        } catch {
            // Per-action error strings, verbatim.
            errorMessage = highlighted ? "Error highlighting." : "Error unhighlighting."
        }
    }

    private func setArchived(_ archived: Bool, on conversation: ModmailConversation) async {
        do {
            if archived {
                try await repository.archiveModmail(conversationID: conversation.id)
            } else {
                try await repository.unarchiveModmail(conversationID: conversation.id)
            }
            await load()
        } catch let error as ModmailWebService.ServiceError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = archived ? "Error archiving." : "Error unarchiving."
        }
    }

    private func markUnread(_ conversation: ModmailConversation) async {
        do {
            try await repository.markModmailUnread(conversationIDs: [conversation.id])
            await load()
        } catch let error as ModmailWebService.ServiceError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Error marking unread."
        }
    }
}

/// One modmail conversation: its messages, and a reply box. In Apollo this is the
/// private message screen in modmail mode.
struct ModmailThreadScreen: View {
    let conversation: ModmailConversation
    let repository: RedditRepository

    @State private var detail: ModmailConversationDetail?
    @State private var isLoading = true
    @State private var replyText = ""
    @State private var isInternalReply = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var isHighlighted: Bool
    @State private var isArchived: Bool

    init(conversation: ModmailConversation, repository: RedditRepository) {
        self.conversation = conversation
        self.repository = repository
        _isHighlighted = State(initialValue: conversation.isHighlighted)
        _isArchived = State(initialValue: conversation.isArchived)
    }

    private var messages: [ModmailMessage] { detail?.messages ?? [] }

    /// A closed or archived conversation is not repliable, which Reddit reports via
    /// `isRepliable`.
    private var canReply: Bool {
        (detail?.conversation ?? conversation).isRepliable
    }

    var body: some View {
        List {
            if isLoading && messages.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            ForEach(messages) { message in
                modmailBubble(message)
            }

            if !isLoading && messages.isEmpty && errorMessage == nil {
                Text("No messages in this conversation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if canReply {
                Section {
                    if let actionError {
                        Text(actionError).font(.caption).foregroundStyle(.red)
                    }
                    TextField("Message", text: $replyText, axis: .vertical)
                        .lineLimit(4...8)
                        .accessibilityIdentifier("modmail.replyField")
                    // `isInternal`: a private note to other moderators. Worth an explicit control and
                    // warning, since sending a mod note as a user-visible reply by accident is what
                    // modmail exists to prevent.
                    Toggle("Private Moderator Note", isOn: $isInternalReply)
                        .accessibilityIdentifier("modmail.internalToggle")
                    Button {
                        Task { await send() }
                    } label: {
                        if isSending {
                            ProgressView()
                        } else {
                            Text(isInternalReply ? "Add Private Note" : "Send Reply")
                        }
                    }
                    .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                } header: {
                    Text("Reply")
                        .apolloSectionHeader()
                } footer: {
                    if isInternalReply {
                        Text("Only other moderators will see this. The user won't.")
                    .apolloSectionFooter()
                    }
                }
            } else {
                Section {
                    Text("This conversation can't be replied to.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        // Plain, matching the Chat conversation: bubbles should read as a conversation,
        // not rows in a grouped table.
        .listStyle(.plain)
        .navigationTitle(conversation.subject)
        .navigationBarTitleDisplayModeIfAvailable()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // More options menu.
                Menu {
                    Button {
                        Task { await toggleHighlight() }
                    } label: {
                        Label(isHighlighted ? "Unhighlight" : "Highlight",
                              systemImage: isHighlighted ? "star.slash" : "star")
                    }
                    Button {
                        Task { await toggleArchive() }
                    } label: {
                        Label(isArchived ? "Unarchive" : "Archive",
                              systemImage: isArchived ? "tray.and.arrow.up" : "archivebox")
                    }
                    Button {
                        Task { await markUnread() }
                    } label: {
                        Label("Mark Unread", systemImage: "envelope.badge")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                    .accessibilityLabel("More")
                }
                .accessibilityIdentifier("modmail.actions")
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    /// The signed-in moderator, so their own replies side right. Modmail has no "self"
    /// field; the active account's username is the only signal, and nil (signed out)
    /// means nothing sides right.
    private var selfUsername: String? {
        FavoriteSubredditsAccountContext.currentUsernameProvider()
    }

    /// One modmail message, as a bubble. Apollo draws modmail with the same screen as
    /// a DM. Two modmail-specific distinctions are kept: a moderator's byline is
    /// green, and an internal note is tinted orange and badged, so it cannot be read
    /// as something the user saw.
    @ViewBuilder
    private func modmailBubble(_ message: ModmailMessage) -> some View {
        MessageBubbleRow(
            author: authorLabel(for: message),
            body: message.body,
            date: message.parsedDate,
            isFromSelf: {
                guard let selfUsername, let author = message.author else { return false }
                return author.name.caseInsensitiveCompare(selfUsername) == .orderedSame
            }(),
            bubbleTint: message.isInternal ? Color.orange.opacity(0.22) : nil
        ) {
            if message.isInternal {
                Text("PRIVATE NOTE")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.25)))
                    .foregroundStyle(.orange)
            }
            if message.author?.isMod == true {
                // Moderator green (#30D158), matching comment bylines.
                Text("MOD")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(hex: "30D158"))
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: ModmailMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(authorLabel(for: message))
                    .font(.caption.weight(.semibold))
                    // Moderator green (#30D158), matching comment bylines.
                    .foregroundStyle(message.author?.isMod == true ? Color(hex: "30D158") : Color.secondary)
                if message.isInternal {
                    Text("PRIVATE NOTE")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.25)))
                        .foregroundStyle(.orange)
                }
                Spacer()
                if let date = message.parsedDate {
                    Text(date, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Text(RedditMarkdown.render(message.body))
                .font(.body)
        }
        .padding(.vertical, 2)
        // An internal note is visually distinct from a reply, not just badged, so it
        // cannot be read as something the user saw.
        .listRowBackground(message.isInternal ? Color.orange.opacity(0.08) : nil)
    }

    /// `isAuthorHidden`: Reddit hides some participants' names, and inventing one
    /// would be worse than saying so.
    private func authorLabel(for message: ModmailMessage) -> String {
        guard let author = message.author, !author.name.isEmpty else { return "Unknown" }
        if author.isHidden { return "Hidden User" }
        return "u/\(author.name)"
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        #if DEBUG
        if let decoded = ModmailFixture.load() {
            detail = decoded
            isHighlighted = decoded.conversation.isHighlighted
            isArchived = decoded.conversation.isArchived
            return
        }
        #endif
        do {
            // Opening a conversation marks it read, via the `markRead` parameter of this same
            // endpoint.
            let loaded = try await repository.fetchModmailConversation(id: conversation.id)
            detail = loaded
            isHighlighted = loaded.conversation.isHighlighted
            isArchived = loaded.conversation.isArchived
            errorMessage = nil
        } catch is RedditRepository.ModmailRequiresOAuthError {
            errorMessage = RedditRepository.ModmailRequiresOAuthError().errorDescription
        } catch let error as ModmailWebService.ServiceError {
            errorMessage = error.errorDescription
        } catch {
            // Error copy.
            errorMessage = "Error fetching modmail: \(error.localizedDescription)"
        }
    }

    private func send() async {
        isSending = true
        actionError = nil
        defer { isSending = false }
        do {
            try await repository.replyToModmail(
                conversationID: conversation.id,
                body: replyText,
                isInternal: isInternalReply
            )
            replyText = ""
            isInternalReply = false
            // Reload rather than appending locally: the server assigns the message's id and
            // date, and a local fake would disagree with the thread on the next refresh.
            await load()
        } catch {
            actionError = "\(error.localizedDescription)"
        }
    }

    private func toggleHighlight() async {
        // Optimistic, then reverted on failure: an error alert shows and the row is left
        // as it was.
        let previous = isHighlighted
        isHighlighted.toggle()
        do {
            if previous {
                try await repository.unhighlightModmail(conversationID: conversation.id)
            } else {
                try await repository.highlightModmail(conversationID: conversation.id)
            }
            actionError = nil
        } catch {
            isHighlighted = previous
            // Error strings, verbatim.
            actionError = previous ? "Error unhighlighting." : "Error highlighting."
        }
    }

    private func toggleArchive() async {
        let previous = isArchived
        isArchived.toggle()
        do {
            if previous {
                try await repository.unarchiveModmail(conversationID: conversation.id)
            } else {
                try await repository.archiveModmail(conversationID: conversation.id)
            }
            actionError = nil
        } catch {
            isArchived = previous
            actionError = previous ? "Error unarchiving." : "Error archiving."
        }
    }

    private func markUnread() async {
        do {
            try await repository.markModmailUnread(conversationIDs: [conversation.id])
            actionError = nil
        } catch {
            actionError = "Error marking unread."
        }
    }
}
