import SwiftUI
import PhoebusCore

/// The Text Sizes & Fonts preview: a compact feed row, an opened post's
/// title and text, and a comment, each drawn with the role it previews.
struct TextSizesPreviewMock: View {
    let settings: TextScaleSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Apollo")
                    .apolloFont(size: 15, weight: .semibold, role: .postMeta)
                    .foregroundStyle(.secondary)
                Text("What's a small change that made your phone nicer to read?")
                    .apolloFont(size: 15, role: .postTitle)
                Text("↑ 1.2k  ·  💬 184  ·  4h")
                    .apolloFont(size: 13, role: .postMeta)
                    .foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Opened post title")
                    .apolloFont(size: 20, weight: .semibold, role: .openedPostTitle)
                LongBodyText("Post text, with **bold**, *italic* and `code` in it.")
                    .apolloFont(size: 15, role: .postBody)
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("ApolloUser")
                        .apolloFont(size: 15, weight: .medium, role: .commentHeader)
                    Text("↑ 42  ·  2h")
                        .apolloFont(size: 13, role: .commentHeader)
                        .foregroundStyle(.secondary)
                }
                LongBodyText("A comment, with a [link](https://example.com) and `code`.")
                    .apolloFont(size: 15, role: .commentBody)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        // Set here as well as at the root so the preview follows the
        // controls in the same frame.
        .environment(\.apolloTextScale, settings)
        .accessibilityIdentifier("textSizes.preview")
    }
}
