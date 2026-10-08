import Foundation

/// How a picked photo is prepared for the profile banner: 10:3 between 640 and
/// 1280pt wide (Reddit's own 1280x384), as JPEG within `upload_sr_img`'s 500 KiB
/// file limit. The banner is the user subreddit's `banner`; the avatar is
/// changed on reddit.com.
public enum ProfileImageSpec {
    public static let maxBytes = 500 * 1024
    public static let bannerWidths = 640...1280
    /// Banner height as a fraction of its width.
    public static let bannerHeightRatio = 0.3
    /// JPEG qualities to try, best first, until the file fits `maxBytes`.
    public static let jpegQualities: [Double] = [0.9, 0.8, 0.7, 0.6, 0.5, 0.4]

    public struct Size: Sendable, Equatable {
        public let width: Int
        public let height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }
    }

    public struct Rect: Sendable, Equatable {
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    /// The pixel size to upload for a banner from a source of the given width.
    public static func bannerSize(sourceWidth: Int) -> Size {
        let width = min(max(sourceWidth, bannerWidths.lowerBound), bannerWidths.upperBound)
        return Size(width: width, height: Int((Double(width) * bannerHeightRatio).rounded()))
    }

    /// Where to draw the whole source so it fills the target, cropping the
    /// overflow evenly from both sides.
    public static func fillRect(sourceWidth: Double, sourceHeight: Double, target: Size) -> Rect {
        let scale = max(Double(target.width) / sourceWidth, Double(target.height) / sourceHeight)
        let width = sourceWidth * scale, height = sourceHeight * scale
        return Rect(x: (Double(target.width) - width) / 2, y: (Double(target.height) - height) / 2,
                    width: width, height: height)
    }
}

/// `upload_sr_img` answers 200 either way: `{"errors": [], "img_src": "…"}`
/// on success, or `{"errors": ["IMAGE_ERROR"], "errors_values": ["…"]}`.
public enum ProfileImageUploadResponse {
    public struct Rejected: Error, LocalizedError, Equatable, Sendable {
        public let message: String
        public var errorDescription: String? { message }
    }

    public static func throwIfRejected(_ data: Data) throws {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errors = root["errors"] as? [Any], let first = errors.first else {
            try PostedCommentResponse.throwIfRejected(data)
            return
        }
        let detail = (root["errors_values"] as? [Any])?.first as? String
        let code = (first as? String) ?? (first as? [Any]).flatMap { $0.first.map { "\($0)" } } ?? "error"
        let said = CommentSubmitFailure.sentence(detail ?? code)
        throw Rejected(message: said.isEmpty ? "Reddit didn't accept this image." : said)
    }
}
