import Foundation

/// Kind-erased mod queue entry, a t1 (comment) or t3 (post) with different
/// display fields, as Reddit's modqueue endpoint returns a mixed listing.
/// Lives in PhoebusCore so its report-reason parsing is exercisable by the
/// Linux-hosted smoke test.
public struct ModQueueItem: Identifiable, Sendable {
    public let id: String
    public let fullname: String
    public let kind: String
    public let title: String
    public let body: String
    public let author: String
    public let numReports: Int
    /// The actual report reasons, not just a count. Reddit's `user_reports`
    /// is `[[reasonText, reportCount], ...]`; `mod_reports` is
    /// `[[reasonText, moderatorName], ...]`.
    public let userReportReasons: [(reason: String, count: Int)]
    public let modReportReasons: [(reason: String, moderator: String)]

    public init?(kind: String, raw: [String: JSONValue]) {
        guard case .string(let id)? = raw["id"],
              case .string(let name)? = raw["name"],
              case .string(let author)? = raw["author"] else { return nil }

        self.id = id
        self.fullname = name
        self.kind = kind
        self.author = author

        if case .number(let reports)? = raw["num_reports"] {
            numReports = Int(reports)
        } else {
            numReports = 0
        }

        if case .array(let userReports)? = raw["user_reports"] {
            userReportReasons = userReports.compactMap { entry -> (String, Int)? in
                guard case .array(let pair) = entry, pair.count == 2,
                      case .string(let reason) = pair[0] else { return nil }
                if case .number(let count) = pair[1] {
                    return (reason, Int(count))
                }
                return (reason, 1)
            }
        } else {
            userReportReasons = []
        }

        if case .array(let modReports)? = raw["mod_reports"] {
            modReportReasons = modReports.compactMap { entry -> (String, String)? in
                guard case .array(let pair) = entry, pair.count == 2,
                      case .string(let reason) = pair[0],
                      case .string(let moderator) = pair[1] else { return nil }
                return (reason, moderator)
            }
        } else {
            modReportReasons = []
        }

        if kind == "t3", case .string(let title)? = raw["title"] {
            self.title = title
            if case .string(let selftext)? = raw["selftext"] {
                self.body = selftext
            } else {
                self.body = ""
            }
        } else if case .string(let commentBody)? = raw["body"] {
            self.title = "Comment"
            self.body = commentBody
        } else {
            self.title = "Item"
            self.body = ""
        }
    }
}
