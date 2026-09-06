import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit

/// The signed-in user's avatar as a tab bar icon (Reborn "Profile Picture Tab
/// Icon"): a 30pt circle in its own colours, since a tab bar item takes an
/// image, not a view.
@MainActor
public final class ProfileTabAvatar: ObservableObject {
    @Published public private(set) var image: UIImage?
    private var loadedFor: String?

    public init() {}

    public static let diameter: CGFloat = 30

    public func load(username: String?, repository: RedditRepository) async {
        guard let username, !username.isEmpty else { image = nil; loadedFor = nil; return }
        guard loadedFor != username.lowercased() || image == nil else { return }
        loadedFor = username.lowercased()
        var urlString = await AvatarCache.shared.cachedURL(for: username)
        if urlString == nil {
            urlString = try? await repository.fetchUserProfile(username: username).iconImage
            await AvatarCache.shared.store(url: urlString, for: username)
        }
        guard let urlString, let url = URL(string: urlString.replacingOccurrences(of: "&amp;", with: "&")) else { return }
        guard let data = await MediaBytes.data(for: url) else { return }
        guard let source = UIImage(data: data) else { return }
        image = Self.circular(source)
    }

    /// Clipped to a circle, aspect-filled, in original colours so the
    /// bar's tint and iOS 26's monochrome treatment leave it alone.
    static func circular(_ source: UIImage) -> UIImage {
        let side = diameter
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let rect = CGRect(x: 0, y: 0, width: side, height: side)
            UIBezierPath(ovalIn: rect).addClip()
            let aspect = source.size.width > 0 ? source.size.height / source.size.width : 1
            let size = aspect > 1 ? CGSize(width: side, height: side * aspect) : CGSize(width: side / max(aspect, 0.01), height: side)
            source.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height))
        }
        return rendered.withRenderingMode(.alwaysOriginal)
    }
}
#endif
