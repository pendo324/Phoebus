import SwiftUI
import PhoebusCore

/// A single trophy tile in Reborn's "Badge Book" grid: the icon with
/// its name below and the full description on tap.
struct BadgeBookCell: View {
    let trophy: RedditTrophy
    @State private var showingDescription = false

    var body: some View {
        Button {
            showingDescription = true
        } label: {
            VStack(spacing: 6) {
                if let file = BundledBadgeArt.catalog.trophyFile(iconURL: trophy.iconURL, title: trophy.name) {
                    BadgeArtImage(file: file, remoteURL: trophy.iconURL.flatMap(URL.init(string:)))
                        .frame(width: 56, height: 56)
                } else if let iconURL = trophy.iconURL, let url = URL(string: iconURL) {
                    CachedAsyncImage(url: url)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 56, height: 56)
                        .overlay {
                            Image(systemName: "trophy.fill")
                                .foregroundStyle(.secondary)
                        }
                }
                Text(trophy.name)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .alert(trophy.name, isPresented: $showingDescription) {
            Button("OK") {}
        } message: {
            if let description = trophy.description, !description.isEmpty {
                Text(description)
            }
        }
    }
}
