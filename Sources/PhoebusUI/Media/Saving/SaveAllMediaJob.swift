import SwiftUI
import PhoebusCore
#if canImport(Photos)
import Photos
#endif

/// Reborn's "Save All Media" batch (#1048), shared by the fullscreen pager's
/// menu, the feed album long-press menu and the Hidden & Deleted archive.
///
/// One job runs app-wide (a second request gets "Already Saving Media").
/// Add-only Photos permission is decided before any download ("Photos Access
/// Required" on denial). Items save one at a time, in order. Images keep their
/// original bytes (a GIF stays animated) by being written as a file resource;
/// videos use the Download Video download-and-mux path. More than one item
/// shows a "Saving All Media" panel with an "N / M" counter, a determinate
/// ring and Cancel. The result reads "Saved All N Items!" or "Saved X of N
/// Items" with a cancelled/failed detail (`SaveAllMediaSummary`).
@MainActor
final class SaveAllMediaJob: ObservableObject {
    static let shared = SaveAllMediaJob()

    @Published private(set) var isRunning = false
    @Published private(set) var total = 0
    @Published private(set) var completed = 0
    @Published private(set) var stopping = false
    @Published var banner: SaveAllMediaSummary.Result?

    private var task: Task<Void, Never>?

    /// `gifFormat`: the batch's answer to Ask Each Time; nil follows the setting.
    func start(_ items: [MediaPagerItem], gifFormat: GIFSaveFormat? = nil) {
        guard !isRunning else {
            show(.init(title: "Already Saving Media", detail: "Wait for the current save to finish.", style: .info))
            return
        }
        guard !items.isEmpty else {
            show(.init(title: "No Media to Save", detail: nil, style: .info))
            return
        }
        isRunning = true
        total = items.count
        completed = 0
        stopping = false
        task = Task { await run(items, gifFormat: gifFormat) }
    }

    func cancel() {
        guard isRunning, !stopping else { return }
        stopping = true
        task?.cancel()
    }

    private func run(_ items: [MediaPagerItem], gifFormat: GIFSaveFormat?) async {
        defer { isRunning = false; task = nil }
        #if canImport(Photos)
        guard await PhotoAlbumSaver.requestAccess() else {
            show(.init(title: "Photos Access Required", detail: "Allow adding photos in Settings.", style: .error))
            return
        }
        let useAlbum = GeneralSettingsStore.load().saveToApolloAlbum
        var saved = 0, failed = 0
        for item in items {
            if Task.isCancelled { break }
            do {
                switch item {
                case .image(let url):
                    try await Self.saveOriginalImage(url, useApolloAlbum: useAlbum)
                case .video(let url):
                    try await VideoDownloadService.downloadAndSave(videoURL: url)
                case .gif(let url):
                    try await GIFSaveService.save(gifURL: url, format: gifFormat ?? GeneralSettingsStore.load().gifSaveFormat,
                                                  useApolloAlbum: useAlbum)
                }
                saved += 1
            } catch {
                // A cancelled download is a skip, not a failure.
                if Task.isCancelled { break }
                failed += 1
            }
            completed = saved + failed
        }
        show(SaveAllMediaSummary.result(total: items.count, saved: saved, failed: failed, cancelled: stopping))
        #endif
    }

    #if canImport(Photos)
    /// Downloads the original and hands Photos the exact bytes. A server
    /// error page or an empty body is never "saved".
    static func saveOriginalImage(_ url: URL, useApolloAlbum: Bool) async throws {
        var request = URLRequest(url: ImgurClient.proxiedImageURL(for: url), timeoutInterval: 60)
        request.httpShouldHandleCookies = false
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty,
              UInt64(data.count) <= AlbumSaveCapacity.maximumItemBytes else {
            throw AlbumImageSaver.SaveError.downloadFailed
        }
        try await PhotoAlbumSaver.save(.imageData(data), useApolloAlbum: useApolloAlbum)
    }
    #endif

    private func show(_ result: SaveAllMediaSummary.Result) {
        banner = result
        let shown = result
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if banner == shown { banner = nil }
        }
    }
}

extension View {
    /// Draws the shared job's progress panel and result banner over this view.
    /// Applied at the app root and inside the fullscreen pager, since a cover
    /// sits above the root.
    public func saveAllMediaOverlay() -> some View {
        modifier(SaveAllMediaOverlay())
    }
}

private struct SaveAllMediaOverlay: ViewModifier {
    @ObservedObject private var job = SaveAllMediaJob.shared

    func body(content: Content) -> some View {
        content
            .overlay {
                if job.isRunning && job.total > 1 {
                    ZStack {
                        Color.black.opacity(0.35).ignoresSafeArea()
                        panel
                    }
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .top) {
                if let banner = job.banner {
                    SaveAllMediaBanner(result: banner)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onTapGesture { job.banner = nil }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: job.isRunning)
            .animation(.easeInOut(duration: 0.2), value: job.banner)
    }

    /// A 300pt panel, headline title, counter, ring, and a 44pt
    /// Cancel that becomes "Stopping…".
    private var panel: some View {
        VStack(spacing: 16) {
            Text("Saving All Media").font(.headline)
            Text(SaveAllMediaSummary.counter(completed: job.completed, total: job.total))
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Media completed")
                .accessibilityValue("\(job.completed) of \(job.total)")
            HiddenContentProgressRing(progress: job.total > 0 ? Double(job.completed) / Double(job.total) : 0)
                .frame(width: 44, height: 44)
                .animation(.easeInOut(duration: 0.25), value: job.completed)
            Button {
                job.cancel()
            } label: {
                Text(job.stopping ? "Stopping…" : "Cancel")
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .disabled(job.stopping)
            .accessibilityIdentifier("saveAllMedia.cancel")
        }
        .padding(.top, 24).padding(.bottom, 12).padding(.horizontal, 24)
        .frame(maxWidth: 300)
        .background(RoundedRectangle(cornerRadius: 20).fill(.regularMaterial))
        .padding(.horizontal, 20)
    }
}

private struct SaveAllMediaBanner: View {
    let result: SaveAllMediaSummary.Result

    private var symbol: String {
        switch result.style {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.title3)
                .foregroundStyle(result.style == .error ? Color.red : (result.style == .success ? Color.green : Color.accentColor))
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title).font(.subheadline.weight(.semibold))
                if let detail = result.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Capsule().fill(.regularMaterial))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("saveAllMedia.banner")
    }
}
