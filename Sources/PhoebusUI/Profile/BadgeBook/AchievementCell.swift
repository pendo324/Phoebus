import SwiftUI
import PhoebusCore

/// A single tile for a Reddit achievement from `AchievementCatalog` (Reborn's
/// bundled `badgebook-catalog.json`). Shown as a plain reference tile with no
/// earned/locked state, since which achievements a user has earned is not
/// known, unlike `EarnedBadgeCell`'s locally computed account milestones.
struct AchievementCell: View {
    let achievement: AchievementDefinition
    @State private var showingBio = false

    var body: some View {
        Button {
            showingBio = true
        } label: {
            VStack(spacing: 6) {
                // Each tile shows the catalog's `image_url` (Reddit's i.redd.it CDN),
                // falling back to a generic placeholder when absent.
                if let file = BundledBadgeArt.catalog.file(imageURL: achievement.imageURL) {
                    BadgeArtImage(file: file, remoteURL: achievement.imageURL.flatMap(URL.init(string:)))
                        .frame(width: 56, height: 56)
                } else if let imageURLString = achievement.imageURL, let url = URL(string: imageURLString) {
                    CachedAsyncImage(url: url)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.apolloAccent.opacity(0.1))
                        .frame(width: 56, height: 56)
                        .overlay {
                            Image(systemName: "rosette")
                                .font(.title2)
                                .foregroundStyle(Color.apolloAccent)
                        }
                }
                Text(achievement.title)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .alert(achievement.title, isPresented: $showingBio) {
            Button("OK") {}
        } message: {
            Text(achievement.bio)
        }
    }
}
