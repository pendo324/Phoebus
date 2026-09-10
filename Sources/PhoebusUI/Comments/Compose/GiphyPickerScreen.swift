import SwiftUI
import PhoebusCore

/// Reborn's GIF picker: a full-screen 2-column GIF grid (trending by
/// default, live search) with the "Powered by GIPHY" attribution Giphy's API
/// terms require and a bottom search field.
public struct GiphyPickerScreen: View {
    let onSelect: (GiphyGIF) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var gifs: [GiphyGIF] = []
    @State private var query = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var offset = 0
    @State private var hasMore = false

    public init(onSelect: @escaping (GiphyGIF) -> Void) {
        self.onSelect = onSelect
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding()
                        .accessibilityIdentifier("giphy.error")
                }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                        ForEach(gifs) { gif in
                            Button {
                                onSelect(gif)
                                dismiss()
                            } label: {
                                if let previewURL = gif.previewURL {
                                    CachedAsyncImage(url: previewURL)
                                        .aspectRatio(1, contentMode: .fill)
                                        .clipped()
                                } else {
                                    Color.secondary.opacity(0.15)
                                        .aspectRatio(1, contentMode: .fill)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("giphy.gif.\(gif.id)")
                        }
                    }
                    if hasMore {
                        ProgressView()
                            .padding()
                            .onAppear { Task { await loadMore() } }
                    }
                }
                // Real "Powered by GIPHY" attribution, required by
                // Giphy's API terms.
                Text("Powered by GIPHY")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search GIFs", text: $query)
                        .onSubmit { Task { await search() } }
                        .accessibilityIdentifier("giphy.searchField")
                }
                .padding()
                .background(Color.secondarySystemBackgroundIfAvailable)
            }
            .navigationTitle("GIPHY")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                        .accessibilityLabel("Close")
                    }
                }
            }
            .task { await search() }
        }
    }

    private func search() async {
        isLoading = true
        errorMessage = nil
        offset = 0
        defer { isLoading = false }
        do {
            let result = try await GiphyClient.search(query: query, offset: 0)
            gifs = result.gifs
            hasMore = result.hasMore
            offset = result.gifs.count
        } catch GiphyClient.ClientError.notConfigured {
            errorMessage = "Configure your Giphy API key in Settings > Custom API to use the GIF picker."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await GiphyClient.search(query: query, offset: offset)
            gifs.append(contentsOf: result.gifs)
            hasMore = result.hasMore
            offset += result.gifs.count
        } catch {
            // Pagination failures degrade silently, the user already
            // has a usable grid of results.
            hasMore = false
        }
    }
}
