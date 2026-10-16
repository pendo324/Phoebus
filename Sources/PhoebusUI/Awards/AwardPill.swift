import SwiftUI
import PhoebusCore

extension AwardStore: @MainActor ObservableObject {}

/// Reddit's featured award icon with the total count: the pill a comment's
/// byline and the post header show. Tapping it opens `AwardDetailsSheet`.
struct AwardPill: View {
    let badge: AwardBadge
    var iconSize: CGFloat = 16
    var fontSize: CGFloat = 13
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 3) {
                if let url = badge.iconURL {
                    // Reddit's 40px icon, drawn at ~16pt.
                    CachedAsyncImage(url: url, downsampleTarget: .pixelWidth(iconSize, scale: 3))
                        .frame(width: iconSize, height: iconSize)
                } else {
                    Image(systemName: "medal.fill")
                        .font(.system(size: iconSize * 0.8))
                        .foregroundStyle(.yellow)
                }
                Text(ShareCardFormatting.abbreviated(badge.count))
                    .apolloFont(size: fontSize, role: .commentHeader)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(badge.count) \(badge.count == 1 ? "award" : "awards")")
        .accessibilityHint("Shows the awards")
    }
}
