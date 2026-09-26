import Foundation
import PhoebusCore
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Starts, updates and ends the Follow Thread Live Activity.
///
/// Every failure path reports a reason rather than silently doing nothing:
/// Live Activities can be switched off, the simulator may not support them,
/// and the push half is unavailable (see `FollowThreadActivityAttributes`).
enum LiveActivityHelper {
    enum StartResult: Equatable {
        case started
        case unsupported
        case disabled
        case failed(String)

        /// What to tell the user. `nil` when it worked.
        var message: String? {
            switch self {
            case .started:
                return nil
            case .unsupported:
                return "Live Activities aren't available on this device."
            case .disabled:
                return "Live Activities are turned off for Phoebus in Settings."
            case .failed(let reason):
                return "Couldn't start the Live Activity: \(reason)"
            }
        }
    }

    /// Whether the OS will let us start one right now.
    static var isAvailable: Bool {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled
        }
        return false
        #else
        return false
        #endif
    }

    @discardableResult
    static func start(postID: String, title: String, subreddit: String,
                      commentCount: Int, score: Int) -> StartResult {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return .unsupported }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return .disabled }
        let attributes = FollowThreadActivity(postID: postID, title: title,
                                              subreddit: subreddit)
        let state = FollowThreadActivityState(commentCount: commentCount, score: score)
        do {
            // `pushType: nil` on purpose: Apollo registers a push token with its own
            // server so threads update while the app is closed, but there is no server
            // to receive one here, so a token would be useless.
            _ = try Activity.request(attributes: attributes,
                                     content: .init(state: state, staleDate: nil),
                                     pushType: nil)
            FollowThreadActivityStore.setActive(postID: postID, active: true)
            return .started
        } catch {
            return .failed(error.localizedDescription)
        }
        #else
        return .unsupported
        #endif
    }

    /// Pushes a new comment count into a running activity.
    static func update(postID: String, commentCount: Int, score: Int) async {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        let state = FollowThreadActivityState(commentCount: commentCount, score: score)
        for activity in Activity<FollowThreadActivity>.activities
        where activity.attributes.postID == postID {
            await activity.update(.init(state: state, staleDate: nil))
        }
        #endif
    }

    static func end(postID: String) async {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            for activity in Activity<FollowThreadActivity>.activities
            where activity.attributes.postID == postID {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        #endif
        FollowThreadActivityStore.setActive(postID: postID, active: false)
    }
}
