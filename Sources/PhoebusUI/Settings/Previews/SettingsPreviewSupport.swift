import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit
#endif

/// True inside a settings preview that draws the app's own post or comment
/// row. Those rows fetch avatars, subreddit icons, account ages and
/// translations when they appear, and read the signed-in account; they skip
/// all of it while this is set.
private struct IsSettingsPreviewKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isSettingsPreview: Bool {
        get { self[IsSettingsPreviewKey.self] }
        set { self[IsSettingsPreviewKey.self] = newValue }
    }
}

extension View {
    /// Makes real rows safe to show as a preview: they take no taps, holds
    /// or swipes, and the group is one VoiceOver element with no actions of
    /// its own (so nothing in it can vote, save or open anything). The rows
    /// see `isSettingsPreview`.
    func inertSettingsPreview(label: String) -> some View {
        environment(\.isSettingsPreview, true)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
    }
}

/// The picture the sample post carries: drawn here once into a local file, so
/// the real row's image loader reads a `file://` URL and nothing is fetched.
enum SettingsPreviewImage {
    static let url: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("phoebus-settings-preview-sample.png")
        #if canImport(UIKit)
        guard !FileManager.default.fileExists(atPath: url.path) else { return url }
        let size = CGSize(width: 640, height: 480)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let png = UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            let cg = context.cgContext
            let colors = [UIColor(red: 0.96, green: 0.80, blue: 0.55, alpha: 1).cgColor,
                          UIColor(red: 0.72, green: 0.45, blue: 0.22, alpha: 1).cgColor]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            // A loaf: a dark rounded oval with three scores across the top.
            UIColor(red: 0.45, green: 0.26, blue: 0.12, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: 90, y: 150, width: 460, height: 220))
            UIColor(red: 0.96, green: 0.84, blue: 0.62, alpha: 1).setStroke()
            cg.setLineWidth(14)
            cg.setLineCap(.round)
            for x in stride(from: 220.0, through: 420.0, by: 100.0) {
                cg.move(to: CGPoint(x: x - 30, y: 215))
                cg.addLine(to: CGPoint(x: x + 30, y: 275))
            }
            cg.strokePath()
        }
        try? png.write(to: url, options: .atomic)
        #endif
        return url
    }()
}
