import Foundation

/// Apollo's "Is Apollo Still Taking up Storage?" explainer. Every string
/// matches Apollo's copy verbatim, including the ➔ arrows, the curly
/// apostrophes, and the parenthetical between the two halves of the sentence.
///
/// iOS reports the app's storage as larger than its own cache because
/// WKWebView's website data is counted against the app but is not the app's
/// to clear. The screen explains where the space went and lists its own folder
/// sizes.
public enum CacheExplainer {
    /// Screen title.
    public static let title = "Is Phoebus Still Taking up Storage?"

    /// First paragraph.
    public static let introduction =
        "If you\u{2019}ve done the normal \u{201C}Clear Cache\u{201D} action in Phoebus, and the iOS Settings app still says Phoebus is taking up a decent amount of storage, that\u{2019}s likely cached data iOS builds up while web browsing within Phoebus. Easy to fix!"

    /// Second paragraph, reassembled from its three fragments. The arrows are U+2794.
    public static let instructions =
        "Go to iOS Settings app \u{2794} Safari \u{2794} Advanced \u{2794} Website Data \u{2794} Remove All Website Data (note: this will clear all open tabs). Approximately 15 minutes later the iOS Storage screen should update to state Phoebus (and other apps with in-app browsers) are using less storage now."

    /// Third paragraph, introducing the folder listing.
    public static let listingIntroduction =
        "Outside of iOS website data, here is the complete listing/size of Phoebus\u{2019}s app folder (let me know if anything seems too large):"

    /// One directory in the listing.
    public struct Entry: Sendable, Equatable, Identifiable {
        public let name: String
        public let byteCount: Int64
        public var id: String { name }

        public init(name: String, byteCount: Int64) {
            self.name = name
            self.byteCount = byteCount
        }

        /// `Documents — 12.4 MB`, aligned by the caller.
        public var formattedSize: String {
            ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
        }
    }

    /// Measures the app container's top-level directories, largest first, since
    /// the copy invites the user to spot anything "too large".
    public static func folderListing(
        containerURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> [Entry] {
        let root = containerURL ?? URL(fileURLWithPath: NSHomeDirectory())
        guard let children = try? fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        return children.compactMap { url -> Entry? in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory
            guard isDirectory == true else { return nil }
            return Entry(name: url.lastPathComponent, byteCount: size(of: url, fileManager: fileManager))
        }
        .sorted { $0.byteCount > $1.byteCount }
    }

    /// Recursive size of a directory, using allocated size since that is what
    /// the iOS Storage screen reports.
    static func size(of directory: URL, fileManager: FileManager = .default) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(
                forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            let bytes = values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0
            total += Int64(bytes)
        }
        return total
    }
}
