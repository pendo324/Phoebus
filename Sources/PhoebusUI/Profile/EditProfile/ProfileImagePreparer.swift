import SwiftUI
import PhoebusCore

/// A picked photo cropped, scaled and encoded for the banner's `upload_sr_img`.
struct PreparedProfileImage {
    let jpeg: Data
    let preview: UIImage
}

enum ProfileImagePreparer {
    /// Fills the banner frame (`ProfileImageSpec`) from the photo's centre and
    /// encodes the best JPEG within Reddit's size limit; nil when the photo
    /// can't be read or no quality fits.
    static func prepareBanner(_ data: Data) -> PreparedProfileImage? {
        guard let source = UIImage(data: data), source.size.width > 1, source.size.height > 1 else { return nil }
        let target = ProfileImageSpec.bannerSize(sourceWidth: Int((source.size.width * source.scale).rounded()))
        let fill = ProfileImageSpec.fillRect(sourceWidth: Double(source.size.width), sourceHeight: Double(source.size.height),
                                             target: target)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        // JPEG has no alpha; a transparent photo lands on white rather than black.
        format.opaque = true
        let size = CGSize(width: target.width, height: target.height)
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            source.draw(in: CGRect(x: fill.x, y: fill.y, width: fill.width, height: fill.height))
        }
        for quality in ProfileImageSpec.jpegQualities {
            if let jpeg = rendered.jpegData(compressionQuality: quality), jpeg.count <= ProfileImageSpec.maxBytes {
                return PreparedProfileImage(jpeg: jpeg, preview: rendered)
            }
        }
        return nil
    }
}
