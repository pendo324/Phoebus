import Foundation
import PhoebusCore
#if canImport(UIKit)
import UIKit
#endif

/// A picked image as bytes Reddit accepts, with its real type: JPEG, PNG
/// and GIF pass through; HEIC and WebP are re-encoded as JPEG.
func webSafeImage(_ data: Data) -> (data: Data, type: ImageFileType) {
    let type = ImageFileType(sniffing: data)
    guard !type.isWebSafe else { return (data, type) }
    #if canImport(UIKit)
    if let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.9) {
        return (jpeg, .jpeg)
    }
    #endif
    return (data, type)
}
