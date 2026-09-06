import SwiftUI

/// A settings row that pushes a destination while drawing its OWN
/// disclosure chevron.
///
/// Why not a plain `NavigationLink`: SwiftUI's own disclosure indicator
/// is system-sized and system-coloured, and Apollo's is neither - the
/// real chevron is 7x12 at rgb(70,70,72) = #464648, appreciably
/// smaller and darker than the platform's. There is no API to restyle
/// the built-in one, so the link is rendered at zero opacity behind the
/// row (which hides its chevron along with the rest of it) and the row
/// draws the measured chevron itself.
///
/// Zero-opacity rather than `EmptyView()`: an empty label still lays
/// out the system chevron, so it has to be the whole link that is
/// invisible.
public struct SettingsNavigationRow<Label: View, Destination: View>: View {
    private let destination: Destination
    private let label: Label

    public init(@ViewBuilder destination: () -> Destination,
                @ViewBuilder label: () -> Label) {
        self.destination = destination()
        self.label = label()
    }

    public var body: some View {
        ZStack {
            // `SettingsLink`, not `NavigationLink`: pushes land in the Settings tab's
            // path so page swipes work.
            SettingsLink {
                destination
            } label: {
                EmptyView()
            }
            .opacity(0)

            label
        }
    }
}
