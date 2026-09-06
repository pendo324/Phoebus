import Foundation

/// Local crash reports, as Apollo-Reborn records them: KSCrash writes a raw
/// report on a crash, and nothing leaves the raw form except through this
/// allowlist. Only the fields below are ever shown, exported or shared;
/// free-form text (exception reasons, thread and queue names, registers,
/// memory) never is.
public enum CrashReportSanitizer {
    static let maxJSONBytes = 1024 * 1024
    static let maxThreads = 128
    static let maxFramesCrashedThread = 256
    static let maxFramesOtherThread = 64
    static let maxFramesOtherThreadTight = 16
    static let maxBinaryImages = 512
    static let maxRecentActions = 20

    static let crashCategories: Set<String> = [
        "signal", "mach", "nsexception", "cpp_exception", "memory_termination", "deadlock", "user",
    ]

    /// Foundation's own exception names; a custom name is app text and is
    /// left out rather than redacted.
    static let systemExceptionNames: Set<String> = [
        "NSGenericException", "NSRangeException", "NSInvalidArgumentException",
        "NSInternalInconsistencyException", "NSMallocException", "NSObjectInaccessibleException",
        "NSObjectNotAvailableException", "NSDestinationInvalidException", "NSPortTimeoutException",
        "NSInvalidSendPortException", "NSInvalidReceivePortException", "NSPortSendException",
        "NSPortReceiveException", "NSOldStyleException",
    ]

    // MARK: Field helpers

    private static func hex(_ value: Any?) -> Any {
        guard let number = value as? NSNumber else { return NSNull() }
        return String(format: "0x%016llx", number.uint64Value)
    }

    private static func number(_ value: Any?) -> Any { (value as? NSNumber) ?? NSNull() }
    private static func string(_ value: Any?) -> String? { value as? String }
    private static func dict(_ value: Any?) -> [String: Any]? { value as? [String: Any] }
    private static func array(_ value: Any?) -> [Any] { (value as? [Any]) ?? [] }
    private static func isTrue(_ value: Any?) -> Bool { (value as? NSNumber)?.boolValue ?? false }
    private static func lastPathComponent(_ value: Any?) -> Any {
        guard let path = value as? String else { return NSNull() }
        return (path as NSString).lastPathComponent
    }

    /// KSCrash's store gives `report.timestamp` as epoch microseconds; a
    /// fixed report has an RFC 3339 string. Both become ISO 8601 UTC.
    static func iso8601Timestamp(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        guard let microseconds = value as? NSNumber else { return nil }
        let date = Date(timeIntervalSince1970: microseconds.doubleValue / 1e6)
        return ISO8601DateFormatter().string(from: date)
    }

    // MARK: Sections

    static func crashSection(_ raw: [String: Any]) -> [String: Any] {
        let crash = dict(raw["crash"]) ?? [:]
        let error = dict(crash["error"]) ?? [:]
        var out: [String: Any] = [:]
        out["timestamp"] = iso8601Timestamp(dict(raw["report"])?["timestamp"]) ?? NSNull()
        let category = string(error["type"]) ?? ""
        out["category"] = crashCategories.contains(category) ? category : "unknown"
        out["address"] = hex(error["address"])
        if let name = string(dict(error["nsexception"])?["name"]), systemExceptionNames.contains(name) {
            out["exception_name"] = name
        }
        if let signal = dict(error["signal"]) {
            out["signal"] = ["code": number(signal["code"])]
        }
        if let mach = dict(error["mach"]) {
            out["mach_exception"] = [
                "exception": number(mach["exception"]),
                "code": number(mach["code"]),
                "subcode": number(mach["subcode"]),
            ]
        }
        if let memory = dict(error["memory_termination"]) {
            var section: [String: Any] = [:]
            for key in ["memory_footprint", "memory_limit", "memory_remaining"] { section[key] = number(memory[key]) }
            out["memory_termination"] = section
        }
        return out
    }

    static func environmentSection(_ raw: [String: Any]) -> [String: Any] {
        let system = dict(raw["system"]) ?? [:]
        let info = dict(dict(raw["user"])?["phoebus"]) ?? [:]
        return [
            "phoebus_version": string(info["version"]) ?? "unknown",
            "phoebus_build": string(info["build"]) ?? "unknown",
            "diagnostic_schema": (info["diagnostic_schema"] as? NSNumber) ?? 1,
            "ios_version": string(system["system_version"]) ?? NSNull(),
            "os_build": string(system["os_version"]) ?? NSNull(),
            "device_model": string(system["machine"]) ?? NSNull(),
            "architecture": string(system["cpu_arch"]) ?? NSNull(),
        ]
    }

    /// Addresses and image/symbol names only.
    static func frame(_ frame: [String: Any]) -> [String: Any] {
        [
            "instruction_address": hex(frame["instruction_addr"]),
            "object_address": hex(frame["object_addr"]),
            "object_name": lastPathComponent(frame["object_name"]),
            "symbol_address": hex(frame["symbol_addr"]),
            "symbol_name": string(frame["symbol_name"]) ?? NSNull(),
        ]
    }

    static func threadsSection(_ raw: [String: Any], maxOtherFrames: Int, includeAllThreads: Bool,
                               truncated: inout Bool) -> [[String: Any]] {
        var out: [[String: Any]] = []
        for case let thread as [String: Any] in array(dict(raw["crash"])?["threads"]) {
            let crashed = isTrue(thread["crashed"])
            if !crashed && !includeAllThreads { continue }
            if out.count >= maxThreads { truncated = true; break }
            let backtraceInfo = dict(thread["backtrace"]) ?? [:]
            let maxFrames = crashed ? maxFramesCrashedThread : maxOtherFrames
            var backtrace: [[String: Any]] = []
            for case let entry as [String: Any] in array(backtraceInfo["contents"]) {
                if backtrace.count >= maxFrames { truncated = true; break }
                backtrace.append(frame(entry))
            }
            var outThread: [String: Any] = [
                "index": (thread["index"] as? NSNumber) ?? NSNumber(value: out.count),
                "crashed": crashed,
                "current": isTrue(thread["current_thread"]),
                "backtrace": backtrace,
            ]
            if let skipped = backtraceInfo["skipped"] as? NSNumber, skipped.intValue > 0 {
                outThread["frames_skipped"] = skipped
            }
            out.append(outThread)
        }
        return out
    }

    /// Images the kept frames reference come first, so the cap never cuts
    /// a UUID needed to symbolicate them.
    static func imagesSection(_ raw: [String: Any], threads: [[String: Any]], truncated: inout Bool) -> [[String: Any]] {
        var referenced = Set<String>()
        for thread in threads {
            for case let frame as [String: Any] in array(thread["backtrace"]) {
                if let name = frame["object_name"] as? String { referenced.insert(name) }
            }
        }
        var first: [[String: Any]] = []
        var rest: [[String: Any]] = []
        for case let image as [String: Any] in array(raw["binary_images"]) {
            let name = (image["name"] as? String).map { ($0 as NSString).lastPathComponent }
            let outImage: [String: Any] = [
                "name": name ?? NSNull(),
                "load_address": hex(image["image_addr"]),
                "size": number(image["image_size"]),
                "uuid": string(image["uuid"]) ?? NSNull(),
                "cpu_type": number(image["cpu_type"]),
                "cpu_subtype": number(image["cpu_subtype"]),
            ]
            if let name, referenced.contains(name) { first.append(outImage) } else { rest.append(outImage) }
        }
        var out = first
        for image in rest {
            if out.count >= maxBinaryImages { truncated = true; break }
            out.append(image)
        }
        if out.count > maxBinaryImages {
            truncated = true
            out = Array(out.prefix(maxBinaryImages))
        }
        return out
    }

    static func recentActions(_ raw: [String: Any]) -> [[String: Any]] {
        var out: [[String: Any]] = []
        for case let action as [String: Any] in array(dict(dict(raw["user"])?["phoebus"])?["recent_actions"]) {
            if out.count >= maxRecentActions { break }
            guard let event = action["event"] as? String, CrashContextEvent(rawValue: event) != nil else { continue }
            out.append(["event": event, "age_seconds": number(action["age_seconds"])])
        }
        return out
    }

    // MARK: Assembly

    /// The allowlisted report, or nil when `raw` isn't a crash report.
    public static func sanitized(_ raw: [String: Any]) -> [String: Any]? {
        guard dict(raw["crash"]) != nil else { return nil }
        var truncated = false
        var threads = threadsSection(raw, maxOtherFrames: maxFramesOtherThread, includeAllThreads: true, truncated: &truncated)
        var report = assemble(raw, threads: threads, truncated: truncated)
        // Size backstop: shrink the other threads, then drop them.
        if encodedLength(report) > maxJSONBytes {
            threads = threadsSection(raw, maxOtherFrames: maxFramesOtherThreadTight, includeAllThreads: true, truncated: &truncated)
            report = assemble(raw, threads: threads, truncated: true)
        }
        if encodedLength(report) > maxJSONBytes {
            threads = threadsSection(raw, maxOtherFrames: 0, includeAllThreads: false, truncated: &truncated)
            report = assemble(raw, threads: threads, truncated: true)
        }
        return report
    }

    static func assemble(_ raw: [String: Any], threads: [[String: Any]], truncated: Bool) -> [String: Any] {
        var imagesTruncated = false
        let images = imagesSection(raw, threads: threads, truncated: &imagesTruncated)
        var out: [String: Any] = [
            "schema_version": 1,
            "report_type": "phoebus_crash",
            "crash": crashSection(raw),
            "environment": environmentSection(raw),
            "threads": threads,
            "binary_images": images,
            "recent_actions": recentActions(raw),
        ]
        if truncated || imagesTruncated { out["truncated"] = true }
        return out
    }

    static func encodedLength(_ report: [String: Any]) -> Int {
        guard JSONSerialization.isValidJSONObject(report),
              let data = try? JSONSerialization.data(withJSONObject: report) else { return .max }
        return data.count
    }

    // MARK: Presentation

    public static func jsonString(_ report: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(report),
              let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }

    /// The store's fixer writes six fractional digits, which
    /// `ISO8601DateFormatter` rejects, so the fraction is dropped.
    public static func crashDate(_ report: [String: Any]) -> Date? {
        guard var timestamp = dict(report["crash"])?["timestamp"] as? String else { return nil }
        if let dot = timestamp.firstIndex(of: "."), timestamp.hasSuffix("Z") {
            timestamp = String(timestamp[..<dot]) + "Z"
        }
        return ISO8601DateFormatter().date(from: timestamp)
    }

    public static func category(_ report: [String: Any]) -> String {
        (dict(report["crash"])?["category"] as? String) ?? "unknown"
    }

    public static func exceptionName(_ report: [String: Any]) -> String? {
        dict(report["crash"])?["exception_name"] as? String
    }

    public static func textSummary(_ report: [String: Any]) -> String {
        let crash = dict(report["crash"]) ?? [:]
        let environment = dict(report["environment"]) ?? [:]
        var lines = ["Phoebus crash report (sanitized)"]
        if let timestamp = crash["timestamp"] as? String { lines.append("Date: \(timestamp)") }
        let name = (crash["exception_name"] as? String).map { " (\($0))" } ?? ""
        lines.append("Type: \((crash["category"] as? String) ?? "unknown")\(name)")
        lines.append("Phoebus: \((environment["phoebus_version"] as? String) ?? "unknown") (\((environment["phoebus_build"] as? String) ?? "unknown"))")
        lines.append("iOS \((environment["ios_version"] as? String) ?? "?") on \((environment["device_model"] as? String) ?? "?")")
        lines.append("")
        for case let thread as [String: Any] in array(report["threads"]) where isTrue(thread["crashed"]) {
            lines.append("Crashed thread (index \(thread["index"] ?? "?")):")
            for (index, entry) in array(thread["backtrace"]).enumerated() {
                if index >= 16 { lines.append("  …"); break }
                guard let frame = entry as? [String: Any] else { continue }
                let symbol = (frame["symbol_name"] as? String).map { " (\($0))" } ?? ""
                let object = (frame["object_name"] as? String) ?? "?"
                let padded = object.padding(toLength: max(28, object.count), withPad: " ", startingAt: 0)
                lines.append(String(format: "  %2d ", index) + "\(padded) \((frame["instruction_address"] as? String) ?? "?")\(symbol)")
            }
            break
        }
        lines.append("")
        lines.append("Full allowlisted report: phoebus-crash.json (addresses + binary UUIDs; symbolicated offline).")
        return lines.joined(separator: "\n")
    }
}

/// The coarse actions a crash report may carry, as Reborn's
/// `ApolloCrashEvent`. Nothing about what was opened, only that it was.
public enum CrashContextEvent: String, CaseIterable, Sendable {
    case appBecameActive = "app_became_active"
    case appResignedActive = "app_resigned_active"
    case appEnteredBackground = "app_entered_background"
    case memoryWarning = "memory_warning"
    case openedFeed = "opened_feed"
    case openedPost = "opened_post"
    case openedComments = "opened_comments"
    case openedGallery = "opened_gallery"
    case openedMediaViewer = "opened_media_viewer"
    case startedVideo = "started_video"
    case openedProfile = "opened_profile"
    case openedSettings = "opened_settings"
    case openedComposer = "opened_composer"
    case presentedShareSheet = "presented_share_sheet"
    case changedCommentSort = "changed_comment_sort"
}

/// "Store Crash Reports Locally" (Reborn's `CrashCaptureEnabled`, default
/// on) and which reports the relaunch prompt has already offered.
public enum CrashCaptureSettings {
    public static let enabledKey = "CrashCaptureEnabled"
    public static let promptedReportIDsKey = "CrashPromptedReportIDs"

    /// Absent means on: capture is local only.
    public static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) == nil || defaults.bool(forKey: enabledKey)
    }
}
