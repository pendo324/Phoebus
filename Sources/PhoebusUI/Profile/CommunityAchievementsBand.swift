import SwiftUI
import PhoebusCore

/// "Achievements in r/<sub>": a row of the user's community trophies. A
/// trophy that matches a Badge Book entry opens that entry's description.
struct CommunityAchievementsBand: View {
    let subreddit: String
    let achievements: CommunityAchievements
    @State private var selected: CommunityAchievements.Trophy?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Achievements in r/\(subreddit)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(achievements.trophies) { trophy in
                        Button { selected = trophy } label: {
                            VStack(spacing: 4) {
                                if let url = trophy.imageURL {
                                    CachedAsyncImage(url: url)
                                        .frame(width: 44, height: 44)
                                } else {
                                    Image(systemName: "rosette")
                                        .font(.title2)
                                        .foregroundStyle(Color.apolloAccent)
                                        .frame(width: 44, height: 44)
                                }
                                Text(trophy.name)
                                    .font(.caption2)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .foregroundStyle(.primary)
                            }
                            .frame(width: 64)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(trophy.name), achievement in r/\(subreddit)")
                        .accessibilityIdentifier("profile.communityAchievement.\(trophy.id)")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.communityAchievements")
        .alert(selected?.name ?? "", isPresented: $selected.isPresent()) {
            Button("OK") {}
        } message: {
            Text(selected?.catalogEntry?.bio ?? "Achievement in r/\(subreddit)")
        }
    }
}
