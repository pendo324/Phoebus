import Foundation
import AVFoundation
import CoreImage
import PhoebusCore
#if canImport(UIKit)
import UIKit
import SwiftUI
#endif

/// Reborn's "Share as Video" (#380): when a video post's Share-as-Image card
/// has the Share as Video toggle on, exports an MP4 with the rendered card as a
/// static backdrop and the post's video composited into the media region.
///
/// The v.redd.it DASH video and audio are muxed with `AVMutableComposition`
/// through `VideoDownloadService`'s pairing, and a custom `AVVideoCompositing`
/// draws the card then the video frame into a caller-supplied normalized rect
/// (where the card's image placeholder sits).
public enum ShareVideoExportService {
    public enum ExportError: LocalizedError {
        case noVideoTrack
        case exportFailed
        case unsupportedURL

        public var errorDescription: String? {
            switch self {
            case .noVideoTrack: return "This post has no video to include."
            case .exportFailed: return "Couldn't export the video."
            case .unsupportedURL: return "This post's video couldn't be downloaded."
            }
        }
    }

    /// Caps the export length so a long v.redd.it post doesn't produce a
    /// minutes-long file.
    public static let maxSeconds: TimeInterval = 180

    /// - Parameters:
    ///   - videoURL: the post's v.redd.it (or direct .mp4) video URL.
    ///   - cardImage: the already-rendered Share-as-Image card, exactly as the
    ///     user configured its toggles.
    ///   - mediaRect: normalized (0...1) rect within the card where the video is
    ///     composited, matching where the card's own image placeholder is drawn.
    #if canImport(UIKit)
    public static func export(videoURL: URL, cardImage: UIImage, mediaRect: CGRect) async throws -> URL {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let videoFile = temporaryDirectory.appendingPathComponent("apollo-sharevideo-src-\(UUID().uuidString).mp4")
        let (downloaded, _) = try await URLSession.shared.download(from: videoURL)
        try? FileManager.default.removeItem(at: videoFile)
        try FileManager.default.moveItem(at: downloaded, to: videoFile)
        defer { try? FileManager.default.removeItem(at: videoFile) }

        // Same DASH audio pairing as "Download Video…": a v.redd.it clip's video
        // and audio are separate assets.
        let sourceForComposition = videoFile
        var audioFile: URL?
        if let audioURL = await VideoDownloader.resolveAudioURL(forRedditVideo: videoURL) {
            let candidate = temporaryDirectory.appendingPathComponent("apollo-sharevideo-audio-\(UUID().uuidString).mp4")
            if let (downloadedAudio, response) = try? await URLSession.shared.download(from: audioURL),
               let http = response as? HTTPURLResponse, http.statusCode == 200 {
                try? FileManager.default.removeItem(at: candidate)
                try? FileManager.default.moveItem(at: downloadedAudio, to: candidate)
                audioFile = candidate
            }
        }
        defer { if let audioFile { try? FileManager.default.removeItem(at: audioFile) } }

        let asset = AVURLAsset(url: sourceForComposition)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExportError.noVideoTrack
        }
        let naturalDuration = try await asset.load(.duration)
        let duration = min(naturalDuration, CMTime(seconds: maxSeconds, preferredTimescale: 600))

        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ExportError.exportFailed
        }
        try compVideo.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: videoTrack, at: .zero)
        compVideo.preferredTransform = try await videoTrack.load(.preferredTransform)

        if let audioFile {
            let audioAsset = AVURLAsset(url: audioFile)
            if let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first,
               let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                let audioDuration = try await audioAsset.load(.duration)
                let range = CMTimeRange(start: .zero, duration: min(duration, audioDuration))
                try? compAudio.insertTimeRange(range, of: audioTrack, at: .zero)
            }
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let renderSize = naturalSize.applying(transform)
        let cardSize = CGSize(width: abs(renderSize.width), height: abs(renderSize.height))

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = cardSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.customVideoCompositorClass = CardBackdropCompositor.self

        let instruction = CardBackdropInstruction(
            timeRange: CMTimeRange(start: .zero, duration: duration),
            cardImage: cardImage,
            mediaRect: mediaRect,
            videoTrackID: compVideo.trackID
        )
        videoComposition.instructions = [instruction]

        let outputURL = temporaryDirectory.appendingPathComponent("apollo-sharevideo-\(UUID().uuidString).mp4")
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.exportFailed
        }
        export.videoComposition = videoComposition
        export.outputURL = outputURL
        export.outputFileType = .mp4
        await export.export()
        guard export.status == .completed else {
            throw ExportError.exportFailed
        }
        return outputURL
    }
    #endif
}

#if canImport(UIKit)
/// One-instruction `AVVideoCompositionInstructionProtocol`: draws the static
/// card image full-frame, then the source video frame aspect-filled into
/// `mediaRect` on top.
final class CardBackdropInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    let cardImage: UIImage
    let mediaRect: CGRect
    let videoTrackID: CMPersistentTrackID

    init(timeRange: CMTimeRange, cardImage: UIImage, mediaRect: CGRect, videoTrackID: CMPersistentTrackID) {
        self.timeRange = timeRange
        self.cardImage = cardImage
        self.mediaRect = mediaRect
        self.videoTrackID = videoTrackID
        self.requiredSourceTrackIDs = [NSNumber(value: videoTrackID)]
    }
}

final class CardBackdropCompositor: NSObject, AVVideoCompositing {
    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]

    private let context = CIContext()

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? CardBackdropInstruction,
              let sourceBuffer = request.sourceFrame(byTrackID: instruction.videoTrackID),
              let outputBuffer = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "ApolloShareVideo", code: -1))
            return
        }

        let renderSize = request.renderContext.size
        let cardCI = CIImage(image: instruction.cardImage) ?? CIImage.empty()
        let cardScaleX = renderSize.width / max(cardCI.extent.width, 1)
        let cardScaleY = renderSize.height / max(cardCI.extent.height, 1)
        let scaledCard = cardCI.transformed(by: CGAffineTransform(scaleX: cardScaleX, y: cardScaleY))

        var videoCI = CIImage(cvPixelBuffer: sourceBuffer)
        // Aspect-fill the source video into the media rect (render-space pixels).
        let rect = CGRect(
            x: instruction.mediaRect.minX * renderSize.width,
            y: (1 - instruction.mediaRect.maxY) * renderSize.height,
            width: instruction.mediaRect.width * renderSize.width,
            height: instruction.mediaRect.height * renderSize.height
        )
        let videoExtent = videoCI.extent
        if videoExtent.width > 0, videoExtent.height > 0, rect.width > 0, rect.height > 0 {
            let scale = max(rect.width / videoExtent.width, rect.height / videoExtent.height)
            videoCI = videoCI.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let scaledExtent = videoCI.extent
            let dx = rect.minX - (scaledExtent.width - rect.width) / 2
            let dy = rect.minY - (scaledExtent.height - rect.height) / 2
            videoCI = videoCI.transformed(by: CGAffineTransform(translationX: dx, y: dy)).cropped(to: rect)
        }

        let composited = videoCI.composited(over: scaledCard)
        context.render(composited, to: outputBuffer)
        request.finish(withComposedVideoFrame: outputBuffer)
    }
}

/// Presents the exported MP4 in a standard share sheet.
public struct ActivityShareSheet: UIViewControllerRepresentable {
    public let items: [Any]
    /// Called with whether the share COMPLETED (as opposed to being
    /// cancelled). Share as Image needs the distinction: a completed
    /// share dismisses the preview sheet, a cancelled one leaves it up
    /// so the options can be adjusted and retried.
    public let onFinish: ((Bool) -> Void)?

    public init(items: [Any], onFinish: ((Bool) -> Void)? = nil) {
        self.items = items
        self.onFinish = onFinish
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        CrashRecorder.record(.presentedShareSheet)
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let onFinish {
            controller.completionWithItemsHandler = { _, completed, _, _ in
                onFinish(completed)
            }
        }
        return controller
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
