import SwiftUI
import PhoebusCore

/// Reborn's Tag Filters cover: a dark frosted blur over a filtered post's
/// title or media with an "NSFW" (red) or "SPOILER" (grey) pill. Tapping asks
/// "View hidden post?" and reveals only that part.
struct TagFilterCover: ViewModifier {
    enum Part: String { case title, media }

    let part: Part
    let isNSFW: Bool
    let isActive: Bool
    var cornerRadius: CGFloat = 8
    var showsPill: Bool = true
    let onReveal: () -> Void

    @State private var confirming = false

    func body(content: Content) -> some View {
        content.overlay {
            if isActive {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                    if showsPill {
                        Text(isNSFW ? "NSFW" : "SPOILER")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill(isNSFW ? Color(red: 0.85, green: 0.10, blue: 0.10).opacity(0.95)
                                             : Color(white: 0.35).opacity(0.95)))
                    }
                }
                .contentShape(Rectangle())
                .highPriorityGesture(TapGesture().onEnded { confirming = true })
                .accessibilityLabel(isNSFW ? "NSFW post, hidden" : "Spoiler, hidden")
                .accessibilityAddTraits(.isButton)
            }
        }
        .alert("View hidden post?", isPresented: $confirming) {
            Button("Cancel", role: .cancel) {}
            Button("Reveal", role: .destructive, action: onReveal)
        } message: {
            Text(part == .title ? "Reveal the title of this filtered post?" : "Reveal the media of this filtered post?")
        }
    }
}

extension View {
    func tagFilterCover(_ part: TagFilterCover.Part, isNSFW: Bool, isActive: Bool,
                        cornerRadius: CGFloat = 8, showsPill: Bool = true,
                        onReveal: @escaping () -> Void) -> some View {
        modifier(TagFilterCover(part: part, isNSFW: isNSFW, isActive: isActive,
                                cornerRadius: cornerRadius, showsPill: showsPill, onReveal: onReveal))
    }
}
