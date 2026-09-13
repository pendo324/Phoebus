import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reborn's poll composer: `POST /api/submit_poll_post.json` (new.reddit.com's
/// web submission endpoint; classic `/api/submit` has no poll kind),
/// authenticated with the web session's cookie and `X-Modhash` header,
/// unlike poll voting, which uses a CSRF token.
public enum PollComposeService {
    /// Bounds: 2-6 options, 1-7 day duration, 3-day default.
    public static let minOptions = 2
    public static let maxOptions = 6
    public static let minDurationDays = 1
    public static let maxDurationDays = 7
    public static let defaultDurationDays = 3

    public enum ComposeError: LocalizedError {
        case requiresWebSession
        case missingModhash
        case invalidTitle
        case tooFewOptions
        case network(Error)
        case rejected(String)

        public var errorDescription: String? {
            switch self {
            case .requiresWebSession:
                return "Poll creation requires signing in via a web session (Settings > Accounts)."
            case .missingModhash:
                return "The stored Reddit session has no modhash. Sign in again and retry."
            case .invalidTitle:
                return "A poll needs a title."
            case .tooFewOptions:
                return "A poll needs at least \(minOptions) options."
            case .network(let error):
                return error.localizedDescription
            case .rejected(let message):
                return message
            }
        }
    }

    /// - Returns: the URL of the newly created post.
    @discardableResult
    public static func submit(
        subreddit: String,
        title: String,
        options: [String],
        durationDays: Int,
        flairID: String? = nil,
        flairText: String? = nil,
        session: WebSessionCredential
    ) async throws -> URL {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw ComposeError.invalidTitle }
        let filledOptions = options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard filledOptions.count >= minOptions else { throw ComposeError.tooFewOptions }
        guard let modhash = session.modhash, !modhash.isEmpty else { throw ComposeError.missingModhash }

        var body: [String: Any] = [
            "sr": subreddit,
            "title": trimmedTitle,
            "text": "",
            "options": filledOptions,
            "duration": min(max(durationDays, minDurationDays), maxDurationDays),
            "api_type": "json",
            "kind": "poll",
            "resubmit": true,
            "sendreplies": true
        ]
        if let flairID, !flairID.isEmpty { body["flair_id"] = flairID }
        if let flairText, !flairText.isEmpty { body["flair_text"] = flairText }

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            throw ComposeError.network(URLError(.cannotCreateFile))
        }

        var request = URLRequest(url: URL(string: "https://www.reddit.com/api/submit_poll_post.json")!)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.timeoutInterval = 30
        request.setValue(session.cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue(modhash, forHTTPHeaderField: "X-Modhash")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let config = URLSessionConfiguration.ephemeral
        let urlSession = URLSession(configuration: config)
        let (data, response) = try await urlSession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let jsonField = json?["json"] as? [String: Any]
        let errors = jsonField?["errors"] as? [[Any]] ?? []
        let postURLString = (jsonField?["data"] as? [String: Any])?["url"] as? String

        guard status == 200, errors.isEmpty, let postURLString, let postURL = URL(string: postURLString) else {
            let serverMessage = (errors.first?.count ?? 0) > 1 ? errors.first?[1] as? String : nil
            let message: String
            switch status {
            case 429: message = "Reddit is rate limiting posts. Wait a moment before trying again."
            case 401: message = "The Reddit web session expired. Sign in again and retry."
            default: message = serverMessage ?? "Reddit did not confirm the poll submission."
            }
            throw ComposeError.rejected(message)
        }
        return postURL
    }
}
