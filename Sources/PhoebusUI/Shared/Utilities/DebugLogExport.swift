import Foundation
import PhoebusCore
#if canImport(OSLog)
import OSLog
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Builds the "Export Debug Logs" file: the build and OS, this session's
/// Apollo AI log, and the last hour of this process's own log messages.
/// Nothing about accounts beyond how many there are.
enum DebugLogExport {
    static func write(accountCount: Int) async -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Phoebus-DebugLogs.txt")
        let info = Bundle.main.infoDictionary ?? [:]
        var lines = [
            "Phoebus \(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))",
            "Exported \(ISO8601DateFormatter().string(from: Date()))",
        ]
        #if canImport(UIKit)
        let device = await MainActor.run { "\(UIDevice.current.model), \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)" }
        lines.append(device)
        #endif
        lines.append("Accounts: \(accountCount)")
        let ai = ApolloAILog.entries
        if !ai.isEmpty {
            lines.append("")
            lines.append("== Phoebus AI (this session) ==")
            lines += ai
        }
        let system = await Task.detached(priority: .utility) { recentProcessLog() }.value
        lines.append("")
        lines.append("== Process log (last hour) ==")
        lines += system.isEmpty ? ["(none available)"] : system
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// The app's own log messages from the last hour, newest 2,000. Only
    /// its own subsystem: reading every framework's messages is very slow.
    private static func recentProcessLog() -> [String] {
        #if canImport(OSLog)
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier),
              let entries = try? store.getEntries(
                at: store.position(date: Date().addingTimeInterval(-3600)),
                matching: NSPredicate(format: "subsystem == %@", "com.pendo324.Phoebus"))
        else { return [] }
        let formatter = ISO8601DateFormatter()
        return entries.compactMap { $0 as? OSLogEntryLog }
            .suffix(2000)
            .map { "\(formatter.string(from: $0.date)) [\($0.category)] \($0.composedMessage)" }
        #else
        return []
        #endif
    }
}
