import SwiftUI
import PhoebusCore

/// The comment jump button's face: a solid blue circle with a white
/// chevron-down, sized to match the collapsed tab pill (44x44). The post screen
/// makes it the button that scrolls to the next top-level comment, and the
/// Comments preview shows it where Jump Button Position puts it. In Reborn's
/// New Comments mode the chevron rises and a small "NEW" caption sits below it.
struct CommentJumpButtonLabel: View {
    var mode: CommentNavigationMode = .threads

    var body: some View {
        ZStack {
            Image(systemName: "chevron.down")
                .font(.title2.bold())
                .offset(y: mode == .newComments ? -6 : 0)
            if mode == .newComments {
                Text("NEW")
                    .font(.system(size: 8, weight: .semibold))
                    .offset(y: 7)
            }
        }
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
