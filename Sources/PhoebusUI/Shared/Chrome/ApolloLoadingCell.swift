import SwiftUI
import PhoebusCore

/// The loading state a list shows while its first page is in flight.
///
/// Rendered as a list cell rather than an overlay, like Apollo's. The
/// spinner uses the theme's accent colour. It appears after a 250ms
/// delay so a cached or fast response does not flash a spinner for one
/// frame.
public struct ApolloLoadingCell: View {
    /// Shown under the spinner. Nil for a plain spinner, as in Apollo.
    let label: String?

    @Environment(\.apolloTheme) private var apolloTheme
    @State private var isVisible = false

    public init(label: String? = nil) {
        self.label = label
    }

    public var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 10) {
                ProgressView()
                    .tint(apolloTheme.color(.accent) ?? .accentColor)
                if let label {
                    Text(label)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 28)
        // Held invisible rather than unbuilt, so the row keeps its
        // height and the list does not jump when it appears.
        .opacity(isVisible ? 1 : 0)
        .accessibilityIdentifier("apollo.loading")
        .accessibilityLabel(label ?? "Loading")
        .task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            withAnimation(.easeIn(duration: 0.15)) { isVisible = true }
        }
    }
}
