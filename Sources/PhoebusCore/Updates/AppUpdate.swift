import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Where a build looks for updates: the AltStore source of its channel
/// (docs/releases.md). Phoebus-only; Reborn reads its own release manifest.
public enum AppUpdateSource {
    public static let bundleIdentifier = "com.pendo324.Phoebus"

    public static func sourceURL(for channel: BuildChannel) -> URL {
        switch channel {
        case .stable: URL(string: "https://pendo324.github.io/AltStoreRepo/source.json")!
        case .nightly: URL(string: "https://pendo324.github.io/AltStoreRepo/nightly/source.json")!
        }
    }
}

/// The newest build in the channel's source, when it is newer than the installed one.
public struct AppUpdate: Sendable, Equatable {
    public let channel: BuildChannel
    public let version: String
    /// `CFBundleVersion`, which only goes up across both channels.
    public let build: Int
    public let date: Date?
    /// The source's `localizedDescription` for the build: the commit subject
    /// for a nightly, a link to the release notes for a stable release.
    public let notes: String
    public let downloadURL: URL?

    public var sourceURL: URL { AppUpdateSource.sourceURL(for: channel) }
    public var versionText: String { "\(version) (\(build))" }

    /// The first https link in the notes, shown as a link on the sheet.
    public var notesURL: URL? {
        guard let range = notes.range(of: #"https://[^\s<>"]+"#, options: .regularExpression) else { return nil }
        let link = notes[range].trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)"))
        return URL(string: link)
    }
}

public enum AppUpdateResult: Sendable, Equatable {
    case upToDate
    case available(AppUpdate)
}

public enum AppUpdateChecker {
    public enum CheckError: Error, Sendable {
        case badResponse
        case unusableSource
    }

    /// The installed build number, from an Info.plist's `CFBundleVersion`.
    public static func installedBuild(infoDictionary: [String: Any]?) -> Int? {
        (infoDictionary?["CFBundleVersion"] as? String).flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    public static func check(channel: BuildChannel, installedBuild: Int,
                             session: URLSession = .shared) async throws -> AppUpdateResult {
        var request = URLRequest(url: AppUpdateSource.sourceURL(for: channel))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw CheckError.badResponse }
        guard let result = parse(data, channel: channel, installedBuild: installedBuild) else { throw CheckError.unusableSource }
        return result
    }

    /// Reads an AltStore source (v2: `apps[].versions[]`; the older flat
    /// `version`/`buildVersion` fields when an app has no versions list) and
    /// compares the app's newest build with `installedBuild`. Nil when the
    /// source has no usable entry for Phoebus.
    public static func parse(_ data: Data, channel: BuildChannel, installedBuild: Int) -> AppUpdateResult? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let apps = json["apps"] as? [[String: Any]],
              let app = apps.first(where: { $0["bundleIdentifier"] as? String == AppUpdateSource.bundleIdentifier })
        else { return nil }

        var entries = (app["versions"] as? [[String: Any]]) ?? []
        if entries.isEmpty, app["version"] != nil {
            entries = [[
                "version": app["version"] as Any, "buildVersion": app["buildVersion"] as Any,
                "date": app["versionDate"] as Any, "localizedDescription": app["versionDescription"] as Any,
                "downloadURL": app["downloadURL"] as Any,
            ]]
        }
        let newest = entries.compactMap { entry -> (build: Int, entry: [String: Any])? in
            guard let build = buildNumber(entry["buildVersion"]) else { return nil }
            return (build, entry)
        }.max { $0.build < $1.build }
        guard let newest, let version = (newest.entry["version"] as? String).flatMap(nonEmpty) else { return nil }
        guard newest.build > installedBuild else { return .upToDate }

        return .available(AppUpdate(
            channel: channel,
            version: version,
            build: newest.build,
            date: (newest.entry["date"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) },
            notes: ((newest.entry["localizedDescription"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            downloadURL: httpsURL(newest.entry["downloadURL"])))
    }

    private static func buildNumber(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        return (value as? String).flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    private static func nonEmpty(_ string: String) -> String? { string.isEmpty ? nil : string }

    /// https only: these URLs are handed to other apps and Safari.
    private static func httpsURL(_ value: Any?) -> URL? {
        guard let string = value as? String, let url = URL(string: string),
              url.scheme?.lowercased() == "https", url.host?.isEmpty == false else { return nil }
        return url
    }
}

/// The apps the update sheet hands off to. A sideloaded app can't replace
/// itself, so the sideloader installs it. Reborn "In-App Update Prompt"
/// (#1343): the same four sideloaders and link shapes.
public enum UpdateSideloader: CaseIterable, Sendable {
    case altStore
    case sideStore
    case feather
    case flareStore

    public var title: String {
        switch self {
        case .altStore: "AltStore"
        case .sideStore: "SideStore"
        case .feather: "Feather"
        case .flareStore: "FlareStore"
        }
    }

    /// What the row opens: the build's IPA where the app takes one, else the
    /// channel's source to add.
    public func handoffURL(for update: AppUpdate) -> URL? {
        let source = update.sourceURL.absoluteString
        switch self {
        case .altStore, .sideStore:
            var components = URLComponents()
            components.scheme = self == .altStore ? "altstore-classic" : "sidestore"
            components.host = "source"
            components.queryItems = [URLQueryItem(name: "url", value: source)]
            return components.url
        case .feather:
            if let ipa = update.downloadURL { return URL(string: "feather://install/" + ipa.absoluteString) }
            return URL(string: "feather://source/" + source)
        case .flareStore:
            if let ipa = update.downloadURL { return URL(string: "flarestore://downloadApp=" + ipa.absoluteString) }
            return URL(string: "flarestore://")
        }
    }
}

/// Where Update goes: one of the sideloaders, the IPA download, or the
/// chooser. Phoebus-only; Reborn always shows the chooser.
public enum UpdateInstaller: String, Codable, Sendable, CaseIterable, Identifiable {
    case askEveryTime
    case altStore
    case sideStore
    case feather
    case flareStore
    case downloadIPA

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .askEveryTime: "Ask Every Time"
        case .altStore: UpdateSideloader.altStore.title
        case .sideStore: UpdateSideloader.sideStore.title
        case .feather: UpdateSideloader.feather.title
        case .flareStore: UpdateSideloader.flareStore.title
        case .downloadIPA: "Download IPA"
        }
    }

    public var sideloader: UpdateSideloader? {
        switch self {
        case .askEveryTime, .downloadIPA: nil
        case .altStore: .altStore
        case .sideStore: .sideStore
        case .feather: .feather
        case .flareStore: .flareStore
        }
    }

    /// Falls back to asking for a value this build doesn't know (a restored backup).
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = UpdateInstaller(rawValue: raw) ?? .askEveryTime
    }

    /// What this installer opens for the update; nil for Ask Every Time and
    /// for the IPA download of a source entry without a download link.
    public func handoffURL(for update: AppUpdate) -> URL? {
        if let sideloader { return sideloader.handoffURL(for: update) }
        return self == .downloadIPA ? update.downloadURL : nil
    }

    /// The chooser's rows: every installer that can take this update.
    public static func choices(for update: AppUpdate) -> [UpdateInstaller] {
        allCases.filter { $0 != .askEveryTime && $0.handoffURL(for: update) != nil }
    }
}

/// What tapping Update does.
public enum UpdateHandoff: Sendable, Equatable {
    case chooser
    case open(UpdateInstaller, URL)

    /// A chosen installer is opened directly. Ask Every Time, and a choice
    /// with nothing to open for this update, show the chooser.
    public static func plan(installer: UpdateInstaller, for update: AppUpdate) -> UpdateHandoff {
        guard let url = installer.handoffURL(for: update) else { return .chooser }
        return .open(installer, url)
    }
}

/// When to check and when to prompt. Keys are Reborn's: `AutomaticUpdateChecks`
/// (default on) and the internal `UpdateLastCheck` / `UpdateSkippedVersion`.
/// `Phoebus.updateInstaller` is Phoebus's own.
public enum AppUpdatePolicy {
    public static let interval: TimeInterval = 24 * 60 * 60

    public static let installer = SettingsStore<UpdateInstaller>(key: "Phoebus.updateInstaller") { .askEveryTime }

    public static let automaticChecks = DefaultsKey<Bool>("AutomaticUpdateChecks", default: true)
    private static let lastCheckKey = "UpdateLastCheck"
    private static let skippedKey = "UpdateSkippedVersion"

    /// Once a day. A last check in the future (clock change) counts as due,
    /// and a restored backup can leave any type in the key, so only a date counts.
    public static func isDue(lastCheck: Date?, now: Date = Date()) -> Bool {
        guard let lastCheck else { return true }
        let elapsed = now.timeIntervalSince(lastCheck)
        return elapsed < 0 || elapsed >= interval
    }

    /// "Skip this version" skips one build: versions repeat across nightlies.
    public static func shouldPrompt(for update: AppUpdate, skippedBuild: String?) -> Bool {
        skippedBuild != String(update.build)
    }

    public static func lastCheck(in defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: lastCheckKey) as? Date
    }

    public static func recordCheck(at date: Date = Date(), in defaults: UserDefaults = .standard) {
        defaults.set(date, forKey: lastCheckKey)
    }

    /// Forgets the check so the next foreground tries again.
    public static func clearLastCheck(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: lastCheckKey)
    }

    public static func skippedBuild(in defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: skippedKey)
    }

    public static func skip(_ update: AppUpdate, in defaults: UserDefaults = .standard) {
        defaults.set(String(update.build), forKey: skippedKey)
    }
}
