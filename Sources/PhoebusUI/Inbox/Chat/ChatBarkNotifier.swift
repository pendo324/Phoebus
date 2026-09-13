import SwiftUI
import PhoebusCore

/// Reborn's on-device chat unread notifier, Bark delivery only: while
/// the app is open, Reddit Chat's own unread counters (from the Matrix
/// `/sync` that `InboxBadge` already runs for the tab badge) are
/// compared with the last ones seen, and rises are pushed to the Bark
/// URL with a tap link into Chat. A backend cannot do this: modern Chat
/// is not on Reddit's OAuth API.
///
/// Fed by `InboxBadge` from `ChatLive`'s events, rather than running a
/// `/sync` loop of its own.
@MainActor
public enum ChatBarkNotifier {
    /// Handles one sync result for `username`.
    static func process(_ sync: RedditChatClient.SyncResult, username: String) async {
        guard let bark = PushNotificationClient.barkURL(NotificationBackendSettingsStore.load()) else { return }
        let unreadRooms = sync.rooms.filter { $0.notificationCount > 0 && !$0.isInvite }
        let latest = unreadRooms.max { $0.lastMessageTimestamp < $1.lastMessageTimestamp }
        let latestTs = latest?.lastMessageTimestamp ?? 0

        guard let marks = ChatUnreadNotifier.marks(for: username) else {
            // First poll ever for this account: record, announce nothing.
            ChatUnreadNotifier.save(.init(unread: sync.unreadCount, requests: sync.requestsCount, latestTs: latestTs), for: username)
            return
        }
        let decision = ChatUnreadNotifier.decide(unread: sync.unreadCount, requests: sync.requestsCount,
                                                 latestTs: latestTs, marks: marks)
        var next = ChatUnreadNotifier.Marks(unread: sync.unreadCount, requests: sync.requestsCount,
                                            latestTs: max(latestTs, marks.latestTs))
        let sound = NotificationSettingsStore.load().notificationSound.barkSoundID ?? "traloop"
        if decision.pushUnread {
            let body = [latest?.previewSender, latest?.preview].compactMap { $0 }.joined(separator: ": ")
            let msg = PushNotificationClient.BarkMessage(
                title: ChatUnreadNotifier.unreadTitle(sync.unreadCount),
                body: body.isEmpty ? "Open Chat to read it." : body,
                url: "\(PushNotificationClient.scheme)://reborn/chat", group: "apollo-chat",
                icon: PushNotificationClient.defaultIconURL, sound: sound)
            if await !PushNotificationClient.sendBark(msg, to: bark).ok {
                next.unread = marks.unread; next.latestTs = marks.latestTs
            }
        }
        if decision.pushRequests {
            let msg = PushNotificationClient.BarkMessage(
                title: ChatUnreadNotifier.requestsTitle(sync.requestsCount),
                body: "Someone wants to start a chat with you.",
                url: "\(PushNotificationClient.scheme)://reborn/chat", group: "apollo-chat",
                icon: PushNotificationClient.defaultIconURL, sound: sound)
            if await !PushNotificationClient.sendBark(msg, to: bark).ok { next.requests = marks.requests }
        }
        ChatUnreadNotifier.save(next, for: username)
    }
}
