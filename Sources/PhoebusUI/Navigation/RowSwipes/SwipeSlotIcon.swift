import SwiftUI
import PhoebusCore

/// The per-row swipe icons for the Gestures screen.
///
/// Apollo shows one icon per row: left short, left long, right short, right
/// long. Apollo's icon art is copyrighted, so this draws the same schematic
/// the icons depict: a phone-screen rounded rectangle with a filled band on
/// the swiping edge, narrow for a short swipe and wide for a long one.
struct SwipeSlotIcon: View {
    let slot: SwipeSlot

    private var isLeadingEdge: Bool {
        slot == .leftShort || slot == .leftLong
    }

    private var isLong: Bool {
        slot == .leftLong || slot == .rightLong
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let corner: CGFloat = 3
            // Short swipes fill about a third of the screen width,
            // long swipes about two thirds - matching how the real
            // icons distinguish the two.
            let fillWidth = w * (isLong ? 0.62 : 0.34)

            ZStack(alignment: isLeadingEdge ? .leading : .trailing) {
                RoundedRectangle(cornerRadius: corner)
                    .stroke(Color.apolloAccent, lineWidth: 1.5)
                    .frame(width: w, height: h)

                RoundedRectangle(cornerRadius: corner)
                    .fill(Color.apolloAccent)
                    .frame(width: fillWidth, height: h)
            }
            .frame(width: w, height: h)
        }
        .frame(width: 26, height: 19)
        .accessibilityHidden(true)
    }
}
