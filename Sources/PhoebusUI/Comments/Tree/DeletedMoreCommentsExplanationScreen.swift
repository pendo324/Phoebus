import SwiftUI
import PhoebusCore

/// Explanation for "N more comments" markers that resolve to nothing:
/// the referenced comments were deleted before the marker could be
/// updated, so there is nothing left to load. A rounded card with a
/// `UITextView` and a nav-bar Done button.
struct DeletedMoreCommentsExplanationScreen: View {
    let stub: MoreStub
    let onDismiss: () -> Void

    /// Explanation copy, verbatim, including the curly quotes.
    private static let explanationText = """
    Sometimes when you tap on “X more comments”, those comments have actually been deleted by the user or a moderator, so there’s not actually anything to load anymore. Reddit generates these "load more" markers when threads have a lot of comments, but if those "more" comments get deleted, sometimes their markers don’t get the memo and aren’t able to tell they were deleted until you try to load them.

    In those situations, rather than showing nothing, Apollo lets you know they were deleted.
    """

    /// Base URL prefix the comment/link id is appended to for the "open in
    /// Safari" deep link.
    private static let oldRedditCommentsURLPrefix = "https://old.reddit.com/comments/"

    private var deepLinkURL: URL? {
        // `stub.parentID` is a fullname like "t1_xxxxx"/"t3_xxxxx"; strip the
        // kind prefix to get the bare id for the old.reddit.com deep link.
        let bareID = stub.parentID.contains("_") ? String(stub.parentID.split(separator: "_", maxSplits: 1)[1]) : stub.parentID
        return URL(string: Self.oldRedditCommentsURLPrefix + bareID)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(Self.explanationText)
                    .font(.body)
                if let url = deepLinkURL {
                    Link(destination: url) {
                        Text("Tap here to open in Safari a direct link to where these comments would be, as extra proof that they’re indeed deleted.")
                            .font(.body)
                            .foregroundStyle(.blue)
                    }
                }
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .padding()
            )
            .navigationTitle("Deleted")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
    }
}
