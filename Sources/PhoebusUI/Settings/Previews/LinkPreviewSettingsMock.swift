import SwiftUI
import PhoebusCore

/// Live preview mock for the Rich Link Previews settings screen.
///
/// Mirrors Reborn's link preview card with its real sample strings. Shows
/// the Body and Comments areas at once, each captioned "AREA · Mode", since
/// they are configured separately.
struct LinkPreviewSettingsMock: View {
    let settings: LinkPreviewSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sample(area: "Body", mode: settings.bodyDisplayMode)
            sample(area: "Comments", mode: settings.commentsDisplayMode)
        }
        .animation(.easeInOut(duration: 0.2), value: settings)
    }

    /// Caption row: the area in semibold caps, then " · " and the mode name in
    /// regular weight.
    private func sample(area: String, mode: LinkPreviewDisplayMode) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            (
                Text(area.uppercased()).font(.system(size: 12, weight: .semibold))
                + Text(" · \(mode.title)").font(.system(size: 12))
            )
            .foregroundStyle(.secondary)
            // Keeps the caption 40pt clear of the pin glyph.
            .padding(.trailing, 40)

            card(for: mode)
        }
    }

    @ViewBuilder
    private func card(for mode: LinkPreviewDisplayMode) -> some View {
        switch mode {
        case .off:
            // Off: a plain link row with a chevron, no metadata.
            HStack(spacing: 6) {
                Text("website.com/example-page")
                    .font(.caption)
                    .foregroundStyle(Color.apolloAccent)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(8)
            .background(cardBackground)

        case .compact:
            // Compact: a small thumbnail beside the text.
            HStack(spacing: 8) {
                thumbnail
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Example link preview title")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text("A short description of the linked page.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(textColor)
            .padding(8)
            .background(cardBackground)

        case .full:
            // Full: a large image on top, then the site, title and description.
            VStack(alignment: .leading, spacing: 0) {
                thumbnail
                    .frame(height: 64)
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 2) {
                    Text("WEBSITE.COM")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Example link preview title")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text("A short description of the linked page.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .background(cardBackground)
        }
    }

    /// Image placeholder: a rounded `systemGray4` block with a centred `photo` glyph.
    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(.systemGray4))
            Image(systemName: "photo")
                .foregroundStyle(Color(.systemGray2))
        }
    }

    /// The custom card colour, when one is set. It is painted exactly as picked,
    /// in light and dark, with title and description text set to black or white
    /// for contrast.
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(settings.cardColorHex.map { Color(hex: $0) } ?? Color(.tertiarySystemFill))
    }

    /// Black or white text for the picked colour, so a dark custom card stays
    /// readable. See `HexContrast` for the coefficients and the 0.6 threshold.
    private var textColor: Color {
        guard let hex = settings.cardColorHex else { return .primary }
        guard HexContrast.needsDarkText(onHex: hex) else { return .white }
        let rgb = HexContrast.darkTextRGB
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
