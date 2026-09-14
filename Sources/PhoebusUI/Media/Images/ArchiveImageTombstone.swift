import SwiftUI
import PhoebusCore
#if canImport(Vision)
import Vision
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Reborn's "image removed" check for archived media.
///
/// Some hosts answer a deleted image with a successful response whose
/// picture is a removal notice. Only the notice's own wording is trusted,
/// never the post's status. OCR is expensive, so a 32x32 sample first
/// rejects anything that is not a mostly dark, mostly grey frame (dark >
/// 512 of 1024 pixels, near-monochrome > 970).
enum ArchiveImageTombstone {
    #if canImport(UIKit)
    nonisolated(unsafe) private static let cache = NSCache<NSURL, NSNumber>()  // NSCache is thread-safe

    /// Pure prefilter, exposed for the smoke test's source check.
    static func looksLikeNotice(darkPixels: Int, monochromePixels: Int) -> Bool {
        darkPixels > 512 && monochromePixels > 970
    }

    /// Matches the removal notice's wording.
    static func textIsNotice(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("looking for") && lower.contains("image") && lower.contains("probably deleted")
    }

    static func isTombstone(_ image: UIImage, url: URL) async -> Bool {
        if let hit = cache.object(forKey: url as NSURL) { return hit.boolValue }
        let result = await Task.detached(priority: .utility) { () -> Bool in
            guard let cg = image.cgImage else { return false }
            var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
            let space = CGColorSpaceCreateDeviceRGB()
            var dark = 0, mono = 0
            pixels.withUnsafeMutableBytes { buffer in
                guard let ctx = CGContext(data: buffer.baseAddress, width: 32, height: 32, bitsPerComponent: 8,
                                          bytesPerRow: 32 * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 32, height: 32))
            }
            for i in 0..<(32 * 32) {
                let r = Int(pixels[i * 4]), g = Int(pixels[i * 4 + 1]), b = Int(pixels[i * 4 + 2])
                if max(r, g, b) < 60 { dark += 1 }
                if max(r, g, b) - min(r, g, b) < 15 { mono += 1 }
            }
            guard looksLikeNotice(darkPixels: dark, monochromePixels: mono) else { return false }
            #if canImport(Vision)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            guard (try? handler.perform([request])) != nil else { return false }
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            return textIsNotice(text)
            #else
            return false
            #endif
        }.value
        cache.setObject(NSNumber(value: result), forKey: url as NSURL)
        return result
    }
    #endif
}

/// One archived media page: loads the image, then swaps it for an "Image
/// unavailable" notice when the host sent back a removal card.
struct ArchivedImagePage: View {
    let url: URL
    #if canImport(UIKit)
    @State private var image: UIImage?
    #endif
    @State private var unavailable = false
    @State private var failed = false

    var body: some View {
        ZStack {
            #if canImport(UIKit)
            if unavailable || failed {
                VStack(spacing: 3) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 22))
                        .padding(.bottom, 3)
                    Text("Image unavailable").font(.system(size: 15, weight: .medium))
                    Text("The original image is no longer available.")
                        .font(.system(size: 13))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Image unavailable. The original image is no longer available.")
            } else if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView()
            }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) { await load() }
    }

    private func load() async {
        #if canImport(UIKit)
        guard image == nil, !unavailable else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: ImgurClient.proxiedImageURL(for: url))
            guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                  let decoded = UIImage(data: data) else { failed = true; return }
            if await ArchiveImageTombstone.isTombstone(decoded, url: url) {
                unavailable = true
            } else {
                image = decoded
            }
        } catch {
            failed = true
        }
        #endif
    }
}
