import SwiftUI

/// The inline "Find in Comments" field at the very top of the comments
/// screen's scroll content, above the post header.
///
/// A capsule 16..377 wide, 43pt tall, 21.5pt radius, filled #1C1C1E,
/// magnifier at x 30 and 17pt placeholder at x 57.3 (same geometry as
/// Settings' search field: `ApolloSearchCapsuleMetrics`).
///
/// Not `.searchable`: Apollo's control is an inline search-bar-shaped
/// row that scrolls with the content rather than docking to the nav bar.
/// Tapping it activates `FindInCommentsBar`, which keeps the
/// counter/next/previous affordances once search is live.
public struct FindInCommentsFieldRow: View {
    let onActivate: () -> Void
    /// The placeholder: "Find in Comments" here, "Search" at the top of
    /// a feed.
    var placeholder: String = "Find in Comments"
    var identifier: String = "postDetail.findInCommentsField"
    @Environment(\.colorScheme) private var colorScheme

    public init(onActivate: @escaping () -> Void) {
        self.onActivate = onActivate
    }

    public init(placeholder: String, identifier: String, onActivate: @escaping () -> Void) {
        self.onActivate = onActivate
        self.placeholder = placeholder
        self.identifier = identifier
    }

    /// #1C1C1E in pure-black dark mode; light mode uses the same grouped
    /// fill grey as the feed's own search field.
    private var fieldFill: Color {
        Color.apolloSearchFieldFill(colorScheme: colorScheme)
    }

    /// The placeholder's measured rgb(105,105,107).
    private var placeholderColor: Color {
        Color.apolloSearchFieldPlaceholder(colorScheme: colorScheme)
    }

    public var body: some View {
        Button(action: onActivate) {
            HStack(spacing: ApolloSearchCapsuleMetrics.iconToText) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17))
                Text(placeholder)
                    .font(.system(size: 17))
                Spacer(minLength: 0)
            }
            .foregroundStyle(placeholderColor)
            // Same capsule as Settings' search field: x 16..377, 21.5pt radius,
            // magnifier at x 30.
            .apolloSearchCapsule(fill: fieldFill)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(placeholder)
    }
}

/// The band behind the feed's search field. In light mode Apollo sits
/// the field on the #F2F3F7 page colour, from under the navigation bar
/// down to the first post; dark mode keeps the list's own surface.
struct FeedSearchBand: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if colorScheme == .light {
            let band = Color(hex: ApolloCardMetrics.pageLightHex)
            content
                // Reaches up under the bar: the row is the list's
                // first, so nothing above it would cover this.
                .background(alignment: .bottom) {
                    band.frame(height: 600).allowsHitTesting(false)
                }
                .listRowBackground(band)
        } else {
            content.listRowBackground(Color.clear)
        }
    }
}
