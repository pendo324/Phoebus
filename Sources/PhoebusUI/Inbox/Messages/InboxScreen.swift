import SwiftUI
import PhoebusCore

/// Inbox category screen (one instance per `InboxType`, pushed from the
/// "Boxes" menu, `InboxListScreen`). `InboxScreen` below is a thin
/// `.inbox`-category wrapper for callers, like widgets/shortcuts, that
/// want the full unfiltered inbox with no Boxes-menu navigation.
public struct InboxCategoryScreen: View {
    @Setting(GeneralSettings.self) private var generalSettings
    let category: InboxCategory
    let repository: RedditRepository
    @ObservedObject private var badge = InboxBadge.shared

    @State private var messages: [RedditMessage] = []
    /// Your comments that replies answer, by fullname, for the row's quote.
    @State private var parentBodies: [String: String] = [:]
    /// Whether an older page may exist.
    @State private var mayHaveMore = false
    @State private var isLoadingMore = false
    /// Apollo-Reborn "Unify Modmail in Inbox" (`UnifyModmailInInbox`):
    /// merges moderator-mail conversations directly into the main
    /// Inbox listing (interleaved by recency) rather than requiring a
    /// moderator to visit the separate `ModmailListScreen`. Only
    /// fetched/merged on the `.inbox` category (the flat combined
    /// list) since the other categories (Comment Replies, Username
    /// Mentions, etc.) have no modmail analog. Populated alongside
    /// `messages` in `load()`; empty when the setting is off or the
    /// category isn't `.inbox`, in which case `displayItems` falls
    /// back to the plain `messages`-only list.
    @State private var modmailConversations: [ModmailConversation] = []
    /// Reddit Chat rooms shown among the messages of Inbox (All), as the
    /// OAuth inbox carries a copy of each chat message. Only fetched
    /// when the inbox comes over the cookie transport, which doesn't.
    @State private var chatRooms: [ChatRoom] = []
    @State private var chatSelfUserID: String?
    @State private var chatNames: [String: String] = [:]
    /// Read/unread changes made here since the last fetch.
    @State private var unreadOverrides: [String: Bool] = [:]

    private func isUnread(_ message: RedditMessage) -> Bool {
        unreadOverrides[message.name] ?? message.new
    }
    @State private var errorMessage: String?
    /// True while the first fetch is in flight, so the list can show a
    /// loading row rather than its "No messages" empty state before
    /// anything has been fetched.
    @State private var isLoading = false
    /// The comment thread a tapped inbox reply points at.
    @State private var commentTarget: InboxCommentTarget?
    @Setting(SwipeActionStore.storage(for: .inbox)) private var swipeSettings
    @State private var showingCompose = false
    /// The message a Reply swipe answers, and the link a Share swipe sends.
    @State private var swipeReplyTarget: RedditMessage?
    @State private var swipeShareURL: URL?
    /// Messages a Hide swipe took off the list.
    @State private var hiddenMessages: Set<String> = []

    public init(category: InboxCategory, repository: RedditRepository) {
        self.category = category
        self.repository = repository
    }

    /// "Inbox (1)" while anything is unread, as Apollo titles it.
    private var title: String {
        guard category == .inbox, badge.unreadCount > 0 else { return category.title }
        return "\(category.title) (\(badge.unreadCount))"
    }

    /// `.inbox`-only merge described above: interleaves messages and
    /// modmail conversations sorted newest-first by their respective
    /// timestamps, so a moderator sees a single unified
    /// recency-ordered feed instead of two disjoint lists.
    private var displayItems: [InboxDisplayItem] {
        guard !modmailConversations.isEmpty || !chatRooms.isEmpty else {
            return messages.map { .message($0) }
        }
        var items: [InboxDisplayItem] = messages.map { .message($0) }
        items.append(contentsOf: modmailConversations.map { .modmail($0) })
        // Rooms older than the last loaded message wait for that page.
        let oldest = mayHaveMore ? messages.last?.created : nil
        items.append(contentsOf: chatRooms
            .filter { room in oldest.map { (room.lastMessageDate ?? .distantPast) >= $0 } ?? true }
            .map { .chat($0) })
        return items.sorted { $0.sortDate > $1.sortDate }
    }

    /// A direct room is named after the other person, as on the Chat list.
    private func chatTitle(_ room: ChatRoom) -> String {
        if let name = room.name, !name.isEmpty { return name }
        let others = room.otherParticipants(excluding: chatSelfUserID)
        let resolved = others.compactMap { chatNames[$0] }
        if !resolved.isEmpty { return resolved.joined(separator: ", ") }
        return others.compactMap { RedditChatClient.accountID(fromMatrixUserID: $0) }.first ?? "Conversation"
    }

    /// Inbox items, with a DEBUG-only synthetic PM thread so the thread UI
    /// can be exercised without a populated PM box. Release builds never
    /// see this.
    private var itemsForDisplay: [InboxDisplayItem] {
        #if DEBUG
        if ProcessInfo.processInfo.environment["APOLLO_FORCE_PM_THREAD"] != nil {
            let reply = RedditMessage(
                id: "dbg2", name: "t4_dbg2", author: "apollo_tester",
                subject: "Test conversation", body: "And this is their reply, which should sit on the left with their name above it.",
                created: Date().addingTimeInterval(-1800),
                firstMessageName: "t4_dbg1")
            let root = RedditMessage(
                id: "dbg1", name: "t4_dbg1", author: "pendo324",
                subject: "Test conversation",
                body: "This is my own message, which should sit on the right in the accent colour.",
                created: Date().addingTimeInterval(-3600),
                replies: [reply])
            return [.message(root)] + displayItems
        }
        #endif
        guard !hiddenMessages.isEmpty else { return displayItems }
        return displayItems.filter { item in
            if case .message(let message) = item { return !hiddenMessages.contains(message.name) }
            return true
        }
    }

    public var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            if displayItems.isEmpty && errorMessage == nil && isLoading {
                ApolloLoadingCell()
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("inbox.loading")
            } else if displayItems.isEmpty && errorMessage == nil {
                // Empty-state copy per category ("No username
                // mentions" / "No comment replies").
                Text(emptyStateText)
                    .foregroundStyle(.secondary)
            }
            ForEach(itemsForDisplay) { item in
                switch item {
                case .message(let message):
                    // A PM with replies is a conversation, so it opens
                    // the thread screen. A comment reply keeps its
                    // existing behaviour of jumping to the comment it
                    // refers to, and a lone PM stays an expandable row;
                    // pushing a one-message thread would be a worse
                    // experience than the row.
                    if !message.wasComment, !message.replies.isEmpty {
                        SettingsLink {
                            MessageThreadScreen(root: message, repository: repository)
                        } label: {
                            MessageRow(message: message, repository: repository, isNew: isUnread(message),
                                       parentBody: message.parentID.flatMap { parentBodies[$0] }) {
                                unreadOverrides[message.name] = false
                            }
                        }
                        .apolloSwipeActions(settings: swipeSettings, subject: subject(for: message)) { action in
                            Task { await handleSwipeAction(action, on: message) }
                        }
                        .apolloHidesDisclosureIndicator()
                        .accessibilityIdentifier("inbox.threadRow.\(message.name)")
                    } else {
                    MessageRow(message: message, repository: repository, isNew: isUnread(message),
                               parentBody: message.parentID.flatMap { parentBodies[$0] },
                               onMarkedRead: { unreadOverrides[message.name] = false }) { sub, postID, commentID in
                        commentTarget = InboxCommentTarget(subreddit: sub, postID: postID, commentID: commentID)
                    }
                        .apolloSwipeActions(settings: swipeSettings, subject: subject(for: message)) { action in
                            Task { await handleSwipeAction(action, on: message) }
                        }
                        .accessibilityIdentifier("inbox.messageRow.\(message.name)")
                    }
                case .modmail(let conversation):
                    SettingsLink {
                        ModmailThreadScreen(conversation: conversation, repository: repository)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "shield")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(conversation.subject).font(.headline)
                                if let subredditName = conversation.subredditName {
                                    Text("r/\(subredditName)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier("inbox.modmailRow.\(conversation.id)")
                case .chat(let room):
                    SettingsLink {
                        ChatRoomScreen(room: room, title: chatTitle(room), selfUserID: chatSelfUserID,
                                       displayNames: chatNames, repository: repository)
                    } label: {
                        ChatMirrorRow(room: room, title: chatTitle(room), repository: repository)
                    }
                    .apolloHidesDisclosureIndicator()
                    .accessibilityIdentifier("inbox.chatRow.\(room.id)")
                }
            }
            if mayHaveMore, !messages.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowSeparator(.hidden)
                    .onAppear { Task { await loadMore() } }
            }
        }
        // Flat, not inset-grouped. Apollo's content lists are
        // edge-to-edge, with no gutter beside the rows. Without this,
        // SwiftUI's default renders a rounded card floating in a
        // gutter, which reads as a settings table rather than a list
        // of conversations.
        .listStyle(.plain)
        // Stock dark surface + Pure Black tiers (`ApolloStockSurface`).
        .scrollContentBackground(.hidden)
        .apolloStockSurface()
        .navigationTitle(title)
        .apolloCentersTitle(title, key: "inbox.\(title)")
        // Inline, not large: a large title collapses into the bar as the
        // list scrolls, leaving only toolbar buttons above a tall blank band.
        .navigationBarTitleDisplayModeIfAvailable()
        // Each category has a compose button and a mark-all-read button, so
        // mark-all-read is reachable from every category's toolbar, not just
        // the Boxes root.
        .toolbar {
            // Both on the right, mark-all-read first, with the back
            // button to Boxes on the left.
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        try? await repository.markAllMessagesRead()
                        InboxBadge.shared.markedAllRead()
                        await load()
                    }
                } label: {
                    ApolloIconImage("option-mark-all-read")
                    .accessibilityLabel("Mark All Read")
                }
                .accessibilityIdentifier("inboxCategory.markAllRead")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCompose = true
                } label: {
                    Image(systemName: "square.and.pencil")
                    .accessibilityLabel("Compose Message")
                }
                .accessibilityIdentifier("inboxCategory.compose")
            }
        }
        .sheet(isPresented: $showingCompose) {
            ComposeMessageScreen(repository: repository) {
                showingCompose = false
            }
        }
        .sheet(item: $swipeReplyTarget) { message in
            CommentComposerScreen(
                parentFullname: message.name,
                repository: repository,
                quotedPreview: (author: message.author, snippet: message.body, age: nil),
                subreddit: message.subreddit,
                onSubmitted: { swipeReplyTarget = nil })
        }
        .sheet(item: $swipeShareURL) { url in
            ActivityShareSheet(items: [url])
        }
        .task { await load() }
        // Feeds the browser-style forward stack, so swiping back from a
        // tapped reply can be undone by a forward swipe.
        .apolloTracksForwardNavigation($commentTarget)
        .apolloOpensRedditTargetsHere()
        // The page swipes themselves come from the Inbox tab's path
        // stack (`apolloSettingsNavigation`), which wraps every push.
        // Isolated single-comment thread for a tapped inbox reply.
        .navigationDestination(item: $commentTarget) { target in
            CommentTreeScreen(subreddit: target.subreddit,
                              postID: target.postID,
                              repository: repository,
                              // `CommentTreeNode.id` is the bare comment
                              // id (`comment.id`), not the `t1_` fullname, and
                              // Reddit's `context` permalink already carries
                              // the bare form, so it is used as-is.
                              focusedCommentID: target.commentID)
        }
        .refreshable { await load() }
    }

    private var emptyStateText: String {
        switch category {
        case .usernameMentions: return "No username mentions"
        case .commentReplies, .postReplies: return "No comment replies"
        default: return "No messages"
        }
    }

    private func load() async {
        // A failure shown from an earlier attempt goes as this one starts.
        errorMessage = nil
        // Only when there is nothing on screen: a refresh keeps the
        // current messages up rather than blanking to a spinner.
        if messages.isEmpty { isLoading = true }
        defer { isLoading = false }
        do {
            messages = try await repository.fetchInbox(category: category)
            unreadOverrides = [:]
            mayHaveMore = messages.count >= 25
            await loadParentBodies(for: messages)
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
        // Only merges on the flat `.inbox` category, and only fetched
        // at all when the setting is on, since a non-moderator's
        // `fetchModmailConversations` call would just 403 for no
        // benefit. A modmail-fetch failure is swallowed rather than
        // surfaced as the screen's main error; the regular inbox
        // messages above already loaded fine.
        if category == .inbox, await repository.inboxLacksChatMirrors {
            await loadChatRooms()
        }
        guard category == .inbox, generalSettings.unifyModmailInInbox else {
            modmailConversations = []
            return
        }
        modmailConversations = (try? await repository.fetchModmailConversations()) ?? []
    }

    /// Chat rooms for Inbox (All). A Chat failure leaves the messages
    /// alone; Direct Chat reports it.
    private func loadChatRooms() async {
        if chatSelfUserID == nil { chatSelfUserID = await repository.chatSelfUserID() }
        guard let result = try? await repository.fetchChatRooms() else { return }
        chatRooms = result.rooms.filter { !$0.isInvite && $0.lastMessageDate != nil }
        let missing = Set(chatRooms.filter { ($0.name ?? "").isEmpty }
            .flatMap { $0.otherParticipants(excluding: chatSelfUserID) })
            .subtracting(chatNames.keys)
        if !missing.isEmpty {
            chatNames.merge(await repository.fetchChatDisplayNames(userIDs: Array(missing))) { _, new in new }
        }
    }

    /// The next page, after the oldest message shown.
    private func loadMore() async {
        guard mayHaveMore, !isLoadingMore, let last = messages.last else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let page = try? await repository.fetchInbox(category: category, after: last.name) else {
            // Leave the row; it retries when it appears again.
            return
        }
        let known = Set(messages.map(\.name))
        messages += page.filter { !known.contains($0.name) }
        mayHaveMore = page.count >= 25
        await loadParentBodies(for: page)
    }

    private func loadParentBodies(for page: [RedditMessage]) async {
        let wanted = page.filter { InboxRowText.kind(of: $0) == .commentReply }
            .compactMap(\.parentID).filter { parentBodies[$0] == nil }
        guard !wanted.isEmpty else { return }
        parentBodies.merge(await repository.fetchCommentBodies(fullnames: wanted)) { _, new in new }
    }

    /// Votes only apply to comment replies; private messages cannot be voted on.
    private func subject(for message: RedditMessage) -> SwipeSubject {
        SwipeSubject(fullname: message.name, unread: isUnread(message))
    }

    /// Votes and Save only apply to comment replies; Reply answers either
    /// kind, Share sends a reply's comment link, Hide takes the row off
    /// the list. Mark Read toggles, as Apollo's does: a read message is
    /// marked unread again.
    private func handleSwipeAction(_ action: SwipeAction, on message: RedditMessage) async {
        if [.upvote, .downvote, .save].contains(action), !message.wasComment { return }
        await ContentActions.perform(action, on: VotableRef(name: message.name), repository: repository,
                                     hooks: SwipeActionHooks(
            onReply: { swipeReplyTarget = message },
            onShare: {
                guard let context = message.context else { return }
                swipeShareURL = URL(string: "https://www.reddit.com" + context)
            },
            onHide: { hiddenMessages.insert(message.name) },
            onMarkRead: {
            if isUnread(message) {
                unreadOverrides[message.name] = false
                try? await repository.markMessageRead(fullname: message.name)
                InboxBadge.shared.markedRead()
            } else {
                unreadOverrides[message.name] = true
                try? await repository.markMessageUnread(fullname: message.name)
                await InboxBadge.shared.refresh()
            }
        },
            author: message.author, subreddit: message.subreddit,
            selectableText: (title: message.linkTitle ?? message.subject, body: message.body)))
    }
}

/// The Inbox tab's root: the Boxes menu, with each category pushed as
/// its own list. Inbox (All) is pushed over it as the tab first
/// appears, as Apollo does, so back from it leads to Boxes. Pushed once
/// Boxes is on screen rather than starting the stack there, so the back
/// swipe has a picture of Boxes to slide in.
public struct InboxScreen: View {
    let repository: RedditRepository
    @Environment(\.settingsNavigation) private var navigation
    @State private var openedInbox = false

    public init(repository: RedditRepository) {
        self.repository = repository
    }

    public var body: some View {
        InboxListScreen(repository: repository)
            .onAppear {
                guard !openedInbox, let navigation else { return }
                openedInbox = true
                DispatchQueue.main.async {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        navigation.path.append(SettingsRoute(view: AnyView(
                            InboxCategoryScreen(category: .inbox, repository: repository))))
                    }
                }
            }
    }
}

/// A single row in `InboxCategoryScreen`'s unified list: either a
/// `RedditMessage` or (when `GeneralSettings.unifyModmailInInbox` is
/// on) a moderator-mail `ModmailConversation` merged in alongside it.
enum InboxDisplayItem: Identifiable {
    case message(RedditMessage)
    case modmail(ModmailConversation)
    case chat(ChatRoom)

    var id: String {
        switch self {
        case .message(let message): return "message-\(message.id)"
        case .modmail(let conversation): return "modmail-\(conversation.id)"
        case .chat(let room): return "chat-\(room.id)"
        }
    }

    /// Sort key for the recency-interleaved merge: falls back to
    /// `.distantPast` for a conversation with no parseable
    /// `lastUpdated` so a malformed timestamp sinks to the bottom
    /// rather than crashing or excluding the row.
    var sortDate: Date {
        switch self {
        case .message(let message): return message.created
        case .modmail(let conversation): return conversation.lastUpdatedDate ?? .distantPast
        case .chat(let room): return room.lastMessageDate ?? .distantPast
        }
    }
}

/// A chat room's latest message in Inbox (All), laid out as Reddit's
/// OAuth inbox copy of it reads in Apollo: "[direct chat room]" as the
/// subject, then who it's with, then the message.
struct ChatMirrorRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.apolloTheme) private var apolloTheme
    @Setting(GeneralSettings.self) private var general
    let room: ChatRoom
    let title: String
    let repository: RedditRepository

    private var isUnread: Bool { room.countsTowardGlobalBadge && room.notificationCount > 0 }

    private var secondary: Color {
        Color.apolloSecondaryText(colorScheme: colorScheme, themeColors: apolloTheme)
    }

    /// Laid out as a stock message row (`MessageRow`): the message glyph,
    /// the bold subject, the latest message in grey, then the sender.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 6) {
                    StockPNG.image(InboxRowText.Kind.message.glyph)
                        .foregroundStyle(Color(hex: "75787E"))
                    if isUnread {
                        StockPNG.image("inbox-highlighted")
                            .foregroundStyle(Color(hex: "E26F2C"))
                    }
                }
                .frame(width: 27, alignment: .center)
                .padding(.top, 3)
                VStack(alignment: .leading, spacing: 8) {
                    Text("[direct chat room]")
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    if let preview = room.preview, !preview.isEmpty {
                        Text(preview)
                            .foregroundStyle(secondary)
                            .lineLimit(6)
                    }
                }
                .apolloFont(size: 15)
            }
            HStack(spacing: 0) {
                Group {
                    if general.showUserProfilePictures {
                        AvatarView(username: title, repository: repository, size: 20)
                    } else {
                        Color.clear.frame(width: 20, height: 20)
                    }
                }
                .frame(width: 27, alignment: .leading)
                Text(title).lineLimit(1)
                Spacer(minLength: 8)
                Menu {
                    Button { PasteboardHelper.copy(room.preview ?? "") } label: {
                        Label("Copy Text", systemImage: "doc.on.doc")
                    }
                } label: {
                    Text("•••").padding(.horizontal, 6).contentShape(Rectangle())
                }
                .accessibilityLabel("More Options")
                if let date = room.lastMessageDate {
                    Text(ShareCardFormatting.compactAge(since: date))
                        .padding(.leading, 8)
                }
            }
            .apolloFont(size: 15)
            .foregroundStyle(secondary)
        }
        .padding(.vertical, 4)
        .listRowBackground(isUnread ? (colorScheme == .dark ? Color(hex: "1C2E48") : Color.apolloAccent.opacity(0.12)) : nil)
        .listRowInsets(EdgeInsets(top: 10, leading: 11, bottom: 10, trailing: 17))
    }
}

struct MessageRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.apolloTheme) private var apolloTheme
    @Setting(GeneralSettings.self) private var general
    let message: RedditMessage
    let repository: RedditRepository
    /// Your comment this reply answers, when known.
    let parentBody: String?
    /// Reports the comment thread a tapped reply points at, so the
    /// hosting screen can push it. See the tap handler below.
    var onOpenComment: ((String, String, String) -> Void)?
    /// Unread, as the screen currently knows it (a swipe can change it).
    let isNew: Bool
    /// Marks it read on the screen, once the tap has sent that to Reddit.
    var onMarkedRead: () -> Void = {}
    @State private var showingReply = false
    @State private var replyText = ""
    @State private var isSubmittingReply = false

    init(message: RedditMessage, repository: RedditRepository, isNew: Bool, parentBody: String? = nil,
         onMarkedRead: @escaping () -> Void = {},
         onOpenComment: ((String, String, String) -> Void)? = nil) {
        self.message = message
        self.repository = repository
        self.isNew = isNew
        self.parentBody = parentBody
        self.onMarkedRead = onMarkedRead
        self.onOpenComment = onOpenComment
    }

    // Row metrics on a 393pt screen: a 15pt type glyph at x 11 (the orange
    // "highlighted" arrow under it while unread), text from x 39 at 15pt,
    // white overview with bold names and title, #94969C body and footer;
    // the footer's 20pt avatar sits in the glyph column.
    private var secondary: Color {
        Color.apolloSecondaryText(colorScheme: colorScheme, themeColors: apolloTheme)
    }

    private var overview: Text {
        InboxRowText.overview(for: message, parentSnippet: parentBody).reduce(Text("")) { text, run in
            text + Text(run.text).fontWeight(run.bold ? .semibold : .regular)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 6) {
                    StockPNG.image(InboxRowText.kind(of: message).glyph)
                        .foregroundStyle(Color(hex: "75787E"))
                    if isNew {
                        StockPNG.image("inbox-highlighted")
                            .foregroundStyle(Color(hex: "E26F2C"))
                    }
                }
                .frame(width: 27, alignment: .center)
                .padding(.top, 1)
                VStack(alignment: .leading, spacing: 8) {
                    overview
                        .apolloFont(size: 15)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    // Apollo-Reborn "Inline Media in Messages"
                    // (`EnableChatMedia`).
                    InlineMediaBodyView(message.body, context: .messages)
                        .apolloFont(size: 15)
                        .foregroundStyle(secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AccessibilitySummary.message(
                author: message.author, subject: message.linkTitle ?? message.subject,
                body: message.body, created: message.created, unread: isNew,
                isCommentReply: message.wasComment))
            .accessibilityAddTraits(message.commentTarget != nil ? .isButton : [])

            footer

            if showingReply {
                TextField("Reply to u/\(message.author)…", text: $replyText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                Button("Send") {
                    Task { await sendReply() }
                }
                .disabled(isSubmittingReply || replyText.trimmingCharacters(in: .whitespaces).isEmpty)
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
        // Tapping a comment reply opens the isolated single-comment
        // thread it refers to, with that comment highlighted. Marking
        // read happens for every message type.
        .contentShape(Rectangle())
        .onTapGesture {
            if isNew {
                onMarkedRead()
                Task {
                    try? await repository.markMessageRead(fullname: message.name)
                    InboxBadge.shared.markedRead()
                }
            }
            if let target = message.commentTarget {
                onOpenComment?(target.subreddit, target.postID, target.commentID)
            }
        }
        // Mirrors Apollo's CopyMessageTextActivity.
        .contextMenu {
            Button {
                PasteboardHelper.copy(message.body)
            } label: {
                Label("Copy Text", systemImage: "doc.on.doc")
            }
        }
        // Unread rows sit on Apollo's blue tint (#1C2E48) until opened.
        .listRowBackground(isNew ? unreadBackground : nil)
        // Glyph column from x 11, text from x 39.
        .listRowInsets(EdgeInsets(top: 10, leading: 11, bottom: 10, trailing: 17))
    }

    /// Avatar, "author in subreddit", then ••• and the age at the end.
    private var footer: some View {
        HStack(spacing: 0) {
            Group {
                if general.showUserProfilePictures {
                    AvatarView(username: message.author, repository: repository, size: 20)
                } else {
                    Color.clear.frame(width: 20, height: 20)
                }
            }
            .frame(width: 27, alignment: .leading)
            (Text(message.author)
                + (message.subreddit.map { Text(" in ") + Text(SubredditCapitalization.display($0)) } ?? Text("")))
                .lineLimit(1)
            Spacer(minLength: 8)
            Menu {
                Button { showingReply.toggle() } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                }
                Button { PasteboardHelper.copy(message.body) } label: {
                    Label("Copy Text", systemImage: "doc.on.doc")
                }
            } label: {
                Text("•••").padding(.horizontal, 6).contentShape(Rectangle())
            }
            .accessibilityLabel("More Options")
            Text(ShareCardFormatting.compactAge(since: message.created))
                .padding(.leading, 8)
        }
        .apolloFont(size: 15)
        .foregroundStyle(secondary)
    }

    private var unreadBackground: Color {
        colorScheme == .dark ? Color(hex: "1C2E48") : Color.apolloAccent.opacity(0.12)
    }

    /// Replying within a PM thread: Reddit treats message replies as
    /// comments on the message "post", so this reuses the same
    /// `/api/comment` endpoint as post/comment replies.
    private func sendReply() async {
        isSubmittingReply = true
        defer { isSubmittingReply = false }
        do {
            try await repository.submitComment(parentFullname: message.name, text: replyText)
            replyText = ""
            showingReply = false
        } catch {
            // Leave the reply box open with the typed text on failure.
        }
    }
}

/// The comment thread a tapped Inbox reply points at, parsed from
/// Reddit's own `context` permalink. See `RedditMessage.commentTarget`.
struct InboxCommentTarget: Identifiable, Hashable {
    let subreddit: String
    let postID: String
    let commentID: String
    var id: String { "\(subreddit)/\(postID)/\(commentID)" }
}

/// A private-message conversation for the plain DM case: Reddit sends
/// the whole exchange nested under its root message's `data.replies`,
/// so this is treated as a conversation rather than a single
/// expandable inbox row.
public struct MessageThreadScreen: View {
    let root: RedditMessage
    let repository: RedditRepository

    @State private var replyText = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    /// Replies sent from this screen, appended locally so the thread
    /// updates without a full refetch (Reddit does not return the new
    /// message in a usable shape from `/api/comment`).
    @State private var sentReplies: [RedditMessage] = []

    public init(root: RedditMessage, repository: RedditRepository) {
        self.root = root
        self.repository = repository
    }

    /// The signed-in user, so their own messages side right.
    private var selfUsername: String? {
        FavoriteSubredditsAccountContext.currentUsernameProvider()
    }

    private var messages: [RedditMessage] {
        root.thread + sentReplies
    }

    /// The other party, used as the screen title: a PM's `subject`
    /// repeats on every message, so the correspondent is the more
    /// useful heading, matching how the Chat list titles a room.
    private var correspondent: String {
        let others = messages
            .map(\.author)
            .filter { author in
                guard let selfUsername else { return true }
                return author.caseInsensitiveCompare(selfUsername) != .orderedSame
            }
        return others.first ?? root.author
    }

    public var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
            ForEach(messages) { message in
                MessageBubbleRow(
                    author: "u/\(message.author)",
                    body: message.body,
                    date: message.created,
                    isFromSelf: {
                        guard let selfUsername else { return false }
                        return message.author.caseInsensitiveCompare(selfUsername) == .orderedSame
                    }()
                )
                .accessibilityIdentifier("messageThread.bubble.\(message.name)")
            }
        }
        // Plain, matching Chat and modmail: bubbles read as a
        // conversation, not as rows in a grouped table.
        .listStyle(.plain)
        .navigationTitle(correspondent.isEmpty ? root.subject : "u/\(correspondent)")
        .navigationBarTitleDisplayModeIfAvailable()
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Message", text: $replyText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .accessibilityIdentifier("messageThread.field")
            Button {
                Task { await send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
                .accessibilityLabel("Send")
            }
            .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            .accessibilityIdentifier("messageThread.send")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func send() async {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        do {
            // A PM reply goes through the same comment endpoint as any
            // other reply, parented to the message's fullname, which
            // is why `RedditMessage.name` matters here.
            _ = try await repository.submitComment(
                parentFullname: messages.last?.name ?? root.name, text: text)
            sentReplies.append(RedditMessage(
                id: UUID().uuidString,
                name: "t4_local_\(UUID().uuidString)",
                author: selfUsername ?? "",
                subject: root.subject,
                body: text,
                created: Date()
            ))
            replyText = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension View {
    /// Stock inbox rows have no disclosure chevron, even those that push.
    @ViewBuilder
    func apolloHidesDisclosureIndicator() -> some View {
        if #available(iOS 26.0, *) {
            navigationLinkIndicatorVisibility(.hidden)
        } else {
            self
        }
    }
}
