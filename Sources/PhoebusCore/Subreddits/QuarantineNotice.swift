import Foundation

/// A quarantined subreddit's refusal. Reddit answers 403 with
/// `reason: "quarantined"` (and its own warning in `quarantine_message`)
/// until the account opts in. Not an Apollo or Reborn feature.
public struct QuarantineNotice: Equatable, Sendable {
    /// Reddit's warning, as Markdown; nil when the body didn't carry one.
    public let message: String?

    public init(message: String?) {
        self.message = message
    }

    /// The notice in a failed request, or nil when it wasn't a quarantine.
    public init?(error: Error) {
        guard case let RedditAPIError.httpError(status, body) = error else { return nil }
        self.init(status: status, body: body)
    }

    public init?(status: Int, body: String) {
        guard status == 403,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["reason"] as? String)?.lowercased() == "quarantined" else { return nil }
        let raw = (json["quarantine_message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        // Without `raw_json=1` Reddit escapes the Markdown's entities.
        let message = raw.map {
            $0.replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&amp;", with: "&")
        }
        self.message = message?.isEmpty == false ? message : nil
    }

    /// `POST /api/quarantine_option`'s form: opting in (`accept=true`) lifts
    /// the 403; opting out puts it back.
    public static func optionParameters(subreddit: String, accept: Bool) -> [String: String] {
        ["accept": accept ? "true" : "false", "sr_name": subreddit]
    }
}
