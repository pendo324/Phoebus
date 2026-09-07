import Foundation
import AVFoundation
import PhoebusCore
#if canImport(Photos)
import Photos
#endif

/// Performs the "Download Video…" post action: fetches Reddit's separate DASH
/// video and audio tracks, muxes them into one file, and saves it to the photo
/// library.
///
/// Reddit serves v.redd.it audio separately, so downloading only the video URL
/// produces a silent clip. Reborn's gallery export composes the two tracks with
/// `AVMutableComposition` for the same reason.
public enum VideoDownloadService {
    public static func downloadAndSave(videoURL: URL) async throws {
        #if canImport(Photos)
        guard await requestPhotosAccess() else {
            throw VideoDownloader.DownloadError.photosAccessDenied
        }
        #endif

        let temporaryDirectory = FileManager.default.temporaryDirectory
        let videoFile = temporaryDirectory.appendingPathComponent("apollo-video-\(UUID().uuidString).mp4")
        let (downloadedVideo, _) = try await URLSession.shared.download(from: videoURL)
        try? FileManager.default.removeItem(at: videoFile)
        try FileManager.default.moveItem(at: downloadedVideo, to: videoFile)
        defer { try? FileManager.default.removeItem(at: videoFile) }

        var fileToSave = videoFile

        // Try to pair the separate audio track; a video with no audio
        // stream (common for silent v.redd.it clips) just saves as-is.
        if let audioURL = await VideoDownloader.resolveAudioURL(forRedditVideo: videoURL),
           let muxed = try? await mux(videoFile: videoFile, audioURL: audioURL, in: temporaryDirectory) {
            fileToSave = muxed
        }
        defer { if fileToSave != videoFile { try? FileManager.default.removeItem(at: fileToSave) } }

        #if canImport(Photos)
        // `SaveToApolloAlbum` ("Save to \"Apollo\" Album").
        try await PhotoAlbumSaver.save(.video(fileToSave), useApolloAlbum: GeneralSettingsStore.load().saveToApolloAlbum)
        #endif
    }

    private static func mux(videoFile: URL, audioURL: URL, in directory: URL) async throws -> URL? {
        let audioFile = directory.appendingPathComponent("apollo-audio-\(UUID().uuidString).mp4")
        let (downloadedAudio, response) = try await URLSession.shared.download(from: audioURL)
        // Reddit returns an XML error document rather than a 404 for
        // posts that genuinely have no audio track.
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            try? FileManager.default.removeItem(at: downloadedAudio)
            return nil
        }
        try? FileManager.default.removeItem(at: audioFile)
        try FileManager.default.moveItem(at: downloadedAudio, to: audioFile)
        defer { try? FileManager.default.removeItem(at: audioFile) }

        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: videoFile)
        let audioAsset = AVURLAsset(url: audioFile)

        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
              let compositionVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return nil
        }
        let duration = try await videoAsset.load(.duration)
        let range = CMTimeRange(start: .zero, duration: duration)
        try compositionVideo.insertTimeRange(range, of: videoTrack, at: .zero)
        compositionVideo.preferredTransform = try await videoTrack.load(.preferredTransform)

        if let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first,
           let compositionAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let audioDuration = try await audioAsset.load(.duration)
            let audioRange = CMTimeRange(start: .zero, duration: min(duration, audioDuration))
            try? compositionAudio.insertTimeRange(audioRange, of: audioTrack, at: .zero)
        }

        let outputURL = directory.appendingPathComponent("apollo-muxed-\(UUID().uuidString).mp4")
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            return nil
        }
        export.outputURL = outputURL
        export.outputFileType = .mp4
        await export.export()
        guard export.status == .completed else {
            throw VideoDownloader.DownloadError.exportFailed
        }
        return outputURL
    }

    #if canImport(Photos)
    private static func requestPhotosAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status == .authorized || status == .limited)
            }
        }
    }
    #endif
}
