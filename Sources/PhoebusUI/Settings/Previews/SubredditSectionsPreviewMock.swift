import SwiftUI
import PhoebusCore

/// Live preview mock for the Subreddit Sections settings screen.
///
/// Renders `SubredditSectionsPreview.blocks(for:)`: a miniature,
/// non-interactive rendering of the Subreddits list: one band + sample
/// row per special section in the configured order, then a letter band
/// showing where the alphabetical list continues.
///
/// The block model lives in PhoebusCore; this only draws it. Reborn diffs two
/// renderings by key and signature to choose between a slide, a cross-fade
/// and a scale-fade. SwiftUI does the same from `.id` plus an animation, so
/// the keys drive the sample followed user sliding between the FOLLOWING band
/// and the U letter band as the separation toggle flips.
///
/// Geometry, measured against Reborn's constants:
///
/// | element            | measured (pt)        | Reborn   |
/// |--------------------|----------------------|----------|
/// | letter circle      | x 42.0-63.7 (21.7)   | 22, +12  |
/// | name label         | x 74.7 (circle + 10) | +10      |
/// | name size          | band 198-211 w/ desc | 14       |
/// | subtitle           | 11pt #8D8D92         | 11       |
/// | star               | x 338-349.7 (11.7)   | 14, -12  |
/// | band label         | cap 9.0, x 43        | 12 bold  |
/// | band rule          | x 118.3-358.7, 1.7   | 1.5, -4  |
/// | band label colour  | rgb(75,150,247)      | accent   |
///
/// The star is the accent colour, and the circle carries the name's initial
/// in white.
struct SubredditSectionsPreviewMock: View {
    let settings: SubredditSectionsSettings

    private var blocks: [SubredditSectionsPreviewBlock] {
        SubredditSectionsPreview.blocks(for: settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SubredditSectionsPreviewBlock.blockSpacing) {
            ForEach(blocks) { block in
                switch block.kind {
                case .band:
                    band(block)
                        .frame(height: SubredditSectionsPreviewBlock.bandHeight)
                        .id(block.key)
                case .row:
                    row(block)
                        .frame(height: block.height)
                        .id(block.key)
                }
            }
        }
        .padding(.vertical, SubredditSectionsPreviewBlock.verticalPadding)
        .animation(.easeInOut(duration: 0.25), value: blocks)
    }

    /// Band. Modern Subreddit Dividers draws the accent label + fading accent
    /// rule; with Enhancements or Modern Dividers off it collapses to the classic
    /// grey pill.
    @ViewBuilder
    private func band(_ block: SubredditSectionsPreviewBlock) -> some View {
        if block.modern {
            HStack(spacing: 8) {
                Text(block.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.apolloAccent)
                // The accent-to-clear rule the Subreddits root header draws, at the card's
                // scale: it fades (rgb(75,150,247) at its left, sinking into the background
                // by x 358.7) rather than using Reborn's flat 55% accent line.
                LinearGradient(
                    colors: [Color.apolloAccent.opacity(0.55), Color.apolloAccent.opacity(0)],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(height: 1.5)
                .padding(.trailing, 4)
            }
            .padding(.leading, 12)
        } else {
            HStack(spacing: 0) {
                Text(block.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(.tertiarySystemFill).opacity(0.5))
            )
        }
    }

    /// Real row: 22pt initial circle at +12, 10pt gap, a
    /// 14pt name over an optional 11pt subtitle, accent star at -12.
    private func row(_ block: SubredditSectionsPreviewBlock) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(color(for: block.tint))
                Text(initial(for: block.title))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(block.title)
                    .font(.system(size: 14))
                if let subtitle = block.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if block.starred {
                Image(systemName: "star.fill")
                    .font(.system(size: 11))
                    .frame(width: 14, height: 14)
                    .foregroundStyle(Color.apolloAccent)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
    }

    /// Real initial: the name's first letter, upper-cased,
    /// with any "u/" prefix stripped first - so the followed user's
    /// circle reads "U" for "username", not for the prefix.
    private func initial(for title: String) -> String {
        let bare = title.replacingOccurrences(of: "u/", with: "")
        return bare.isEmpty ? "" : String(bare.prefix(1)).uppercased()
    }

    /// Real sample tints.
    private func color(for tint: SubredditSectionsPreviewBlock.Tint?) -> Color {
        switch tint {
        case .indigo: return .indigo
        case .teal: return .teal
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        case nil: return .gray
        }
    }
}
