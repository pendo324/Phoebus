import Foundation

/// What to tell the user when something failed, in place of a raw
/// `"\(error)"` dump such as `httpError(status: 403, body: "{…}")`. A
/// cancelled sign-in is not shown as an error.
public enum UserFacingError {
    /// nil for a cancellation, which is the user's own doing and says
    /// nothing went wrong.
    public static func message(for error: Error) -> String? {
        if error is CancellationError { return nil }
        if let url = error as? URLError {
            switch url.code {
            case .cancelled: return nil
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "You appear to be offline."
            case .timedOut: return "Reddit took too long to respond. Try again."
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "Couldn't reach the server. Check your connection."
            default: return "A network error occurred. Try again."
            }
        }
        if (error as NSError).domain == "com.apple.AuthenticationServices.WebAuthenticationSession",
           (error as NSError).code == 1 { return nil }
        if let rejected = error as? CommentRejectedError {
            let said = CommentSubmitFailure.sentence(rejected.message)
            return said.isEmpty ? "Reddit didn't accept this." : said
        }
        if let api = error as? RedditAPIError {
            switch api {
            case .notAuthenticated: return "You need to be signed in to do that."
            case .sessionExpired: return "Your Reddit session expired. Sign in again."
            case .decodingFailed: return "Reddit sent something this app couldn't read."
            case .httpError(let status, _): return httpMessage(status)
            }
        }
        if error is DecodingError { return "Reddit sent something this app couldn't read." }
        if let described = (error as? LocalizedError)?.errorDescription, !described.isEmpty { return described }
        return "Something went wrong. Try again."
    }

    /// The same, never nil, for use inside a longer sentence.
    public static func text(for error: Error) -> String {
        message(for: error) ?? "Cancelled."
    }

    static func httpMessage(_ status: Int) -> String {
        switch status {
        case 401: return "Reddit didn't accept your sign-in. Sign in again."
        case 403: return "You don't have permission to do that."
        case 404: return "That couldn't be found. It may have been deleted."
        case 429: return "Reddit is rate-limiting requests. Try again in a minute."
        case 500...599: return "Reddit is having trouble right now (HTTP \(status)). Try again soon."
        default: return "Reddit returned an error (HTTP \(status))."
        }
    }
}
