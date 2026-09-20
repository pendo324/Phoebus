import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit
#endif

/// One Liquid Glass icon's preview art, in a named variant.
///
/// The pack ships four renditions per icon (`default`, `dark`,
/// `clear-light`, `clear-dark`); they are bundled flat as
/// `<id>.png` and `<id>--<variant>.png`.
enum LiquidGlassIconArt {
    #if canImport(UIKit)
    static func image(_ id: String, _ variant: String) -> UIImage? {
        let name = variant == "default" ? id : "\(id)--\(variant)"
        if let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "LiquidGlassIcons") {
            return UIImage(contentsOfFile: url.path)
        }
        // A standard pack's cover: Apollo's own app icon art.
        for scale in ["@3x", "@2x"] {
            if let path = Bundle.main.path(forResource: "AppIcon-\(id)60x60\(scale)", ofType: "png") {
                return UIImage(contentsOfFile: path)
            }
        }
        return nil
    }
    #endif
}

/// Two renditions of one icon, overlapped and rotated.
///
/// Reborn's "fan": the rear thumbnail is 0.72 of the host square, the squircle
/// corner is 0.2237 of the thumb side, and the two are rotated -0.09 and
/// +0.13 radians.
struct LiquidGlassRenditionFan: View {
    /// The icon this fan shows.
    let iconID: String
    /// The two variant names, front-most first.
    let front: String
    let back: String
    let side: CGFloat

    private var thumb: CGFloat { side * 0.72 }
    private var corner: CGFloat { thumb * 0.2237 }

    var body: some View {
        ZStack {
            art(back)
                .rotationEffect(.radians(0.13))
                .offset(x: thumb * 0.16, y: thumb * 0.05)
            art(front)
                .rotationEffect(.radians(-0.09))
                .offset(x: -thumb * 0.16, y: -thumb * 0.05)
        }
        .frame(width: side, height: side)
    }

    @ViewBuilder
    private func art(_ name: String) -> some View {
        #if canImport(UIKit)
        if let image = LiquidGlassIconArt.image(iconID, name) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: thumb, height: thumb)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(.quaternary)
                .frame(width: thumb, height: thumb)
        }
        #else
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(.quaternary)
            .frame(width: thumb, height: thumb)
        #endif
    }
}

/// Three cover icons fanned across a pack card (58pt thumbs, 29/5pt offsets,
/// 0.08 rotation step).
struct LiquidGlassCoverFan: View {
    let iconIDs: [String]
    let variant: String

    private let thumb: CGFloat = 58
    private let offsetX: CGFloat = 29
    private let offsetY: CGFloat = 5

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(iconIDs.prefix(3).enumerated()), id: \.offset) { index, id in
                art(id)
                    .rotationEffect(.radians(Double(index) - 1) * 0.08)
                    .offset(x: CGFloat(index) * offsetX, y: CGFloat(index) * offsetY)
            }
        }
        .frame(width: thumb + offsetX * 2, height: thumb + offsetY * 2, alignment: .topLeading)
    }

    @ViewBuilder
    private func art(_ id: String) -> some View {
        #if canImport(UIKit)
        if let image = LiquidGlassIconArt.image(id, variant) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: thumb, height: thumb)
                // 13pt corner at a 58pt thumb.
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(.quaternary)
                .frame(width: thumb, height: thumb)
        }
        #else
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(.quaternary)
            .frame(width: thumb, height: thumb)
        #endif
    }
}

/// A pack card: fanned covers, a title, and an "N icons" caption. 160pt tall,
/// 14pt corner, 12pt grid spacing; the selected card gets an accent ring plus
/// a check badge.
struct LiquidGlassPackCard: View {
    let title: String
    let iconCount: Int
    let coverIconIDs: [String]
    let isSelected: Bool
    let variant: String

    var body: some View {
        VStack(spacing: 6) {
            LiquidGlassCoverFan(iconIDs: coverIconIDs, variant: variant)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text("\(iconCount) icon\(iconCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.11)))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white, Color.accentColor)
                    .font(.system(size: 20))
                    .padding(6)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(iconCount) icon\(iconCount == 1 ? "" : "s")")
    }
}
