import Foundation

/// Decodes the accounts out of an Apollo backup's `keychain.plist`: the Valet
/// items a restore replays so the user is signed back in.
///
/// Three of its items carry credentials:
///
///     VAL_VALValet_…_com.christianselig.Apollo_…
///       account `2RedditAccounts2`        NSKeyedArchiver blob:
///                                         NSArray<NSDictionary> with
///                                         clientIdentifier /
///                                         refreshToken /
///                                         authorizationCode /
///                                         accessToken
///       account `2ApplicationOnlyAccount2` the app-only token
///     com.christianselig.Apollo.webjson
///       account `websession:<user>:cookie`  the cookie header
///       account `websession:<user>:modhash` the CSRF modhash
///
/// The remaining items (`deviceSeed`, the Valet canary, a feature flag) are not
/// credentials and are ignored. The OAuth blob is decoded via
/// `NSKeyedUnarchiver`; see `KeyedArchiveReader` for why that works on Linux.
public enum ApolloKeychainImport {
    /// Apollo's own service names.
    public static let webJSONService = "com.christianselig.Apollo.webjson"

    /// The Valet account names holding the OAuth blobs.
    public static let redditAccountsAccount = "2RedditAccounts2"
    public static let applicationOnlyAccount = "2ApplicationOnlyAccount2"

    /// One decoded account.
    public struct ImportedAccount: Equatable, Sendable {
        public var username: String
        public var clientIdentifier: String?
        public var accessToken: String?
        public var refreshToken: String?
        /// `name=value; …` header, from `websession:<user>:cookie`.
        public var cookieHeader: String?
        /// From `websession:<user>:modhash`.
        public var modhash: String?

        public init(username: String,
                    clientIdentifier: String? = nil,
                    accessToken: String? = nil,
                    refreshToken: String? = nil,
                    cookieHeader: String? = nil,
                    modhash: String? = nil) {
            self.username = username
            self.clientIdentifier = clientIdentifier
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            self.cookieHeader = cookieHeader
            self.modhash = modhash
        }

        public var hasOAuth: Bool { !(accessToken ?? "").isEmpty }
        public var hasWebSession: Bool { !(cookieHeader ?? "").isEmpty }
    }

    /// Whether a keychain identity is one Apollo owns. A backup is untrusted and
    /// a keychain item is a credential, so only the exact Apollo-owned namespaces
    /// are accepted, not any name that merely contains Apollo's bundle ID.
    public static func ownsIdentity(service: String, account: String) -> Bool {
        guard !account.isEmpty,
              !service.contains(where: \.isNewline),
              !account.contains(where: \.isNewline) else { return false }
        if service == webJSONService {
            if ["sessionCookieHeader", "sessionModhash", "sessionUsername"].contains(account) {
                return true
            }
            // `^websession:[^:\s]+:(cookie|modhash)$`.
            let parts = account.split(separator: ":", omittingEmptySubsequences: false)
            return parts.count == 3
                && parts[0] == "websession"
                && !parts[1].isEmpty
                && !parts[1].contains(where: { $0 == " " })
                && (parts[2] == "cookie" || parts[2] == "modhash")
        }
        // The Valet form is matched on its stable prefix and bundle id; the
        // accessibility suffix varies by class and every variant is Apollo's.
        return service.hasPrefix("VAL_VAL")
            && service.contains("_com.christianselig.Apollo_")
    }

    /// Reads every account it can find.
    public static func accounts(fromKeychainPlist data: Data) -> [ImportedAccount] {
        guard let items = (try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil)) as? [[String: Any]] else { return [] }

        var oauthByIndex: [[String: String]] = []
        var cookiesByUser: [String: String] = [:]
        var modhashByUser: [String: String] = [:]

        for item in items {
            guard let service = item["service"] as? String,
                  let account = item["account"] as? String,
                  let blob = item["data"] as? Data,
                  ownsIdentity(service: service, account: account) else { continue }

            if service == webJSONService {
                let parts = account.split(separator: ":", omittingEmptySubsequences: false)
                guard parts.count == 3 else { continue }
                let user = String(parts[1]).lowercased()
                let value = String(decoding: blob, as: UTF8.self)
                if parts[2] == "cookie" { cookiesByUser[user] = value }
                if parts[2] == "modhash" { modhashByUser[user] = value }
            } else if account == redditAccountsAccount {
                oauthByIndex = KeyedArchiveReader.dictionaries(in: blob)
            }
        }

        // Usernames come from the web session keys. The OAuth blob holds only
        // tokens, in account order, so they are matched positionally against
        // `accounts.txt` by the caller.
        var result: [ImportedAccount] = []
        for user in Set(cookiesByUser.keys).union(modhashByUser.keys).sorted() {
            result.append(ImportedAccount(
                username: user,
                cookieHeader: cookiesByUser[user],
                modhash: modhashByUser[user]))
        }
        // Attach OAuth tokens positionally.
        for (index, fields) in oauthByIndex.enumerated() where index < result.count {
            result[index].clientIdentifier = fields["clientIdentifier"]
            result[index].accessToken = fields["accessToken"]
            result[index].refreshToken = fields["refreshToken"]
        }
        // An OAuth-only account (no web session) still has to appear.
        if result.isEmpty, let first = oauthByIndex.first {
            result.append(ImportedAccount(
                username: "",
                clientIdentifier: first["clientIdentifier"],
                accessToken: first["accessToken"],
                refreshToken: first["refreshToken"]))
        }
        return result
    }

    /// Fills in usernames from `accounts.txt` for accounts that only
    /// had an OAuth blob (which carries no username).
    public static func applyingUsernames(_ accounts: [ImportedAccount],
                                         from accountsFile: String) -> [ImportedAccount] {
        let names = accountsFile
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        var result = accounts
        for index in result.indices where result[index].username.isEmpty {
            if index < names.count { result[index].username = names[index] }
        }
        return result
    }
}

/// Reads Apollo's archived account list with `NSKeyedUnarchiver`, which exists
/// on Linux via swift-corelibs-foundation. Resolving `$objects` by hand does
/// not work there: a `UID` bridges to `_NSKeyedArchiverUID`, which casts to
/// neither `Int` nor `NSNumber`.
enum KeyedArchiveReader {
    /// Every `[String: String]` dictionary in the archived array.
    static func dictionaries(in data: Data) -> [[String: String]] {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return [] }
        // The blob predates secure coding and holds plain NSArray/NSDictionary/
        // NSString, so secure coding must be off for the root decode.
        unarchiver.requiresSecureCoding = false
        defer { unarchiver.finishDecoding() }
        let root = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
        if let typed = root as? [[String: String]] { return typed }
        // Filter per entry so one non-string field does not lose every account.
        if let array = root as? [[String: Any]] {
            return array.map { entry in
                entry.compactMapValues { $0 as? String }
            }
        }
        return []
    }
}
