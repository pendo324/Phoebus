import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reborn "Open via Nitter" (#1334): opens X/Twitter page links on a Nitter
/// mirror so posts can be read without an X account. Nitter has no app and
/// public instances challenge scripted requests, so this only rewrites the
/// link for a browser; nothing here talks to an instance. Tweet preview cards
/// are a separate pipeline and are unaffected.
public enum NitterInstances {
    // MARK: Settings

    /// Reborn's keys. The host is empty until one is picked, which leaves the
    /// feature off even when the toggle is on.
    public static let enabledKey = "OpenTwitterLinksViaNitter"
    public static let hostKey = "NitterInstanceHost"

    /// The saved instance when the feature is on and the saved host is valid.
    public static func activeHost(defaults: UserDefaults = .standard) -> String? {
        guard defaults.bool(forKey: enabledKey) else { return nil }
        return savedHost(defaults: defaults)
    }

    public static func savedHost(defaults: UserDefaults = .standard) -> String? {
        normalizeHost(defaults.string(forKey: hostKey))
    }

    // MARK: Host matching

    private static func host(_ host: String, isOrIsUnder domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }

    private static func isXOwned(_ host: String) -> Bool {
        ["x.com", "twitter.com", "t.co", "twimg.com"].contains { self.host(host, isOrIsUnder: $0) }
    }

    /// Only X's web front doors are rewritten; api., help., developer., pbs. and
    /// the like serve things Nitter has no equivalent for.
    private static let rewritableHosts: Set<String> = [
        "x.com", "www.x.com", "mobile.x.com",
        "twitter.com", "www.twitter.com", "mobile.twitter.com",
    ]

    /// A plausible public DNS name: dotted, LDH labels, no empty or hyphen-edged
    /// labels. It only has to keep typos and non-hosts out of the setting.
    private static func isPlausibleHostname(_ host: String) -> Bool {
        guard host.count >= 4, host.count <= 253 else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        for label in labels {
            if label.isEmpty || label.count > 63 { return false }
            if label.hasPrefix("-") || label.hasSuffix("-") { return false }
            if label.contains(where: { !allowed.contains($0) }) { return false }
        }
        return true
    }

    /// Normalizes user input ("nitter.example.org", "https://nitter.example.org/foo",
    /// "Nitter.Example.org:8443") to a lowercase "host" or "host:port", meaning
    /// https. An explicit http:// is kept ("http://host[:port]") for self-hosted
    /// instances served without TLS. Nil for anything that isn't a plausible
    /// dotted hostname, and for X/Twitter's own domains (pointing the mirror at X
    /// would loop straight back).
    public static func normalizeHost(_ input: String?) -> String? {
        guard var trimmed = input?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") { trimmed = "https://" + trimmed }

        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme, scheme == "https" || scheme == "http",
              (components.user ?? "").isEmpty, (components.password ?? "").isEmpty,
              let host = components.host?.lowercased(),
              isPlausibleHostname(host), !isXOwned(host) else { return nil }

        // https stays bare; an explicit http:// is kept so a plain-http instance
        // isn't silently upgraded to an address that doesn't answer.
        let plainHTTP = scheme == "http"
        let address = plainHTTP ? "http://" + host : host
        if let port = components.port {
            guard port > 0, port <= 65535 else { return nil }
            if port != (plainHTTP ? 80 : 443) { return "\(address):\(port)" }
        }
        return address
    }

    // MARK: URL rewriting

    /// First path segments that are X app pages rather than profiles; Nitter has
    /// no equivalent (or, for /explore, redirects to its own about page).
    private static let unsupportedTopLevelPaths: Set<String> = [
        "home", "explore", "settings", "messages", "notifications", "compose",
        "login", "logout", "signup", "account", "intent", "share",
        "tos", "privacy", "rules", "jobs", "download",
    ]

    /// `/i/<kind>/...` routes Nitter serves itself; it shows "feature not
    /// supported" for every other `/i/` path.
    private static let supportedInternalPaths: Set<String> = [
        "status", "web", "lists", "communities", "spaces", "broadcasts", "article", "user",
    ]

    private static let queryAllowed = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    /// Rewrites an X/Twitter web URL onto `instanceHost` (a `normalizeHost`
    /// result). Nil when the URL isn't an x.com / twitter.com page link or
    /// points at a page Nitter can't serve, so the caller keeps its normal
    /// routing. X's tracking parameters are dropped; a search keeps its query.
    public static func url(for url: URL, instanceHost: String?) -> URL? {
        guard let instanceHost, !instanceHost.isEmpty,
              let source = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let scheme = source.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let sourceHost = source.host?.lowercased(), rewritableHosts.contains(sourceHost) else { return nil }

        let base = instanceHost.hasPrefix("http://") ? instanceHost : "https://" + instanceHost
        guard let instance = URLComponents(string: base),
              let instanceScheme = instance.scheme, let host = instance.host, !host.isEmpty else { return nil }

        let segments = source.percentEncodedPath.split(separator: "/").map(String.init)
        let first = segments.first?.lowercased()
        if let first {
            if first == "i" {
                guard segments.count >= 2, supportedInternalPaths.contains(segments[1].lowercased()) else { return nil }
            } else if unsupportedTopLevelPaths.contains(first) {
                return nil
            }
        }

        var rewritten = URLComponents()
        rewritten.scheme = instanceScheme
        rewritten.host = host
        rewritten.port = instance.port
        rewritten.percentEncodedPath = segments.isEmpty ? "/" : "/" + segments.joined(separator: "/")

        // Nothing else in an X page query means anything to Nitter, so only a
        // search keeps its text, with X's people tab mapped onto Nitter's.
        if first == "search" {
            let items = source.queryItems ?? []
            let query = items.first { $0.name == "q" }?.value
            let tab = items.first { $0.name == "f" }?.value
            if let query, !query.isEmpty,
               let encoded = query.addingPercentEncoding(withAllowedCharacters: queryAllowed) {
                rewritten.percentEncodedQuery = "f=\(tab == "user" ? "users" : "tweets")&q=\(encoded)"
            }
        }
        return rewritten.url
    }

    /// The URL to open for a tapped link when "Open via Nitter" is on and a
    /// valid instance is saved, else nil.
    public static func rewrittenURL(for url: URL, defaults: UserDefaults = .standard) -> URL? {
        self.url(for: url, instanceHost: activeHost(defaults: defaults))
    }

    // MARK: Instance list

    /// One healthy public instance from the status.d420.de tracker.
    public struct Instance: Equatable, Sendable {
        /// A `normalizeHost` result (always https, so a bare host).
        public let host: String
        /// The tracker's health score; the list is sorted by it, highest first.
        public let points: Int
        /// Average response time over the tracker's recent pings, 0 when unknown.
        public let averagePingMilliseconds: Int

        public init(host: String, points: Int, averagePingMilliseconds: Int) {
            self.host = host
            self.points = points
            self.averagePingMilliseconds = averagePingMilliseconds
        }
    }

    static let trackerURL = URL(string: "https://status.d420.de/api/v1/instances")!

    /// Parses the tracker's `/api/v1/instances` JSON into the healthy
    /// instances, best first. Malformed entries are skipped; nil when the
    /// payload itself isn't the expected shape.
    public static func parseInstanceList(_ data: Data?) -> [Instance]? {
        guard let data, !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hosts = json["hosts"] as? [Any] else { return nil }

        var instances: [Instance] = []
        var seen: Set<String> = []
        for entry in hosts {
            guard let dict = entry as? [String: Any], isTrue(dict["healthy"]),
                  let domain = dict["domain"] as? String, let host = normalizeHost(domain),
                  // Public instances are https only; plain http is for an
                  // address the user typed, never one the tracker hands us.
                  !host.hasPrefix("http://"), seen.insert(host).inserted else { continue }
            instances.append(Instance(host: host,
                                      points: integer(dict["points"]),
                                      averagePingMilliseconds: max(0, integer(dict["ping_avg"]))))
        }
        return instances.sorted { $0.points != $1.points ? $0.points > $1.points : $0.host < $1.host }
    }

    private static func isTrue(_ value: Any?) -> Bool {
        guard let value = value as? NSNumber else { return false }
        return value.boolValue
    }

    private static func integer(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }
}

/// Fetches the tracker's healthy-instance list. The tracker rate-limits hard (a
/// second request seconds after the first gets a 429), so this is only called
/// when the picker opens, never in the background; a successful result is
/// reused for 15 minutes and concurrent callers share one request.
public actor NitterInstanceDirectory {
    public static let shared = NitterInstanceDirectory()

    public static let cacheLifetime: TimeInterval = 15 * 60

    public struct TrackerError: Error, Equatable, Sendable {
        public let message: String
    }

    private let now: @Sendable () -> Date
    private let fetch: @Sendable () async throws -> (Data, Int)
    private var cached: (instances: [NitterInstances.Instance], date: Date)?
    private var inFlight: Task<[NitterInstances.Instance], Error>?

    public init(now: @escaping @Sendable () -> Date = { Date() },
                fetch: @escaping @Sendable () async throws -> (Data, Int) = NitterInstanceDirectory.fetchFromTracker) {
        self.now = now
        self.fetch = fetch
    }

    public func healthyInstances() async throws -> [NitterInstances.Instance] {
        if let cached, now().timeIntervalSince(cached.date) < Self.cacheLifetime {
            return cached.instances
        }
        if let inFlight { return try await inFlight.value }

        let fetch = fetch
        let task = Task { () throws -> [NitterInstances.Instance] in
            let (data, status) = try await fetch()
            guard status == 200 else {
                throw TrackerError(message: "Instance tracker returned HTTP \(status)")
            }
            guard let instances = NitterInstances.parseInstanceList(data) else {
                throw TrackerError(message: "Instance tracker returned an unexpected response")
            }
            return instances
        }
        inFlight = task
        defer { inFlight = nil }
        let instances = try await task.value
        cached = (instances, now())
        return instances
    }

    @Sendable
    public static func fetchFromTracker() async throws -> (Data, Int) {
        // Ephemeral: no cookies or disk cache left behind by a third-party tracker.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        var request = URLRequest(url: NitterInstances.trackerURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
