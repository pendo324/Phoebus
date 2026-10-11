import Foundation

/// The endpoints Reddit refuses over a web session's cookie (the moderator
/// ones, and private-message compose), so a
/// keyless account sends them to `oauth.reddit.com` with the account's web
/// bearer instead (`RedditAPIClient`). API-key accounts are unaffected.
///
/// Reborn "Removal reasons" (#1292, #1298), "Mod user lists" (#1304) and
/// "Moderator Mail" (#1311): www answers the OAuth-only ones with a 403 for
/// any cookie request and 404s the `/r/<sub>/api/` writes.
public enum WebBearerRouting {
    /// Subreddit user lists and declining a mod invite, `/api/v1/<sub>/<name>`.
    private static let subredditEndpoints: Set<String> = [
        "removal_reasons", "contributors", "banned", "muted", "moderators",
        "moderators_invited", "decline_mod_invite",
    ]

    /// Subreddit-scoped writes, `/r/<sub>/api/<name>`. Reborn lists friend and
    /// accept_moderator_invite; unfriend is the same family Phoebus sends for
    /// unbanning and removing a moderator.
    private static let subredditWrites: Set<String> = ["friend", "unfriend", "accept_moderator_invite"]

    /// Whether a request path (with or without a query) must use the bearer.
    public static func needsBearer(path: String) -> Bool {
        let bare = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? path
        let parts = bare.lowercased().split(separator: "/").map(String.init)

        // Sending a private message (also "message the moderators"). Phoebus
        // only: Reborn leaves /api/compose on the cookie, where www answers 401.
        if parts == ["api", "compose"] { return true }

        guard parts.count >= 3 else { return false }

        // New modmail: the list, a thread and every action under it.
        if parts[0] == "api", parts[1] == "mod", parts[2] == "conversations" { return true }
        // Mod notes (`/api/mod/notes`, `/api/mod/notes/recent`): www answers 403 to the cookie.
        if parts[0] == "api", parts[1] == "mod", parts[2] == "notes" { return true }

        if parts[0] == "api", parts[1] == "v1" {
            // Removal-reason logging and notices: /api/v1/modactions/<action>.
            if parts[2] == "modactions" { return parts.count == 4 }
            // /api/v1/<sub>/removal_reasons[/<id>] and the other per-sub endpoints.
            guard parts.count >= 4, subredditEndpoints.contains(parts[3]) else { return false }
            return parts.count == 4 || (parts.count == 5 && parts[3] == "removal_reasons")
        }

        return parts.count == 4 && parts[0] == "r" && parts[2] == "api" && subredditWrites.contains(parts[3])
    }
}
