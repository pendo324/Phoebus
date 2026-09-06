import Foundation
import PhoebusCore
#if canImport(UIKit)
import UIKit
import QuartzCore
#endif

/// The last 20 coarse actions before a crash, as in Reborn: a ring buffer
/// of `CrashContextEvent`s, published into KSCrash's userInfo at most every
/// two seconds.
enum CrashContext {
    private static let capacity = 20
    private static let publishDebounce: TimeInterval = 2
    private static let queue = DispatchQueue(label: "app.phoebus.crashcontext")
    nonisolated(unsafe) private static var entries: [(event: CrashContextEvent, time: TimeInterval)] = []
    nonisolated(unsafe) private static var started = false
    nonisolated(unsafe) private static var publishScheduled = false
    nonisolated(unsafe) private static var observers: [NSObjectProtocol] = []

    static func start() {
        guard CrashManager.shared.isInstalled, !started else { return }
        started = true
        #if canImport(UIKit)
        let observed: [(Notification.Name, CrashContextEvent)] = [
            (UIApplication.didBecomeActiveNotification, .appBecameActive),
            (UIApplication.willResignActiveNotification, .appResignedActive),
            (UIApplication.didEnterBackgroundNotification, .appEnteredBackground),
            (UIApplication.didReceiveMemoryWarningNotification, .memoryWarning),
        ]
        for (name, event) in observed {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in
                record(event)
            })
        }
        #endif
        CrashManager.shared.publishUserInfo(recentActions: [])
    }

    static func record(_ event: CrashContextEvent) {
        guard started else { return }
        let now = ProcessInfo.processInfo.systemUptime
        queue.async {
            entries.append((event, now))
            if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
            guard !publishScheduled else { return }
            publishScheduled = true
            queue.asyncAfter(deadline: .now() + publishDebounce) {
                publishScheduled = false
                publish()
            }
        }
    }

    /// Oldest first, ages in whole seconds before the snapshot.
    private static func publish() {
        let now = ProcessInfo.processInfo.systemUptime
        let actions: [[String: Any]] = entries.map { ["event": $0.event.rawValue, "age_seconds": Int(now - $0.time)] }
        CrashManager.shared.publishUserInfo(recentActions: actions)
    }
}
