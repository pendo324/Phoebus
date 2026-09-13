import Foundation

/// Reborn's chat-to-Bark transition logic: the self-hosted backend
/// polls Reddit's OAuth API, where modern Chat does not exist, so chat
/// pushes can only come from the device. Per-account high-water marks
/// of what was already announced are persisted, so a relaunch does not
/// repeat them, and a failed Bark POST leaves the mark alone so the
/// next tick retries.
public enum ChatUnreadNotifier {
    public struct Marks: Codable, Equatable, Sendable {
        public var unread: Int
        public var requests: Int
        public var latestTs: Double
        public init(unread: Int = 0, requests: Int = 0, latestTs: Double = 0) {
            self.unread = unread; self.requests = requests; self.latestTs = latestTs
        }
    }

    public struct Decision: Equatable, Sendable {
        public var pushUnread: Bool
        public var pushRequests: Bool
        public init(pushUnread: Bool, pushRequests: Bool) {
            self.pushUnread = pushUnread; self.pushRequests = pushRequests
        }
    }

    /// A newer message can arrive while the total holds steady (one read,
    /// one received): the advancing timestamp catches it. `latestTs > 0`
    /// on the mark keeps the first-ever poll from announcing history.
    public static func decide(unread: Int, requests: Int, latestTs: Double, marks: Marks) -> Decision {
        let newer = unread > 0 && latestTs > 0 && marks.latestTs > 0 && latestTs > marks.latestTs
        return Decision(pushUnread: unread > marks.unread || newer, pushRequests: requests > marks.requests)
    }

    public static func unreadTitle(_ count: Int) -> String {
        count == 1 ? "New Chat Message" : "\(count) Unread Chat Messages"
    }

    public static func requestsTitle(_ count: Int) -> String {
        count == 1 ? "New Chat Request" : "\(count) New Chat Requests"
    }

    private static let key = "ChatUnreadNotifiedWatermarks"

    public static func marks(for username: String, defaults: UserDefaults = .standard) -> Marks? {
        guard let data = defaults.data(forKey: key),
              let all = try? JSONDecoder().decode([String: Marks].self, from: data) else { return nil }
        return all[username.lowercased()]
    }

    public static func save(_ marks: Marks, for username: String, defaults: UserDefaults = .standard) {
        var all = (defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([String: Marks].self, from: $0) }) ?? [:]
        all[username.lowercased()] = marks
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: key) }
    }
}
