import Foundation
import PhoebusCore
#if canImport(Photos)
import Photos
#endif

/// Bulk "Save All" for a multi-image album.
///
/// Downloads every original first, then commits them to the photo library
/// in one `performChanges` block, so a failed download never leaves a
/// partial album in Photos.
public enum AlbumImageSaver {
    public enum SaveError: LocalizedError {
        case notEnoughSpace
        case accessDenied
        case downloadFailed

        public var errorDescription: String? {
            switch self {
            // Reborn's toast wording.
            case .notEnoughSpace: return "Not enough free space"
            case .accessDenied: return "Photos access denied"
            case .downloadFailed: return "Save failed"
            }
        }
    }

    #if canImport(Photos)
    /// Downloads and saves every URL, reporting the saved count.
    public static func saveAll(
        urls: [URL],
        useApolloAlbum: Bool,
        session: URLSession = .shared
    ) async throws -> Int {
        guard !urls.isEmpty else { return 0 }

        guard await PhotoAlbumSaver.requestAccess() else { throw SaveError.accessDenied }

        // Checked before downloading anything, so the guard actually avoids
        // filling the disk.
        if urls.count > 1, !hasCapacity(for: urls.count) {
            throw SaveError.notEnoughSpace
        }

        // Downloaded concurrently but committed together, so a failure
        // partway leaves nothing in Photos.
        var payloads: [Data] = []
        try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    var request = URLRequest(url: url, timeoutInterval: 60)
                    request.httpShouldHandleCookies = false
                    let (data, response) = try await session.data(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                          !data.isEmpty else { throw SaveError.downloadFailed }
                    // Reborn's per-item ceiling, enforced on the real body rather than a
                    // trusted Content-Length.
                    guard UInt64(data.count) <= AlbumSaveCapacity.maximumItemBytes else {
                        throw SaveError.downloadFailed
                    }
                    return (index, data)
                }
            }
            var collected: [(Int, Data)] = []
            for try await pair in group { collected.append(pair) }
            // Restored to the album's own order, which concurrency
            // otherwise scrambles.
            payloads = collected.sorted { $0.0 < $1.0 }.map(\.1)
        }

        for payload in payloads {
            try await PhotoAlbumSaver.save(.imageData(payload), useApolloAlbum: useApolloAlbum)
        }
        return payloads.count
    }

    /// Whether the volume can take `count` more originals.
    ///
    /// A volume whose capacity cannot be read returns true: an unreadable
    /// volume is not evidence of a full one.
    private static func hasCapacity(for count: Int) -> Bool {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
        guard let values = try? url.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage else {
            return true
        }
        return AlbumSaveCapacity.hasCapacity(
            availableBytes: UInt64(max(0, available)),
            storedBytes: 0,
            remainingCount: count)
    }
    #endif
}
