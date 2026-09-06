import SwiftUI

/// Apollo's "Double tap to upvote": an Instagram-style double-tap-to-like
/// gesture on post media with a brief upvote-arrow burst as feedback.
public struct DoubleTapUpvoteModifier: ViewModifier {
    let onUpvote: () -> Void
    @State private var showBurst = false

    public func body(content: Content) -> some View {
        content
            .overlay {
                if showBurst {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.orange)
                        .shadow(radius: 8)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .onTapGesture(count: 2) {
                onUpvote()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    showBurst = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showBurst = false
                    }
                }
            }
    }
}

extension View {
    /// Attaches Apollo's double-tap-to-upvote gesture to post media.
    public func doubleTapToUpvote(onUpvote: @escaping () -> Void) -> some View {
        modifier(DoubleTapUpvoteModifier(onUpvote: onUpvote))
    }
}
