import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit
#endif

/// The Inbox tab's unread badge, as Apollo's `updateInboxBadge` keeps it:
/// refreshed at launch, on returning to the foreground, periodically
/// while open, and after anything marks messages read.
@MainActor
public final class InboxBadge: ObservableObject {
    public static let shared = InboxBadge()

    @Published public private(set) var unreadCount = 0
    private var repository: RedditRepository?
    private var username: String?
    private var pollTask: Task<Void, Never>?
    private var chatTask: Task<Void, Never>?
    private var lastRefresh = Date.distantPast

    /// Apollo refreshes the inbox count about once a minute while in
    /// the foreground. Chat needs no timer: `ChatLive` delivers its
    /// counts as they change.
    static let pollInterval: Duration = .seconds(60)

    /// Starts (or restarts, for a new account) the foreground poll. A
    /// brief trip through `.inactive` (Control Center, a system alert)
    /// doesn't refetch at once if the last refresh is recent.
    public func start(repository: RedditRepository, username: String?) {
        let sameAccount = self.repository.map { ObjectIdentifier($0) == ObjectIdentifier(repository) } ?? false
        self.repository = repository
        self.username = username
        if !sameAccount { lastRefresh = .distantPast }
        pollTask?.cancel()
        chatTask?.cancel()
        ChatLive.shared.start(repository: repository)
        let engine = ChatLive.shared.engine(for: repository)
        chatTask = Task { [weak self] in
            for await update in await engine.updates() {
                guard let self else { return }
                self.chatUnread = InboxUnreadCount.chat(unread: update.snapshot.unreadCount,
                                                        requests: update.snapshot.requestsCount)
                self.apply(self.combinedCount)
                // Bark chat notifications ride on the same events.
                if let username = self.username {
                    await ChatBarkNotifier.process(update.snapshot, username: username)
                }
            }
        }
        pollTask = Task { [weak self] in
            if let self, sameAccount {
                let wait = Self.pollInterval - .seconds(Date().timeIntervalSince(self.lastRefresh))
                if wait > .zero { try? await Task.sleep(for: wait) }
            }
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
        chatTask?.cancel()
        chatTask = nil
        ChatLive.shared.stop()
    }

    /// Unread Reddit Chat, kept apart so a chat failure (no chat token for
    /// this account) keeps the inbox half.
    private var chatUnread = 0
    private var inboxUnread = 0
    /// OAuth inboxes list a copy of each chat message; web sessions don't.
    private var inboxListsChat = false

    private var combinedCount: Int {
        InboxUnreadCount.combined(inbox: inboxUnread, chat: chatUnread, inboxListsChat: inboxListsChat)
    }

    public func refresh() async {
        guard let repository else { return }
        lastRefresh = Date()
        inboxListsChat = !(await repository.inboxLacksChatMirrors)
        if let count = try? await repository.fetchUnreadInboxCount() {
            inboxUnread = count
        }
        // Reborn adds unread Reddit Chat to the Inbox badge; that half
        // arrives from `ChatLive`.
        apply(combinedCount)
    }

    private func apply(_ count: Int) {
        unreadCount = count
        // Also set on the UIKit item itself, as Reborn does: SwiftUI's
        // `Tab.badge` is not reliably carried to the system bar.
        #if canImport(UIKit)
        for window in UIKitTree.allWindows {
            guard let tabs = UIKitTree.tabBarController(in: window.rootViewController) else { continue }
            for item in tabs.tabBar.items ?? [] where item.title?.caseInsensitiveCompare("Inbox") == .orderedSame {
                item.badgeValue = Self.badgeText(count)
            }
        }
        #endif
    }

    /// Called after marking read, so the badge drops without waiting.
    public func markedRead(count: Int = 1) {
        inboxUnread = max(0, inboxUnread - count)
        apply(combinedCount)
        Task { await refresh() }
    }

    public func markedAllRead() {
        inboxUnread = 0
        apply(combinedCount)
        Task { await refresh() }
    }

    /// Tab badge text: nothing at zero, "99+" past 99.
    public static func badgeText(_ count: Int) -> String? {
        count <= 0 ? nil : (count > 99 ? "99+" : "\(count)")
    }
}
