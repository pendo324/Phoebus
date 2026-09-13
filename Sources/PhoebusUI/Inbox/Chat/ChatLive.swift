import Foundation
import PhoebusCore

/// The app's one `ChatLiveSync`, for the active account. Runs while the
/// app is in the foreground (`InboxBadge` starts and stops it); screens
/// subscribe to its updates instead of polling.
@MainActor
public final class ChatLive {
    public static let shared = ChatLive()

    private var engine: ChatLiveSync?
    private var owner: ObjectIdentifier?

    /// The engine for `repository`, replacing the previous account's.
    public func engine(for repository: RedditRepository) -> ChatLiveSync {
        let id = ObjectIdentifier(repository)
        if let engine, owner == id { return engine }
        if let old = engine { Task { await old.stop() } }
        let made = ChatLiveSync(repository: repository)
        engine = made
        owner = id
        return made
    }

    public func start(repository: RedditRepository) {
        let engine = engine(for: repository)
        Task { await engine.start() }
    }

    public func stop() {
        guard let engine else { return }
        Task { await engine.stop() }
    }
}
