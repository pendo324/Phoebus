import SwiftUI
import PhoebusCore

/// A single badge tile in Reborn's "Badge Book" grid. Unlike
/// `BadgeBookCell` (a Reddit trophy), this renders a locally evaluated
/// `EarnedBadge` with a locked/unlocked state, showing the full catalog
/// with greyed-out locked badges.
struct EarnedBadgeCell: View {
    let badge: EarnedBadge
    @State private var showingDescription = false

    var body: some View {
        Button {
            showingDescription = true
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(badge.isEarned ? Color.apolloAccent.opacity(0.15) : Color.secondary.opacity(0.1))
                        .frame(width: 56, height: 56)
                    Image(systemName: badge.definition.symbolName)
                        .font(.title2)
                        .foregroundStyle(badge.isEarned ? Color.apolloAccent : Color.secondary.opacity(0.4))
                }
                Text(badge.definition.name)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(badge.isEarned ? .primary : .secondary)
            }
            .opacity(badge.isEarned ? 1.0 : 0.6)
        }
        .buttonStyle(.plain)
        .alert(badge.definition.name, isPresented: $showingDescription) {
            Button("OK") {}
        } message: {
            Text(badge.isEarned ? badge.definition.description : "Locked — \(badge.definition.description)")
        }
    }
}
