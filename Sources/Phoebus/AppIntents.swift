import AppIntents
import PhoebusCore

/// Apollo's SiriKit custom intents (OpenHome, OpenSubreddit, OpenUser,
/// OpenMultireddit) reimplemented with AppIntents. These are plain Swift
/// types in the app target, so no .appex or .intentdefinition is needed.
public struct OpenSubredditIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Subreddit"
    public static let description = IntentDescription("Opens a subreddit in Phoebus.")

    @Parameter(title: "Subreddit")
    public var subredditName: String

    public init() {}

    public init(subredditName: String) {
        self.subredditName = subredditName
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Open r/\(\.$subredditName)")
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        AppIntentNavigation.shared.pendingTarget = .subreddit(subredditName)
        return .result()
    }
}

public struct OpenHomeIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Home Feed"
    public static let description = IntentDescription("Opens your Phoebus home feed.")

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        AppIntentNavigation.shared.pendingTarget = .subreddit("")
        return .result()
    }
}

public struct OpenUserIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open User Profile"
    public static let description = IntentDescription("Opens a Reddit user's profile in Phoebus.")

    @Parameter(title: "Username")
    public var username: String

    public init() {}

    public init(username: String) {
        self.username = username
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Open u/\(\.$username)")
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        AppIntentNavigation.shared.pendingTarget = .user(username)
        return .result()
    }
}

/// The OpenMultireddit intent and its `multiredditName` parameter.
public struct OpenMultiredditIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Multireddit"
    public static let description = IntentDescription("Opens a multireddit in Phoebus.")

    @Parameter(title: "Multireddit Name")
    public var multiredditName: String

    public init() {}

    public init(multiredditName: String) {
        self.multiredditName = multiredditName
    }

    public static var parameterSummary: some ParameterSummary {
        Summary("Open multireddit \(\.$multiredditName)")
    }

    @MainActor
    public func perform() async throws -> some IntentResult {
        AppIntentNavigation.shared.pendingTarget = .multireddit(multiredditName)
        return .result()
    }
}

/// Bridges AppIntents (which run detached from any particular SwiftUI
/// view hierarchy) into the running app's navigation state. The main
/// app observes `pendingTarget` and routes to it the same way it
/// handles phoebus:// deep links from the share extension.
@MainActor
public final class AppIntentNavigation {
    public static let shared = AppIntentNavigation()
    public static let didRequestNotification = Notification.Name("AppIntentNavigationDidRequest")
    public var pendingTarget: RedditURLTarget? {
        didSet {
            if pendingTarget != nil {
                NotificationCenter.default.post(name: Self.didRequestNotification, object: nil)
            }
        }
    }
    private init() {}
}

/// Exposes the intents to Siri/Shortcuts/Spotlight.
///
/// Phrases can only interpolate `AppEntity`/`AppEnum` parameters, and
/// `subredditName`/`multiredditName` are plain `String`s, so the phrases are
/// static and Siri prompts for the parameter.
public struct PhoebusShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenHomeIntent(),
            phrases: ["Open my \(.applicationName) feed"],
            shortTitle: "Open Home Feed",
            systemImageName: "house"
        )
        AppShortcut(
            intent: OpenSubredditIntent(),
            phrases: ["Open a subreddit in \(.applicationName)"],
            shortTitle: "Open Subreddit",
            systemImageName: "text.bubble"
        )
        AppShortcut(
            intent: OpenMultiredditIntent(),
            phrases: ["Open a multireddit in \(.applicationName)"],
            shortTitle: "Open Multireddit",
            systemImageName: "rectangle.stack"
        )
    }
}
