import Foundation

/// "Copy to My Multireddits" on someone else's multireddit (`POST /api/multi/copy`).
/// Not in Apollo or Reborn. The rules here are Reddit's own: a display name of up to
/// 50 characters, and a path name of a letter or digit followed by 1 to 20 letters,
/// digits or underscores.
public enum MultiredditCopy {
    public static let maxDisplayNameLength = 50
    public static let maxPathNameLength = 21

    public enum NameProblem: Equatable, Sendable {
        case empty
        case tooLong
        /// Nothing left once spaces and unsupported characters are dropped, so
        /// Reddit could not build a path for it.
        case noLettersOrDigits

        public var message: String {
            switch self {
            case .empty: return "Enter a name."
            case .tooLong: return "Names can be at most \(MultiredditCopy.maxDisplayNameLength) characters."
            case .noLettersOrDigits: return "Names need at least two letters or numbers."
            }
        }
    }

    /// The `<owner>` of `/user/<owner>/m/<name>`, or nil for any other shape.
    public static func owner(ofPath path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 4, parts[0] == "user", parts[2] == "m", !parts[1].isEmpty else { return nil }
        return parts[1]
    }

    /// Offered when signed in and the multireddit belongs to someone else.
    public static func canCopy(path: String, signedInUsername: String?) -> Bool {
        guard let signedInUsername, !signedInUsername.isEmpty,
              let owner = owner(ofPath: path) else { return false }
        return owner.caseInsensitiveCompare(signedInUsername) != .orderedSame
    }

    /// The path name for a display name: spaces become underscores, other
    /// unsupported characters and leading underscores are dropped, capped at
    /// Reddit's 21 characters.
    public static func pathName(forDisplayName displayName: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        var name = String(displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
            .filter { allowed.contains($0) })
        while name.hasPrefix("_") { name.removeFirst() }
        return String(name.prefix(maxPathNameLength))
    }

    public static func problem(with displayName: String) -> NameProblem? {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        if trimmed.count > maxDisplayNameLength { return .tooLong }
        if pathName(forDisplayName: trimmed).count < 2 { return .noLettersOrDigits }
        return nil
    }

    /// `/user/<username>/m/<name>`, numbered when one of `existingPaths` already
    /// uses that name, since Reddit refuses a copy onto an existing multireddit.
    public static func destinationPath(displayName: String, username: String, existingPaths: [String]) -> String {
        let base = pathName(forDisplayName: displayName)
        let taken = Set(existingPaths.compactMap { $0.split(separator: "/").last.map { $0.lowercased() } })
        var name = base
        var count = 0
        while taken.contains(name.lowercased()) {
            count += 1
            let suffix = String(count)
            name = String(base.prefix(maxPathNameLength - suffix.count)) + suffix
        }
        return "/user/\(username)/m/\(name)"
    }

    /// Form fields for `POST /api/multi/copy`. Without `to`, Reddit would copy onto
    /// the source owner's account. Reddit itself carries the description over and
    /// adds a "copied from" line, so none is sent.
    public static func parameters(sourcePath: String, destinationPath: String, displayName: String) -> [String: String] {
        [
            "from": sourcePath,
            "to": destinationPath,
            "display_name": displayName.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
    }

    /// The new multireddit from the endpoint's `LabeledMulti` response.
    public static func copiedMultireddit(from data: Data) -> RedditMultireddit? {
        try? JSONDecoder.reddit.decode(RedditThing<RedditMultireddit>.self, from: data).data
    }
}
