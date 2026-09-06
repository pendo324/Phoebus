import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit
import PhotosUI

/// Reborn "Subreddit Headers: tap-to-set custom local images" (#266).
///
/// A user can replace any subreddit's banner or icon with a photo of their
/// own. Stored locally only, keyed by lowercased subreddit name:
/// - banner: centre-cropped to 5:1, at most 1280px wide, JPEG 0.85
///   stepping down to 0.45 to stay under 1.5 MB;
/// - icon: centre-cropped square, at most 512px, PNG under 500 KB else
///   256px.
/// "Clear Custom Banners & Icons" in the Reborn hub wipes both.
public enum SubredditCustomArtKind: String, Sendable { case banner, icon }

/// Reborn #799/#837 custom multireddit icons ride the subreddit icon store
/// under a slash-free key built from the multireddit's path (stable across
/// display-name renames), namespaced so it can never collide with a
/// subreddit ("multi" + path with "/" -> "~").
public func multiredditIconKey(path: String) -> String {
    "multi" + path.replacingOccurrences(of: "/", with: "~")
}

@MainActor
public final class SubredditCustomArtStore: ObservableObject {
    public static let shared = SubredditCustomArtStore()
    /// Bumped on every change so views re-read.
    @Published public private(set) var revision = 0
    private var cache: [String: UIImage] = [:]

    private init() {}

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SubredditCustomArt", isDirectory: true)
    }

    private static func fileURL(_ subreddit: String, _ kind: SubredditCustomArtKind) -> URL {
        let key = subreddit.lowercased().trimmingCharacters(in: .whitespaces)
        return directory.appendingPathComponent("\(kind.rawValue)-\(key).\(kind == .banner ? "jpg" : "png")")
    }

    public func image(for subreddit: String, kind: SubredditCustomArtKind) -> UIImage? {
        let url = Self.fileURL(subreddit, kind)
        if let hit = cache[url.path] { return hit }
        guard let img = UIImage(contentsOfFile: url.path) else { return nil }
        cache[url.path] = img
        return img
    }

    public func has(_ subreddit: String, kind: SubredditCustomArtKind) -> Bool {
        FileManager.default.fileExists(atPath: Self.fileURL(subreddit, kind).path)
    }

    @discardableResult
    public func save(_ image: UIImage, for subreddit: String, kind: SubredditCustomArtKind) -> Bool {
        let data: Data?
        switch kind {
        case .banner: data = Self.bannerData(image)
        case .icon: data = Self.iconData(image)
        }
        guard let data else { return false }
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let url = Self.fileURL(subreddit, kind)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return false }
        cache[url.path] = nil
        revision += 1
        return true
    }

    public func remove(_ subreddit: String, kind: SubredditCustomArtKind) {
        let url = Self.fileURL(subreddit, kind)
        try? FileManager.default.removeItem(at: url)
        cache[url.path] = nil
        revision += 1
    }

    public var count: Int {
        (try? FileManager.default.contentsOfDirectory(atPath: Self.directory.path).count) ?? 0
    }

    public func clearAll() {
        try? FileManager.default.removeItem(at: Self.directory)
        cache.removeAll()
        revision += 1
    }

    // MARK: Normalisation (Reborn's constants)

    static func centreCrop(_ image: UIImage, aspect: CGFloat) -> CGImage? {
        guard let cg = image.cgImage else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        guard w > 1, h > 1 else { return nil }
        let rect: CGRect = (w / h > aspect)
            ? CGRect(x: (w - h * aspect) / 2, y: 0, width: h * aspect, height: h)
            : CGRect(x: 0, y: (h - w / aspect) / 2, width: w, height: w / aspect)
        return cg.cropping(to: rect.integral)
    }

    static func render(_ cg: CGImage, width: CGFloat, height: CGFloat, opaque: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = opaque
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { _ in
            UIImage(cgImage: cg).draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    static func bannerData(_ image: UIImage) -> Data? {
        guard let crop = centreCrop(image.normalizedUp(), aspect: 5) else { return nil }
        let w = min(1280, CGFloat(crop.width))
        let img = render(crop, width: w, height: w / 5, opaque: true)
        var quality: CGFloat = 0.85
        var data = img.jpegData(compressionQuality: quality)
        while let d = data, d.count > 1_572_864, quality > 0.45 {
            quality -= 0.1
            data = img.jpegData(compressionQuality: quality)
        }
        return data
    }

    static func iconData(_ image: UIImage) -> Data? {
        guard let crop = centreCrop(image.normalizedUp(), aspect: 1) else { return nil }
        let side = min(512, CGFloat(crop.width))
        if let d = render(crop, width: side, height: side, opaque: false).pngData(), d.count <= 512_000 { return d }
        return render(crop, width: min(256, side), height: min(256, side), opaque: false).pngData()
    }
}

private extension UIImage {
    /// Bakes EXIF orientation in, so the crop works on what is seen.
    func normalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in draw(at: .zero) }
    }
}

/// Tap/long-press behaviour on a subreddit header's banner or icon: tap views
/// the art when there is any, else offers options; long-press always offers
/// "View Banner/Icon", "Choose Photo", "Remove Custom …".
struct SubredditArtOptions: ViewModifier {
    let subreddit: String
    let kind: SubredditCustomArtKind
    /// The image a "View" shows (custom or official).
    let viewURL: URL?

    @ObservedObject private var store = SubredditCustomArtStore.shared
    @State private var showingOptions = false
    @State private var showingPicker = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var viewing: URL?

    private var isIcon: Bool { kind == .icon }

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture {
                if let url = currentViewURL { viewing = url } else { showingOptions = true }
            }
            .onLongPressGesture { showingOptions = true }
            .confirmationDialog("", isPresented: $showingOptions, titleVisibility: .hidden) {
                if let url = currentViewURL {
                    Button(isIcon ? "View Icon" : "View Banner") { viewing = url }
                }
                Button("Choose Photo") { showingPicker = true }
                if store.has(subreddit, kind: kind) {
                    Button(isIcon ? "Remove Custom Icon" : "Remove Custom Banner", role: .destructive) {
                        store.remove(subreddit, kind: kind)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .photosPicker(isPresented: $showingPicker, selection: $pickedItem, matching: .images)
            .onChange(of: pickedItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        store.save(image, for: subreddit, kind: kind)
                    }
                    pickedItem = nil
                }
            }
            .apolloImageViewer(url: $viewing)
    }

    /// Custom art is served from its file URL, like Reborn (the image loader
    /// handles file:// too).
    private var currentViewURL: URL? {
        _ = store.revision
        if store.has(subreddit, kind: kind) {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let key = subreddit.lowercased()
            return base.appendingPathComponent("SubredditCustomArt/\(kind.rawValue)-\(key).\(kind == .banner ? "jpg" : "png")")
        }
        return viewURL
    }
}

extension View {
    func subredditArtOptions(_ subreddit: String, kind: SubredditCustomArtKind, viewURL: URL?) -> some View {
        modifier(SubredditArtOptions(subreddit: subreddit, kind: kind, viewURL: viewURL))
    }
}
#endif
