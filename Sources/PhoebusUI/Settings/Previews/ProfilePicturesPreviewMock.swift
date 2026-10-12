import SwiftUI
import PhoebusCore

/// Preview for the User Profiles settings screen (Reborn #1352): a sample
/// comment and a reply whose avatars grow in and out with Show User Profile
/// Pictures and follow Profile Picture Shape (Full and Circle clip to a circle,
/// Square to a rounded square at 24% of the side, like `AvatarClipShape`).
///
/// Reborn draws two bundled default avatars; these are plain coloured
/// placeholders with a person glyph, so no Reddit artwork ships.
struct ProfilePicturesPreviewMock: View {
    let showsPictures: Bool
    let shape: ProfileLayoutSettings.AvatarStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let avatarSize: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sample(name: "Winter121921", score: "1.9k", body: "Found a new hiking trail this weekend.", tint: .orange)
                .padding(.leading, 14)
            Rectangle()
                .fill(Color(.separator))
                .frame(height: 0.5)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            sample(name: "TheBean31415", score: "1.5k", body: "Nice! I tried a new coffee shop.", tint: .teal)
                .padding(.leading, 28)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.red)
                        .frame(width: 2)
                        .padding(.leading, 14)
                }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: showsPictures)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview: a comment by Winter121921 and a reply by TheBean31415.")
    }

    private func sample(name: String, score: String, body: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if showsPictures {
                    avatar(tint: tint)
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                }
                Text(name)
                    .font(.system(size: 14, weight: .medium))
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10, weight: .semibold))
                    Text(score)
                }
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                Text("3d")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 14)
            }
            Text(body)
                .font(.subheadline)
                .padding(.trailing, 14)
        }
    }

    private func avatar(tint: Color) -> some View {
        ZStack {
            tint
            Image(systemName: "person.fill")
                .font(.system(size: avatarSize * 0.5))
                .foregroundStyle(.white.opacity(0.9))
                .offset(y: avatarSize * 0.04)
        }
        .frame(width: avatarSize, height: avatarSize)
        .clipShape(AvatarClipShape(style: shape))
    }
}
