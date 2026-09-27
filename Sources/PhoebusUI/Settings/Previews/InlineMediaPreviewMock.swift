import SwiftUI
import PhoebusCore

/// Live preview mock for the Inline Media settings screen.
///
/// Mirrors Reborn's inline media preview card: 12pt horizontal inset, 8pt
/// vertical pad, a 440pt content cap, and a constant 110pt media block whose
/// width alone follows the size control. The card is pinned, so a true 16:9
/// block would cost ~190pt of list height at 100% and leave a hole at 50%.
struct InlineMediaPreviewMock: View {
    let settings: InlineMediaSettings

    /// Content width cap.
    private let maxContentWidth: CGFloat = 440
    /// Media block height, constant by design.
    private let mediaHeight: CGFloat = 110
    /// Link row height.
    private let linkHeight: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 20, height: 20)
                Text("ApolloUser")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(.tertiarySystemFill))
                .frame(height: 8)
                .frame(maxWidth: 220, alignment: .leading)

            GeometryReader { geometry in
                let content = min(geometry.size.width, maxContentWidth)
                if settings.enabled {
                    // Only the width follows the size control.
                    let width = max(60, content * settings.size.fraction)
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(.tertiarySystemFill))
                        // 26pt play badge pinned bottom-right, for Tap to Play only.
                        if settings.autoplayMode == .tapToPlay {
                            Image(systemName: "play.circle.fill")
                                .resizable()
                                .frame(width: 26, height: 26)
                                .foregroundStyle(.white.opacity(0.9))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                                .padding(6)
                        }
                        Text("GIF")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.black.opacity(0.55)))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            .padding(6)
                    }
                    .frame(width: width, height: mediaHeight)
                    .frame(maxWidth: .infinity, alignment: settings.alignment.previewAlignment)
                } else {
                    // Off: a plain link in the accent colour, as a body link renders.
                    Text("https://i.imgur.com/example.gif")
                        .font(.caption)
                        .foregroundStyle(Color.apolloAccent)
                        .lineLimit(1)
                        .frame(height: linkHeight, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: settings.enabled ? mediaHeight : linkHeight)
        }
        .animation(.easeInOut(duration: 0.2), value: settings)
    }
}

// `InlineMediaSize.fraction` carries the 0.5/0.75/1.0 values; reusing it
// keeps the preview from disagreeing with the setting.

private extension InlineMediaAlignment {
    var previewAlignment: Alignment {
        switch self {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }
}
