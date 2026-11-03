import Foundation
import PhoebusCore

// MARK: - Signing in without a Reddit API key

@MainActor func checkKeylessSignInWithoutAPIKey() {
    let saved = RedditOAuthConfig.clientID
    defer { RedditOAuthConfig.clientID = saved }
    RedditOAuthConfig.clientID = RedditOAuthConfig.defaultClientID
    check("the build's placeholder client ID is not a configured API key", !RedditOAuthConfig.hasConfiguredClientID)
    RedditOAuthConfig.clientID = ""
    check("...nor is an empty one", !RedditOAuthConfig.hasConfiguredClientID)
    RedditOAuthConfig.clientID = "abc123"
    check("a key the user entered is", RedditOAuthConfig.hasConfiguredClientID)
    check("the message tells an API-key sign-in without a key where to go",
          RedditOAuthConfig.missingClientIDMessage.contains("Custom API Settings")
            && RedditOAuthConfig.missingClientIDMessage.contains("without an API key"))
}
