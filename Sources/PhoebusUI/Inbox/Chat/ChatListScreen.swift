import SwiftUI
import PhotosUI
import PhoebusCore

/// Reddit Chat, rendered natively.
///
/// Reborn hosts Reddit's own web client in a WKWebView because, as a tweak, it
/// cannot replace Apollo's screens. Phoebus owns its screens and needs only the
/// transport underneath: Reddit Chat is Matrix, and the account's `token_v2`
/// works as a bearer against `matrix.redditspace.com` (see `RedditChatClient`).
/// Reddit's own chat page is a Matrix client too (`<rs-matrix-client>`); this
/// talks to the same API directly instead of through a browser and a private
/// DOM.
///
/// Covers the conversation list (unread counts, previews, pending requests) and
/// the rooms: reading, sending through `ChatSendQueue`, images, reactions,
/// edits and threads, and answering a request (Phoebus only; Reborn's web chat
/// does it in its page). See `docs/chat-sending-and-threads.md`.
public struct ChatListScreen: View {
    let repository: RedditRepository

    @State private var rooms: [ChatRoom] = []
    @State private var unreadCount = 0
    @State private var requestsCount = 0
    @State private var displayNames: [String: String] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedSection: Section = .messages
    @State private var selfUserID: String?
    @State private var openRequest: OpenRequest?

    /// A pending request opened from the list. It is held apart from the
    /// list's rows so accepting it, which moves the row to Messages, does not
    /// pop the screen the user is looking at.
    struct OpenRequest: Hashable, Identifiable {
        let room: ChatRoom
        var id: String { room.id }
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    /// Sections: Messages, Requests, Threads.
    ///
    /// Threads is omitted. Matrix threads are reachable (the homeserver advertises
    /// `org.matrix.msc3440.stable` and the relations API answers), but the
    /// room-level listing endpoint (`/_matrix/client/v1/rooms/{id}/threads`,
    /// MSC3856) returns 404. A Threads tab would mean walking every room's timeline
    /// and asking for relations per message, which is too many requests for one tab.
    enum Section: String, CaseIterable, Identifiable {
        case messages = "Messages"
        case requests = "Requests"
        var id: String { rawValue }
    }

    public init(repository: RedditRepository) {
        self.repository = repository
    }

    /// `ChatMessagesFilter` / `ChatMessagesUnreadOnly` (Reborn). See
    /// `ChatMessagesFilter` for the menu structure, titles and default.
    @Setting(ChatMessagesFilterStore.filterStorage) private var messagesFilter
    @Setting(ChatMessagesFilterStore.unreadOnlyStorage) private var messagesUnreadOnly

    private var visibleRooms: [ChatRoom] {
        switch selectedSection {
        case .messages:
            // The filter applies to Messages only; Requests/Threads
            // sections are untouched by it.
            return ChatMessagesFilterStore.apply(
                filter: messagesFilter,
                unreadOnly: messagesUnreadOnly,
                to: rooms.filter { !$0.isInvite }
            )
        case .requests:
            return rooms.filter { $0.isInvite }
        }
    }

    /// Selecting a filter also brings the Messages section up, as Apollo does; the
    /// setting would otherwise appear to do nothing while Requests is frontmost.
    private func applyMessagesFilter(_ filter: ChatMessagesFilter) {
        $messagesFilter.binding.wrappedValue = filter
        ChatMessagesFilterStore.saveFilter(filter)
        selectedSection = .messages
    }

    /// Same section behaviour as `toggleUnreadOnly`.
    private func toggleMessagesUnreadOnly() {
        $messagesUnreadOnly.update { $0.toggle() }
        selectedSection = .messages
    }

    /// The "Show in Messages" menu: an inline group of the three mutually
    /// exclusive chat types, then a second inline group with the "Unread Only"
    /// toggle. Both are `Section`s so SwiftUI renders the two-group layout
    /// `UIMenu`'s inline display produces. `SwiftUI.Section` is spelled out because
    /// this screen declares its own `Section` enum.
    @ViewBuilder private var messagesFilterMenu: some View {
        SwiftUI.Section {
            // A Toggle, not a checkmark image: UIKit draws a menu row's checkmark on the
            // trailing edge from `UIAction.state`, while a checkmark image lands in the
            // leading icon slot and destroys any row that has its own icon.
            ForEach(ChatMessagesFilter.allCases) { filter in
                Toggle(isOn: Binding(
                    get: { messagesFilter == filter },
                    set: { if $0 { applyMessagesFilter(filter) } }
                )) {
                    Text(filter.displayName)
                }
            }
        }
        SwiftUI.Section {
            Toggle(isOn: Binding(
                get: { messagesUnreadOnly },
                set: { _ in toggleMessagesUnreadOnly() }
            )) {
                Label("Unread Only", systemImage: "envelope.badge")
            }
        }
    }

    public var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
            if isLoading && rooms.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
            if !isLoading && visibleRooms.isEmpty && errorMessage == nil {
                Text(selectedSection == .requests
                     ? "No pending chat requests."
                     : "No conversations yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(visibleRooms) { room in
                // A request opens to its first message with Accept and Decline.
                if room.isInvite {
                    Button {
                        openRequest = OpenRequest(room: room)
                    } label: {
                        HStack {
                            roomRow(room)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    SettingsLink {
                        ChatRoomScreen(
                            room: room,
                            title: title(for: room),
                            selfUserID: selfUserID,
                            displayNames: displayNames,
                            repository: repository
                        )
                    } label: {
                        roomRow(room)
                    }
                }
            }
        }
        // Flat, not inset-grouped: Apollo's content lists are edge-to-edge, and the
        // default renders a rounded card in a gutter, which reads as a settings table.
        .listStyle(.plain)
        .navigationTitle("Chat")
        .navigationBarTitleDisplayModeIfAvailable()
        // The filter lives on the chat hub's bar button, as a submenu titled "Show in
        // Messages" with the `line.3.horizontal.decrease.circle` symbol.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    messagesFilterMenu
                } label: {
                    Label("Show in Messages",
                          systemImage: "line.3.horizontal.decrease.circle")
                }
                .accessibilityIdentifier("chat.messagesFilter")
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Section", selection: $selectedSection) {
                ForEach(Section.allCases) { section in
                    // The Requests tab carries its pending count.
                    if section == .requests && requestsCount > 0 {
                        Text("\(section.rawValue) (\(requestsCount))").tag(section)
                    } else {
                        Text(section.rawValue).tag(section)
                    }
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 6)
            .background(.bar)
            .accessibilityIdentifier("chat.sectionPicker")
        }
        .navigationDestination(item: $openRequest) { target in
            ChatRoomScreen(
                room: target.room,
                title: title(for: target.room),
                selfUserID: selfUserID,
                displayNames: displayNames,
                repository: repository,
                onRequestAccepted: { selectedSection = .messages }
            )
        }
        .apolloTracksForwardNavigation($openRequest)
        .task { await load() }
        // Kept current by the live sync rather than reloaded on a timer.
        .task {
            for await update in await ChatLive.shared.engine(for: repository).updates() where !isLoading {
                rooms = update.snapshot.rooms
                unreadCount = update.snapshot.unreadCount
                requestsCount = update.snapshot.requestsCount
                await resolveNames()
            }
        }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func roomRow(_ room: ChatRoom) -> some View {
        HStack(spacing: 10) {
            // A muted room is unread too, in grey; it stays out of the badge.
            if ChatRoomUnread.isUnread(room) {
                Circle().fill(ChatRoomUnread.isMutedUnread(room) ? Color.secondary : Color.apolloAccent)
                    .frame(width: 8, height: 8)
            } else {
                Circle().fill(.clear).frame(width: 8, height: 8)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title(for: room))
                        .font(.subheadline.weight(ChatRoomUnread.isUnread(room) ? .bold : .semibold))
                        .lineLimit(1)
                    Spacer()
                    if let date = room.lastMessageDate {
                        Text(date, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                if let preview = room.preview {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .accessibilityIdentifier("chat.room.\(room.id)")
    }

    /// A titled room uses its name; a direct room is titled by the
    /// other participant, resolved to a username.
    private func title(for room: ChatRoom) -> String {
        if let name = room.name, !name.isEmpty { return name }
        let others = room.otherParticipants(excluding: selfUserID)
        let resolved = others.compactMap { displayNames[$0] }
        if !resolved.isEmpty { return resolved.joined(separator: ", ") }
        // Falls back to the account id rather than an empty row.
        let ids = others.compactMap { RedditChatClient.accountID(fromMatrixUserID: $0) }
        return ids.first ?? "Conversation"
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            // Resolved before the rooms are titled: a direct room is named after its
            // other participant, and without knowing which one is you every DM reads
            // "you, them".
            if selfUserID == nil { selfUserID = await repository.chatSelfUserID() }
            // A request answered a moment ago stays answered, whichever sync reports it.
            let result = await ChatLive.shared.engine(for: repository).reconciled(try await repository.fetchChatRooms())
            rooms = result.rooms
            unreadCount = result.unreadCount
            requestsCount = result.requestsCount
            errorMessage = nil
            await resolveNames()
        } catch let error as RedditChatClient.ChatError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Resolves participant ids for the rooms that need a name; a titled room
    /// does not, and asking anyway would cost a profile request per participant.
    private func resolveNames() async {
        let needed = rooms
            .filter { ($0.name ?? "").isEmpty }
            .flatMap { $0.otherParticipants(excluding: selfUserID) }
        let missing = Array(Set(needed).subtracting(displayNames.keys))
        guard !missing.isEmpty else { return }
        let resolved = await repository.fetchChatDisplayNames(userIDs: missing)
        displayNames.merge(resolved) { _, new in new }
    }
}

/// One chat room: its messages, the composer and its send queue.
struct ChatRoomScreen: View {
    private static let bottomID = "chat.bottom"
    @Setting(ProfileLayoutSettings.self) private var profileLayoutSettings
    let room: ChatRoom
    let title: String
    let selfUserID: String?
    let displayNames: [String: String]
    let repository: RedditRepository
    /// Called when a pending request is accepted, so the list can show Messages.
    var onRequestAccepted: (() -> Void)?

    @State private var accepted = false
    @State private var messages: [RedditChatClient.ChatMessage] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var resolvedNames: [String: String] = [:]
    @State private var draft = ""
    /// Signed-in username the draft is kept under; empty until resolved,
    /// and the store ignores an empty account.
    @State private var draftAccount = ""
    @State private var pending: [ChatSendQueue.Entry] = []
    @State private var isSending = false
    @State private var typingTask: Task<Void, Never>?
    /// When the last "typing" notice went out, so a burst of keystrokes
    /// sends one (the notice lasts 20 s server-side), not one per key.
    @State private var lastTypingNotice = Date.distantPast
    @State private var draftSaveTask: Task<Void, Never>?
    @State private var photoItem: PhotosPickerItem?
    @State private var ephemeral: RedditChatClient.RoomEphemeral?
    @State private var ephemeralTask: Task<Void, Never>?
    @State private var editingMessage: RedditChatClient.ChatMessage?
    @State private var editDraft = ""
    @State private var reactions: [String: [RedditChatClient.MessageReaction]] = [:]
    @State private var reactingTo: RedditChatClient.ChatMessage?
    @State private var isUploading = false
    @State private var uploadError: String?

    /// A room that is still a request takes no messages until it is accepted.
    private var isPendingRequest: Bool { !ChatRequests.canReply(in: room) && !accepted }

    var body: some View {
        ScrollViewReader { proxy in
            // A scroll view over a plain stack, not a `List`: a list sizes rows lazily
            // from estimates, and a long message's estimate is far enough off that
            // scrolling down to it re-measures and throws the position back up. A room
            // loads its newest 50 messages, few enough to lay out in full.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
                if isPendingRequest {
                    requestIntro
                } else if !isLoading && messages.isEmpty && errorMessage == nil {
                    Text("No messages in this conversation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                    // Date headers between days; see `ChatDateFormatter`.
                    if let date = message.date,
                       ChatDateFormatter.needsHeader(
                           previous: index > 0 ? messages[index - 1].date : nil,
                           current: date) {
                        Text(ChatDateFormatter.headerText(for: date))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .padding(.vertical, 6)
                    }
                    messageRow(message).id(message.id)
                }

                // Queued messages sit after the delivered ones, which
                // is where they will land once sent.
                ForEach(pending) { entry in
                    pendingRow(entry)
                }

                // Typing indicator driven by the m.typing ephemeral
                // event. Excludes yourself, or your own typing notice
                // would show back at you.
                if let typing = ephemeral?.othersTyping(excluding: selfUserID), !typing.isEmpty {
                    typingRow(typing)
                }
                Color.clear.frame(height: 1).id(Self.bottomID)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            // Opens at the newest message, and stays there as more come.
            .defaultScrollAnchor(.bottom)
            // The composer is a safe-area inset, so the newest message ends above it.
            // An overlay rather than a first row, which would stay pinned under the bar
            // after the messages arrive.
            .overlay(alignment: .top) {
                if isLoading && messages.isEmpty {
                    ProgressView().padding(.top, 20)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isPendingRequest {
                    ChatRequestBar(
                        prompt: ChatRequests.isModmail(room) ? "Accept to read and reply." : "Accept to reply to \(title).",
                        blockName: title,
                        canBlock: ChatRequests.canBlock(room, selfUserID: selfUserID),
                        answer: answerRequest,
                        onAccepted: requestAccepted
                    )
                } else {
                    composer
                }
            }
            .onChange(of: messages.count) { _, _ in
                // A conversation opens at its very end: once now, and again after this
                // layout pass, since the first scroll lands before a long message has its
                // full height.
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
                DispatchQueue.main.async { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayModeIfAvailable()
        .task {
            // The messages first; the draft's account lookup can be a network round trip.
            async let loaded: Void = load()
            // Reborn #1207: restore this conversation's unsent draft.
            draftAccount = await CurrentUsernameCache.username(repository: repository) ?? ""
            if draft.isEmpty, let saved = MessageDraftStore.load(account: draftAccount, conversation: room.id) {
                draft = saved
            }
            await loaded
            startEphemeralPolling()
        }
        .onDisappear {
            ephemeralTask?.cancel()
            // Written now rather than when the debounce would have fired.
            draftSaveTask?.cancel()
            MessageDraftStore.save(draft, account: draftAccount, conversation: room.id)
            // Leaving mid-sentence: stop showing this user as typing.
            if lastTypingNotice.timeIntervalSinceNow > -20 {
                Task { [repository, room] in await repository.setChatTyping(roomID: room.id, isTyping: false) }
            }
        }
        .refreshable { await load() }
        .sheet(item: $reactingTo) { target in
            ChatReactionPicker(
                selected: Set((reactions[target.id] ?? []).filter { $0.myEventID != nil }.map(\.key))
            ) { key in
                reactingTo = nil
                Task { await toggleReaction(target, key: key) }
            }
        }
        .sheet(item: $editingMessage) { _ in
            NavigationStack {
                List {
                    TextField("Message", text: $editDraft, axis: .vertical)
                        .lineLimit(3...10)
                        .accessibilityIdentifier("chat.editField")
                }
                .apolloFlatListAppearance()
                .navigationTitle("Edit Message")
                .navigationBarTitleDisplayModeIfAvailable()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { editingMessage = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { await commitEdit() } }
                    }
                }
            }
        }
    }

    /// What a request shows before it is answered. Reddit sends neither the first
    /// message in the invite nor its history before the room is joined, so there is
    /// only who it is from.
    @ViewBuilder
    private var requestIntro: some View {
        VStack(alignment: .leading, spacing: 10) {
            if ChatRequests.isModmail(room) {
                Text(title)
                    .font(.headline)
                Text("Sent through a subreddit's modmail. Accept the request to read it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(title) wants to chat with you")
                    .font(.headline)
                Text("Accept the request to read their message.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .accessibilityIdentifier("chat.request.intro")
    }

    /// Accepts, declines or blocks through `ChatLive`, which moves the room in the
    /// list and the badge first and puts it back if this fails. Returns what to
    /// tell the user, nil on success.
    private func answerRequest(_ action: ChatRequestAction, alsoBlock: Bool) async -> String? {
        let requester = ChatRequests.requester(of: room, selfUserID: selfUserID)
        do {
            try await ChatLive.shared.engine(for: repository).answerRequest(action, room: room) { [repository, room] in
                if alsoBlock, let requester { try await repository.blockChatRequester(matrixUserID: requester) }
                try await repository.sendChatRequestAnswer(action, roomID: room.id)
            }
            return nil
        } catch {
            return ChatRequests.failureMessage(for: error, action: action)
        }
    }

    /// The request is now a conversation: this screen becomes it in place.
    private func requestAccepted() {
        accepted = true
        onRequestAccepted?()
        Task { await load() }
    }

    private var composer: some View {
        VStack(spacing: 4) {
            if let uploadError {
                Text(uploadError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            composerBar
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
    }

    private var composerBar: some View {
        HStack(spacing: 8) {
            // Apollo's chat composer has a media button.
            PhotosPicker(selection: $photoItem, matching: .images) {
                if isUploading {
                    ProgressView().frame(width: 24, height: 24)
                } else {
                    Image(systemName: "photo.on.rectangle")
                        .font(.title3)
                        .foregroundStyle(Color.apolloAccent)
                }
            }
            .disabled(isUploading)
            .accessibilityIdentifier("chat.photoPicker")

            TextField("Message", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                // Matrix typing notices carry a server-side timeout, so the notice expires
                // on its own; one is still sent on send, to clear it immediately.
                .onChange(of: draft) { _, newValue in
                    draftChanged(newValue)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color(.tertiarySystemFill)))
                .accessibilityIdentifier("chat.composer")
            Button {
                Task { await send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? Color.apolloAccent : Color(.tertiaryLabel))
                .accessibilityLabel("Send")
            }
            .disabled(!canSend)
            .accessibilityIdentifier("chat.send")
        }
    }

    /// Uploads a picked image and sends it. Dimensions are read from
    /// the image itself and sent in `info`, because Matrix clients lay
    /// a bubble out from `w`/`h` before the image loads; omitting them
    /// makes the conversation jump as each image arrives.
    private func upload(_ item: PhotosPickerItem) async {
        isUploading = true
        uploadError = nil
        defer {
            isUploading = false
            photoItem = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            uploadError = "Couldn't read that image."
            return
        }
        #if canImport(UIKit)
        let size = UIImage(data: data)?.size ?? .zero
        #else
        let size = CGSize.zero
        #endif
        let (upload, type) = webSafeImage(data)
        do {
            try await repository.sendChatImage(
                roomID: room.id,
                data: upload,
                filename: "image.\(type.fileExtension)",
                mimeType: type.mimeType,
                width: Int(size.width),
                height: Int(size.height)
            )
            await load()
        } catch let error as RedditChatClient.ChatError {
            uploadError = error.errorDescription
        } catch {
            uploadError = error.localizedDescription
        }
    }

    /// The draft is saved to the Keychain once typing pauses, not on
    /// every keystroke, and the typing notice is re-sent at most every
    /// few seconds.
    private func draftChanged(_ newValue: String) {
        draftSaveTask?.cancel()
        draftSaveTask = Task { [draftAccount, room] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            MessageDraftStore.save(newValue, account: draftAccount, conversation: room.id)
        }
        guard !newValue.isEmpty, Date().timeIntervalSince(lastTypingNotice) > 5 else { return }
        lastTypingNotice = Date()
        typingTask?.cancel()
        typingTask = Task { [repository, room] in
            await repository.setChatTyping(roomID: room.id, isTyping: true)
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    /// A queued message, shown in place with its state. Deliberately
    /// not a spinner: a queued send is a real object the user can
    /// abort or retry, see `ChatSendQueue`.
    @ViewBuilder
    private func pendingRow(_ entry: ChatSendQueue.Entry) -> some View {
        // A queued message is drawn as the outgoing bubble it will
        // become, dimmed, so sending does not change shape visibly.
        HStack(alignment: .bottom, spacing: 6) {
            Spacer(minLength: 40)
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.body)
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(maxWidth: 260, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.apolloAccent)
                    )
                    .opacity(entry.failureMessage == nil ? 0.55 : 0.85)

                if let failure = entry.failureMessage {
                    Text(entry.isParked ? "Failed — \(failure)" : "Retrying — \(failure)")
                        .font(.caption2)
                        .foregroundStyle(entry.isParked ? .red : .orange)
                        .multilineTextAlignment(.trailing)
                    HStack(spacing: 14) {
                        Button("Try Again") {
                            Task {
                                await repository.retryChatMessage(id: entry.id, roomID: room.id)
                                await refreshPending()
                            }
                        }
                        .font(.caption2)
                        Button("Delete", role: .destructive) {
                            Task {
                                await repository.abortChatMessage(id: entry.id)
                                await refreshPending()
                            }
                        }
                        .font(.caption2)
                    }
                } else {
                    Text("Sending…")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .padding(.vertical, 1)
    }

    private func send() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        // Cleared immediately (and its saved draft with it): the message
        // is durably queued in `ChatSendQueue` before the network is
        // touched, so a failed send cannot lose the text.
        draft = ""
        typingTask?.cancel()
        lastTypingNotice = .distantPast
        await repository.setChatTyping(roomID: room.id, isTyping: false)
        await repository.enqueueChatMessage(roomID: room.id, body: body)
        await refreshPending()
        // Reload so a delivered message appears as a real event rather
        // than staying a local copy the server never confirmed.
        await load()
    }

    private func refreshPending() async {
        pending = await repository.pendingChatMessages(roomID: room.id)
    }

    private func isFromSelf(_ message: RedditChatClient.ChatMessage) -> Bool {
        selfUserID != nil && message.sender == selfUserID
    }

    /// One message, as a chat bubble sided by author, with the other
    /// party's avatar, not a uniform list of rows.
    @ViewBuilder
    private func messageRow(_ message: RedditChatClient.ChatMessage) -> some View {
        let mine = isFromSelf(message)
        // The reaction pills sit outside the bubble's contextMenu: a
        // long-press menu inside it would consume their taps.
        VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
            messageBubbleRow(message)
            if let found = reactions[message.id], !found.isEmpty {
                ChatReactionRow(reactions: found) { key in
                    Task { await toggleReaction(message, key: key) }
                }
                .padding(mine ? .trailing : .leading, 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .padding(.vertical, 5)
    }

    private func messageBubbleRow(_ message: RedditChatClient.ChatMessage) -> some View {
        let mine = isFromSelf(message)
        return HStack(alignment: .bottom, spacing: 6) {
            if mine {
                // Outgoing messages carry no avatar.
                Spacer(minLength: 40)
            } else {
                avatar(for: message)
            }

            VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                // Incoming bubbles label their sender; outgoing ones
                // do not.
                if !mine {
                    Text(senderLabel(message))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if message.isMedia, let mediaURL = message.mediaDownloadURL {
                    // Inline media rendered directly rather than through a MessageKind.photo.
                    // The mxc:// URI resolves through the legacy unauthenticated download path
                    // (the authenticated variant 404s here), so it needs no bearer and goes
                    // through the app's image cache. Laid out from the event's declared w/h,
                    // which is why `info` is sent on upload.
                    ZStack {
                        if message.isAnimatedGIF {
                            // GIFs must animate. Reddit serves chat
                            // media with no file extension, so the
                            // mimetype is the only signal; the URL
                            // cannot be sniffed.
                            AnimatedGIFView(url: mediaURL)
                                .aspectRatio(mediaAspectRatio(message), contentMode: .fit)
                        } else {
                            CachedAsyncImage(url: mediaURL)
                                .aspectRatio(mediaAspectRatio(message), contentMode: .fit)
                        }
                        if message.isVideo {
                            // A video's poster is still an image; only
                            // the play affordance distinguishes it.
                            Image(systemName: "play.circle.fill")
                                .font(.largeTitle)
                                .foregroundStyle(.white.opacity(0.9))
                                .shadow(radius: 4)
                        }
                    }
                    .frame(maxWidth: 240, maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel(message.body)
                } else {
                    ChunkedMarkdownText(message.body)
                        .font(.body)
                        .bodyForeground(mine ? Color.white : Color.primary)
                        // Bubbles are width-capped so a long message
                        // wraps inside a bubble rather than becoming a
                        // full-width block.
                        .frame(maxWidth: 260, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(mine ? Color.apolloAccent : Color(.secondarySystemFill))
                        )
                }

                HStack(spacing: 6) {
                    if let date = message.date {
                        Text(date, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if message.isEdited {
                        Text("edited")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    // Read receipt, shown only on your own messages.
                    if mine, ephemeral?.isReadByOthers(eventID: message.id, excluding: selfUserID) == true {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.apolloAccent)
                            .accessibilityLabel("Read")
                    }
                    if effectiveThreadCount(message) > 0 {
                        SettingsLink {
                            ChatThreadScreen(
                                room: room,
                                parent: message,
                                title: title,
                                selfUserID: selfUserID,
                                displayNames: displayNames,
                                repository: repository
                            )
                        } label: {
                            Label(
                                effectiveThreadCount(message) == 1
                                    ? "1 reply" : "\(effectiveThreadCount(message)) replies",
                                systemImage: "bubble.left.and.bubble.right"
                            )
                            .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.apolloAccent)
                        .accessibilityIdentifier("chat.thread.\(message.id)")
                    }
                }
            }

            if !mine { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        // Edit and delete apply to your own messages only; the server
        // would reject the rest.
        .contextMenu {
            if !isPendingRequest {
                Button {
                    reactingTo = message
                } label: {
                    Label("React", systemImage: "face.smiling")
                }
            }
            if mine {
                if !message.isMedia {
                    Button {
                        editDraft = message.body
                        editingMessage = message
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                }
                Button(role: .destructive) {
                    Task { await deleteMessage(message) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            Button {
                #if canImport(UIKit)
                UIPasteboard.general.string = message.body
                #endif
            } label: {
                Label("Copy Text", systemImage: "doc.on.doc")
            }
        }
    }

    private func loadReactions() async {
        reactions = await repository.chatReactions(roomID: room.id, messages: messages)
    }

    private func toggleReaction(_ message: RedditChatClient.ChatMessage, key: String) async {
        let existing = reactions[message.id]?.first { $0.key == key }
        do {
            try await repository.toggleChatReaction(
                roomID: room.id, eventID: message.id, key: key, existing: existing)
            await loadReactions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteMessage(_ message: RedditChatClient.ChatMessage) async {
        do {
            try await repository.deleteChatMessage(roomID: room.id, eventID: message.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func commitEdit() async {
        guard let target = editingMessage else { return }
        let body = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        editingMessage = nil
        guard !body.isEmpty, body != target.body else { return }
        do {
            try await repository.editChatMessage(roomID: room.id, eventID: target.id, newBody: body)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// "X is typing…", styled as an incoming bubble so it occupies the
    /// place the message will appear.
    @ViewBuilder
    private func typingRow(_ userIDs: [String]) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            Circle()
                .fill(Color(.tertiarySystemFill))
                .frame(width: 28, height: 28)
            Text(typingLabel(userIDs))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.secondarySystemFill))
                )
            Spacer(minLength: 40)
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .accessibilityIdentifier("chat.typing")
    }

    private func typingLabel(_ userIDs: [String]) -> String {
        let names = userIDs.map { id in
            displayNames[id]
                ?? resolvedNames[id]
                ?? RedditChatClient.accountID(fromMatrixUserID: id)
                ?? id
        }
        if names.count == 1 { return "\(names[0]) is typing…" }
        return "\(names.count) people are typing…"
    }

    /// Follows the open room through `ChatLive`: new messages, typing and receipts
    /// arrive as they happen.
    private func startEphemeralPolling() {
        ephemeralTask?.cancel()
        let engine = ChatLive.shared.engine(for: repository)
        ephemeralTask = Task {
            for await update in await engine.updates() {
                if Task.isCancelled { return }
                if let state = update.ephemeral[room.id] { ephemeral = state }
                if update.timelineRoomIDs.contains(room.id), !isLoading {
                    await refreshIfNewMessages()
                }
            }
        }
    }

    /// Reloads the room only when its newest message has changed.
    private func refreshIfNewMessages() async {
        guard let latest = try? await repository.fetchChatMessages(roomID: room.id, limit: 1).last,
              latest.id != messages.last?.id, !Task.isCancelled else { return }
        await load()
    }

    /// The aspect ratio to lay an image bubble out at.
    ///
    /// Falls back to 4:3 when Reddit omitted `info`, rather than to a
    /// square - an arbitrary square distorts far more images than an
    /// arbitrary landscape does.
    private func mediaAspectRatio(_ message: RedditChatClient.ChatMessage) -> CGFloat {
        guard let width = message.mediaWidth, let height = message.mediaHeight,
              width > 0, height > 0 else { return 4.0 / 3.0 }
        return CGFloat(width) / CGFloat(height)
    }

    /// The other party's avatar beside an incoming bubble.
    ///
    /// Uses the `com.reddit.profile` avatar Reddit already bundles on
    /// the event, so it costs no extra request for anyone who has
    /// spoken in the room.
    @ViewBuilder
    private func avatar(for message: RedditChatClient.ChatMessage) -> some View {
        if let raw = message.senderAvatarURL,
           let url = URL(string: raw.replacingOccurrences(of: "&amp;", with: "&")) {
            CachedAsyncImage(url: url)
                .frame(width: 28, height: 28)
                // Shared Profile Picture Shape (Reborn #1136 covers
                // "messages" too).
                .clipShape(AvatarClipShape(style: profileLayoutSettings.avatarStyle))
        } else {
            AvatarClipShape(style: profileLayoutSettings.avatarStyle)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 28, height: 28)
                .overlay(
                    Text(senderLabel(message).prefix(1).uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                )
        }
    }


    /// The thread count to display. DEBUG builds honour
    /// `APOLLO_CHAT_FORCE_THREADS` so the thread affordance and screen
    /// can be exercised without a real threaded room. Release builds
    /// only ever use Reddit's real count.
    private func effectiveThreadCount(_ message: RedditChatClient.ChatMessage) -> Int {
        #if DEBUG
        if ProcessInfo.processInfo.environment["APOLLO_CHAT_FORCE_THREADS"] != nil,
           message.threadReplyCount == 0 {
            return 2
        }
        #endif
        return message.threadReplyCount
    }

    private func senderLabel(_ message: RedditChatClient.ChatMessage) -> String {
        if isFromSelf(message) { return "You" }
        // Reddit bundles a `com.reddit.profile` relation on messages,
        // carrying the sender's username. Preferring it means most
        // senders need no /profile request at all.
        if let bundled = message.senderUsername, !bundled.isEmpty { return bundled }
        if let name = displayNames[message.sender] ?? resolvedNames[message.sender] { return name }
        return RedditChatClient.accountID(fromMatrixUserID: message.sender) ?? message.sender
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        // Nothing to fetch for a request: its history is empty until it is accepted.
        if isPendingRequest {
            errorMessage = nil
            return
        }
        await refreshPending()
        do {
            let fetched = try await repository.fetchChatMessages(roomID: room.id)
            // Parsed off the main thread before they're shown: a long message (a
            // subreddit's weekly recap) can take most of a second to parse.
            let bodies = fetched.filter { !$0.isMedia }.map(\.body)
            await Task.detached(priority: .userInitiated) {
                for body in bodies { for block in QuoteBlocks.split(body) { _ = RedditMarkdown.render(block.text) } }
            }.value
            messages = fetched
            errorMessage = nil
            isLoading = false
            // Any message still queued from a previous launch is retried here, after
            // the messages are up so a send that is going nowhere can't hold the
            // conversation back.
            if !pending.isEmpty {
                await repository.drainChatQueue(roomID: room.id)
                await refreshPending()
                if let refreshed = try? await repository.fetchChatMessages(roomID: room.id) {
                    messages = refreshed
                }
            }
            // Opening a conversation marks it read. Best-effort: a
            // failed receipt must never stop you reading a room.
            if let newest = messages.last {
                await repository.markChatRead(roomID: room.id, eventID: newest.id)
            }
            // A group room can contain senders the list never needed
            // to name. Only senders Reddit did not bundle a profile
            // for need a lookup, which is usually none of them.
            let unnamed = messages.filter { ($0.senderUsername ?? "").isEmpty }.map(\.sender)
            let unknown = Set(unnamed)
                .subtracting(displayNames.keys)
                .subtracting(resolvedNames.keys)
                .subtracting(selfUserID.map { [$0] } ?? [])
            if !unknown.isEmpty {
                let extra = await repository.fetchChatDisplayNames(userIDs: Array(unknown))
                resolvedNames.merge(extra) { _, new in new }
            }
            // Loaded after the messages are on screen: reactions cost
            // one request per message, and the conversation should not
            // wait on decoration.
            await loadReactions()
        } catch let error as RedditChatClient.ChatError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Accept, Decline and Block under a pending request. A leaf view so that
/// reading `dismiss` does not re-render the conversation above it.
struct ChatRequestBar: View {
    let prompt: String
    /// Who a Block would apply to.
    let blockName: String
    let canBlock: Bool
    /// Returns what to tell the user when the answer failed, nil when it worked.
    let answer: (ChatRequestAction, _ alsoBlock: Bool) async -> String?
    let onAccepted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var confirming: Confirmation?

    enum Confirmation: Identifiable {
        case decline, block
        var id: Self { self }
    }

    var body: some View {
        VStack(spacing: 8) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("chat.request.error")
            }
            Text(prompt)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button {
                    Task { await run(.accept, alsoBlock: false) }
                } label: {
                    Group {
                        if isWorking { ProgressView() } else { Text("Accept") }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.apolloAccent)
                .accessibilityIdentifier("chat.request.accept")

                Button("Decline", role: .destructive) { confirming = .decline }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("chat.request.decline")

                if canBlock {
                    Button("Block", role: .destructive) { confirming = .block }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("chat.request.block")
                }
            }
            .disabled(isWorking)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .confirmationDialog(
            confirming == .block ? "Block \(blockName)?" : "Decline this chat request?",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible
        ) {
            if confirming == .block {
                Button("Block and Decline", role: .destructive) { Task { await run(.decline, alsoBlock: true) } }
            } else {
                Button("Decline", role: .destructive) { Task { await run(.decline, alsoBlock: false) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirming == .block
                 ? "They won't be able to message you, and the request is removed."
                 : "The request is removed from your list.")
        }
    }

    private func run(_ action: ChatRequestAction, alsoBlock: Bool) async {
        isWorking = true
        errorMessage = nil
        let failure = await answer(action, alsoBlock)
        isWorking = false
        if let failure {
            errorMessage = failure
        } else if action == .accept {
            onAccepted()
        } else {
            dismiss()
        }
    }
}

/// A message's thread replies. Threads open from the message that owns them
/// rather than from a room-wide tab, since the listing endpoint is missing.
struct ChatThreadScreen: View {
    let room: ChatRoom
    let parent: RedditChatClient.ChatMessage
    let title: String
    let selfUserID: String?
    let displayNames: [String: String]
    let repository: RedditRepository

    @State private var replies: [RedditChatClient.ChatMessage] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                messageRow(parent)
            } header: {
                Text("Original Message")
                    .apolloSectionHeader()
            }

            Section {
                if isLoading && replies.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
                if !isLoading && replies.isEmpty && errorMessage == nil {
                    Text("No replies.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(replies) { reply in
                    messageRow(reply)
                }
            } header: {
                Text(replies.count == 1 ? "1 Reply" : "\(replies.count) Replies")
            }
        }
        .apolloFlatListAppearance()
        .navigationTitle("Thread")
        .navigationBarTitleDisplayModeIfAvailable()
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func messageRow(_ message: RedditChatClient.ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(senderLabel(message))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(message.sender == selfUserID ? Color.apolloAccent : Color.secondary)
                Spacer()
                if let date = message.date {
                    Text(date, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            ChunkedMarkdownText(message.body)
                .font(.body)
        }
        .padding(.vertical, 2)
    }

    private func senderLabel(_ message: RedditChatClient.ChatMessage) -> String {
        if message.sender == selfUserID { return "You" }
        if let bundled = message.senderUsername, !bundled.isEmpty { return bundled }
        if let name = displayNames[message.sender] { return name }
        return RedditChatClient.accountID(fromMatrixUserID: message.sender) ?? message.sender
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            replies = try await repository.fetchChatThreadReplies(roomID: room.id, eventID: parent.id)
            errorMessage = nil
        } catch let error as RedditChatClient.ChatError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}


/// The reactions on one message. Reddit's reactions are images, not
/// unicode, so each is rendered as a remote GIF/PNG from its CDN
/// rather than as text. See `RedditChatReactions`.
struct ChatReactionRow: View {
    let reactions: [RedditChatClient.MessageReaction]
    let onTap: (String) -> Void

    var body: some View {
        // Wrapping, not a single row: a message can carry many
        // distinct reaction keys, which would run off the edges.
        ChatWrapLayout(spacing: 4) {
            ForEach(reactions) { reaction in
                Group {
                    HStack(spacing: 3) {
                        CachedAsyncImage(url: reaction.imageURL)
                            .frame(width: 18, height: 18)
                        if reaction.count > 1 {
                            Text("\(reaction.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            // Your own reaction is tinted, the only
                            // cue that tapping removes it.
                            .fill(reaction.myEventID != nil
                                  ? Color.accentColor.opacity(0.22)
                                  : Color.secondary.opacity(0.15))
                    )
                }
                // A tap gesture rather than a Button: a Button nested
                // under the bubble's contextMenu does not receive taps.
                .contentShape(Capsule())
                .onTapGesture { onTap(reaction.key) }
                .accessibilityIdentifier("chat.reaction." + reaction.key)
            }
        }
    }
}

/// Reddit's fixed reaction set.
struct ChatReactionPicker: View {
    let selected: Set<String>
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(RedditChatReactions.keys, id: \.self) { key in
                        Button {
                            onPick(key)
                        } label: {
                            CachedAsyncImage(url: RedditChatReactions.imageURL(forKey: key))
                                .frame(width: 36, height: 36)
                                .padding(4)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selected.contains(key)
                                              ? Color.accentColor.opacity(0.25)
                                              : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("chat.pick." + key)
                    }
                }
                .padding()
            }
            .navigationTitle("React")
            .navigationBarTitleDisplayModeIfAvailable()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}


/// Lays subviews left to right, wrapping onto new lines. Needed
/// because a message can carry many reactions and a plain HStack runs
/// them off the screen.
struct ChatWrapLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += lineHeight + spacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(widest, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += lineHeight + spacing
                x = bounds.minX
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
