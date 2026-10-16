import SwiftUI
import PhoebusCore

/// The comment jump button's face: a solid blue circle with a white
/// chevron-down, sized to match the collapsed tab pill (44x44). The post screen
/// makes it the button that scrolls to the next top-level comment, and the
/// Comments preview shows it where Jump Button Position puts it.
struct CommentJumpButtonLabel: View {
    var body: some View {
        Image(systemName: "chevron.down")
            .font(.title2.bold())
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(Circle().fill(Color.apolloAccent))
            .shadow(radius: 2)
    }
}

extension JumpButtonPosition {
    var alignment: Alignment {
        switch self {
        case .bottomTrailing: return .bottomTrailing
        case .middleTrailing: return .trailing
        case .topTrailing: return .topTrailing
        case .center: return .bottom
        case .bottomLeading: return .bottomLeading
        case .middleLeading: return .leading
        case .topLeading: return .topLeading
        }
    }

    var sitsAtBottom: Bool { alignment.vertical == .bottom }
}
