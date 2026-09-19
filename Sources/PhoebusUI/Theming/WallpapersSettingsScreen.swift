import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit
import Photos
#endif

/// Reborn's unlocked Wallpapers browser: the 32-wallpaper Goodbye collection
/// with artist credits, fetched from the artists' URLs (see `GoodbyeWallpaper`).
public struct WallpapersSettingsScreen: View {
    @State private var selectedWallpaper: GoodbyeWallpaper?
    @State private var saveMessage: String?

    public init() {}

    public var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 12) {
                    ForEach(GoodbyeWallpaper.all) { wallpaper in
                        Button {
                            saveMessage = nil
                            selectedWallpaper = wallpaper
                        } label: {
                            VStack(spacing: 4) {
                                wallpaperImage(wallpaper)
                                    .aspectRatio(2.0/3.0, contentMode: .fill)
                                    .frame(height: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                Text(wallpaper.name)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                // Every artist is credited ("<Name> by <Artist>") so the credit
                                // travels with the art.
                                if let artist = wallpaper.artist {
                                    Text(artist)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
            }
            .padding()
        }
        .apolloSettingsListAppearance()
        .navigationTitle("Wallpapers")
        .sheet(item: $selectedWallpaper) { wallpaper in
            NavigationStack {
                VStack {
                    wallpaperImage(wallpaper)
                        .aspectRatio(contentMode: .fit)
                    if let saveMessage {
                        Text(saveMessage).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .navigationTitle(wallpaper.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { selectedWallpaper = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save to Photos") {
                            save(wallpaper)
                        }
                    }
                }
            }
        }
    }

    /// Fetched, not bundled: the artists host the art and the album is picked
    /// per device class.
    @ViewBuilder
    private func wallpaperImage(_ wallpaper: GoodbyeWallpaper) -> some View {
        if let url = URL(string: wallpaper.url) {
            CachedAsyncImage(url: url)
        } else {
            Color.secondary.opacity(0.2)
        }
    }

    #if canImport(UIKit)
    private func save(_ wallpaper: GoodbyeWallpaper) {
        guard let url = URL(string: wallpaper.url) else {
            saveMessage = "Couldn't load this wallpaper."
            return
        }
        saveMessage = "Saving..."
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = UIImage(data: data) else {
                    saveMessage = "Couldn't load this wallpaper."
                    return
                }
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    DispatchQueue.main.async {
                        guard status == .authorized || status == .limited else {
                            saveMessage = "Photo library access is needed to save wallpapers."
                            return
                        }
                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                        saveMessage = "Saved to Photos."
                    }
                }
            } catch {
                saveMessage = "Couldn't download this wallpaper."
            }
        }
    }
    #else
    private func save(_ wallpaper: GoodbyeWallpaper) {}
    #endif
}
