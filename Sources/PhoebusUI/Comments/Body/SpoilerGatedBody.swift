import SwiftUI
import PhoebusCore

/// A post body that stays hidden until tapped when the post is marked NSFW or
/// Spoiler. `PostMediaView.contentWarning` gates only the media node, so
/// without this a gallery post's self-text would sit readable beside hidden
/// images.
///
/// A tap reveals; the reveal is per-view and not persisted, so scrolling back
/// to a post re-hides it.
struct SpoilerGatedBody: View {
    let text: String
    let isHidden: Bool
    let lineLimit: Int?
    let onTap: () -> Void

    @State private var isRevealed = false

    var body: some View {
        if isHidden && !isRevealed {
            Button {
                isRevealed = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "eye.slash.fill")
                    Text("Tap to reveal spoiler text")
                    Spacer()
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.15))
                )
                .apolloFullRowTapTarget()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("postDetail.spoilerBody.reveal")
        } else {
            InlineMediaBodyView(text, lineLimit: lineLimit)
                .onTapGesture(perform: onTap)
        }
    }
}
