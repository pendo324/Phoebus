import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit
#endif

/// Reborn's bundled Badge Book art, loaded once.
enum BundledBadgeArt {
    static let catalog: BadgeBookArt = {
        guard let url = Bundle.module.url(forResource: "badgebook-catalog", withExtension: "json", subdirectory: "BadgeBook"),
              let data = try? Data(contentsOf: url) else { return BadgeBookArt(catalogJSON: Data()) }
        return BadgeBookArt(catalogJSON: data)
    }()

    static func url(_ file: String?) -> URL? {
        guard let file else { return nil }
        let name = (file as NSString).deletingPathExtension
        return Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "BadgeBook")
    }
}

/// A badge's icon: Reborn's bundled art when the catalogue has it,
/// else Reddit's own image.
struct BadgeArtImage: View {
    let file: String?
    let remoteURL: URL?

    var body: some View {
        #if canImport(UIKit)
        if let local = BundledBadgeArt.url(file), let image = UIImage(contentsOfFile: local.path) {
            Image(uiImage: image).resizable().scaledToFit()
        } else {
            CachedAsyncImage(url: remoteURL, contentMode: .fit)
        }
        #else
        CachedAsyncImage(url: remoteURL, contentMode: .fit)
        #endif
    }
}
