import SwiftUI
import PhotosUI
import AVFoundation
import PhoebusCore

/// Compose/new-post screen with flair selection. Media posts use one
/// unified "Media" type (segmented Media / Link / Text) holding multiple
/// images or a single video, plus a "Posting in {subreddit}. View Rules"
/// line and a live title character counter.
public struct ComposePostScreen: View {
    @Setting(GeneralSettings.self) private var generalSettings
    let subreddit: String
    let repository: RedditRepository
    let onSubmitted: () -> Void

    @State private var title = ""
    @State private var selftextBody = ""
    @State private var linkURL = ""
    @State private var postType: PostType = .text
    /// Reddit's gallery limit. A single image is a one-item selection,
    /// submitted via the simpler `submitImagePost` endpoint.
    static let maxMediaImages = 20
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var selectedImages: [MediaComposeImage] = []
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var selectedVideoData: Data?
    @State private var selectedVideoPosterData: Data?
    @State private var isLoadingVideo = false
    @State private var flairOptions: [RedditFlairOption] = []
    @State private var selectedFlair: RedditFlairOption?
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var subredditRules: [SubredditRule] = []
    @Environment(\.dismiss) private var dismiss

    struct MediaComposeImage: Identifiable {
        let id = UUID()
        let data: Data
    }

    /// `public` so the subreddit "•••" menu's post-type icon row can
    /// name a type when opening this screen.
    public enum PostType: String, CaseIterable {
        case text = "Text"
        case link = "Link"
        /// Labelled "Media" in the segmented control.
        case media = "Media"
        case poll = "Poll"
    }

    /// Reborn's poll composer. Bounds: 2-6 options, 1-7 day duration
    /// (default 3).
    @State private var pollOptionTexts: [String] = ["", ""]
    @State private var pollDurationDays = PollComposeService.defaultDurationDays

    /// `initialType` preselects the segmented control. The subreddit "•••"
    /// menu opens the composer from post-type icons (link / text / poll).
    /// Defaults to `.text`.
    public init(subreddit: String,
                repository: RedditRepository,
                initialType: PostType = .text,
                onSubmitted: @escaping () -> Void) {
        self.subreddit = subreddit
        self.repository = repository
        self.onSubmitted = onSubmitted
        _postType = State(initialValue: initialType)
    }

    public var body: some View {
        crashTrackedBody.onAppear { CrashRecorder.record(.openedComposer) }
    }

    @ViewBuilder private var crashTrackedBody: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }

            Section {
                Picker("Type", selection: $postType) {
                    // Reborn "Polls Enabled" (`GeneralSettings.pollsEnabled`): hides the
                    // Poll option when off.
                    ForEach(PostType.allCases.filter { $0 != .poll || generalSettings.pollsEnabled }, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                // Live title character count.
                HStack {
                    TextField("Title", text: $title)
                    Text("\(title.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                switch postType {
                case .link:
                    TextField("URL", text: $linkURL)
                        #if os(iOS)
                        .keyboardType(.URL)
                        #endif
                case .text:
                    MarkdownComposerField(text: $selftextBody, placeholder: "Text (optional)", lineLimit: 5...10)
                case .media:
                    mediaEditor
                case .poll:
                    pollOptionsEditor
                    Stepper(pollDurationLabel, value: $pollDurationDays, in: PollComposeService.minDurationDays...PollComposeService.maxDurationDays)
                        .accessibilityIdentifier("compose.poll.durationStepper")
                }
            }

            // "Posting in {subreddit}. View Rules" line below the media picker.
            Section {
                postingInRow
            }

            if !flairOptions.isEmpty {
                Section("Flair") {
                    Picker("Flair", selection: $selectedFlair) {
                        Text("None").tag(RedditFlairOption?.none)
                        ForEach(flairOptions) { option in
                            Text(option.text).tag(RedditFlairOption?.some(option))
                        }
                    }
                }
            }

            Section {
                Button {
                    Task { await submit() }
                } label: {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text("Submit to r/\(subreddit)")
                    }
                }
                .disabled(!canSubmit || isSubmitting)
            }
        }
        .apolloFlatListAppearance()
        .navigationTitle("New Post")
        // Cancel/Post nav-bar buttons, like the other compose screens.
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSubmitting {
                    ProgressView()
                } else {
                    Button("Post") {
                        Task { await submit() }
                    }
                    .disabled(!canSubmit)
                    // Apollo's "Submit" key command (Command-Return).
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .task {
            await loadFlairs()
            subredditRules = (try? await repository.fetchSubredditRules(name: subreddit)) ?? []
        }
        .onChange(of: selectedPhotoItems) { _, newValue in
            Task {
                for item in newValue {
                    guard selectedImages.count < Self.maxMediaImages else { break }
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        selectedImages.append(MediaComposeImage(data: data))
                    }
                }
                selectedPhotoItems = []
            }
        }
        .onChange(of: selectedVideoItem) { _, newValue in
            guard let newValue else { return }
            isLoadingVideo = true
            Task {
                defer { isLoadingVideo = false }
                guard let data = try? await newValue.loadTransferable(type: Data.self) else { return }
                selectedVideoData = data
                selectedVideoPosterData = await Self.generatePosterFrame(videoData: data)
            }
        }
    }

    // MARK: - Media editor ("Media" post type - image gallery OR single video)

    /// Horizontal thumbnail strip with per-image remove buttons and a
    /// "Choose from Photos" row to add more.
    @ViewBuilder
    private var mediaEditor: some View {
        if !selectedImages.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(selectedImages) { image in
                        if let uiImage = PlatformImage(data: image.data) {
                            uiImage.swiftUIImage
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 100, height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(alignment: .topLeading) {
                                    Button {
                                        selectedImages.removeAll { $0.id == image.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                        .accessibilityLabel("Remove Image")
                                    }
                                    .padding(4)
                                }
                        }
                    }
                }
            }
        } else if selectedVideoData != nil, let posterData = selectedVideoPosterData, let uiImage = PlatformImage(data: posterData) {
            ZStack(alignment: .topLeading) {
                uiImage.swiftUIImage
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                Button {
                    self.selectedVideoData = nil
                    self.selectedVideoPosterData = nil
                    self.selectedVideoItem = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white, .black.opacity(0.6))
                    .accessibilityLabel("Remove Video")
                }
                .padding(4)
            }
        } else if isLoadingVideo {
            ProgressView("Processing video…")
        }

        if selectedVideoData == nil && selectedImages.count < Self.maxMediaImages {
            PhotosPicker(
                selection: $selectedPhotoItems,
                maxSelectionCount: Self.maxMediaImages - selectedImages.count,
                matching: .images
            ) {
                Label("Choose from Photos", systemImage: "camera")
            }
        }
        if selectedImages.isEmpty && selectedVideoData == nil {
            PhotosPicker(selection: $selectedVideoItem, matching: .videos) {
                Label("Choose Video", systemImage: "video")
            }
        }
    }

    private var pollDurationLabel: String {
        "Duration: \(pollDurationDays) \(pollDurationDays == 1 ? "Day" : "Days")"
    }

    @ViewBuilder
    private var postingInRow: some View {
        HStack(spacing: 4) {
            Text("Posting in \(subreddit).")
                .foregroundStyle(.secondary)
            if !subredditRules.isEmpty {
                SettingsLink("View Rules") {
                    SubredditRulesScreen(subredditName: subreddit, repository: repository)
                }
            }
        }
        .font(.caption)
    }

    private var canSubmit: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if postType == .media { return !selectedImages.isEmpty || selectedVideoData != nil }
        if postType == .poll {
            let filled = pollOptionTexts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return filled.count >= PollComposeService.minOptions
        }
        return true
    }

    /// Per-option text fields plus Add/Remove Option rows (2-6 options).
    @ViewBuilder
    private var pollOptionsEditor: some View {
        ForEach(pollOptionTexts.indices, id: \.self) { index in
            HStack {
                TextField("Option \(index + 1)", text: $pollOptionTexts[index])
                    .accessibilityIdentifier("compose.poll.option.\(index)")
                if pollOptionTexts.count > PollComposeService.minOptions {
                    Button {
                        pollOptionTexts.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                        .accessibilityLabel("Remove Option")
                    }
                }
            }
        }
        if pollOptionTexts.count < PollComposeService.maxOptions {
            Button {
                pollOptionTexts.append("")
            } label: {
                Label("Add Option", systemImage: "plus.circle")
            }
            .accessibilityIdentifier("compose.poll.addOption")
        }
    }

    private func loadFlairs() async {
        flairOptions = (try? await repository.fetchFlairOptions(subreddit: subreddit)) ?? []
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            switch postType {
            case .media:
                if let selectedVideoData {
                    guard let posterData = selectedVideoPosterData else {
                        errorMessage = "Couldn't generate a video thumbnail."
                        return
                    }
                    try await repository.submitVideoPost(
                        subreddit: subreddit,
                        title: title,
                        videoData: selectedVideoData,
                        videoFilename: "upload.mp4",
                        videoMimeType: "video/mp4",
                        posterData: posterData,
                        flairID: selectedFlair?.id
                    )
                } else if selectedImages.count == 1 {
                    try await submitSingleImage(selectedImages[0].data)
                } else if selectedImages.count >= 2 {
                    try await repository.submitGalleryPost(
                        subreddit: subreddit,
                        title: title,
                        images: selectedImages.map { (data: $0.data, filename: "upload.jpg", mimeType: "image/jpeg") },
                        flairID: selectedFlair?.id
                    )
                } else {
                    return
                }
            case .poll:
                try await repository.submitPoll(
                    subreddit: subreddit,
                    title: title,
                    options: pollOptionTexts,
                    durationDays: pollDurationDays,
                    flairID: selectedFlair?.id,
                    flairText: selectedFlair?.text
                )
            default:
                try await repository.submitPost(
                    subreddit: subreddit,
                    title: title,
                    selftext: postType == .link ? nil : (selftextBody.isEmpty ? nil : selftextBody),
                    url: postType == .link ? linkURL : nil,
                    flairID: selectedFlair?.id
                )
            }
            onSubmitted()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    /// `GeneralSettings.mediaUploadHost` ("Media Upload Host"): `.reddit`
    /// uploads natively and submits `kind=image` (`submitImagePost`);
    /// `.imgur`/`.imgChest` upload to that host and submit a link post to
    /// the hosted image.
    private func submitSingleImage(_ data: Data) async throws {
        switch generalSettings.mediaUploadHost {
        case .reddit:
            try await repository.submitImagePost(
                subreddit: subreddit,
                title: title,
                fileData: data,
                filename: "upload.jpg",
                mimeType: "image/jpeg",
                kind: .image,
                flairID: selectedFlair?.id
            )
        case .imgur:
            let image = try await ImgurClient.uploadImage(data: data)
            try await repository.submitPost(subreddit: subreddit, title: title, selftext: nil, url: image.link, flairID: selectedFlair?.id)
        case .imgChest:
            let image = try await ImgChestClient.uploadImage(data: data)
            try await repository.submitPost(subreddit: subreddit, title: title, selftext: nil, url: image.link, flairID: selectedFlair?.id)
        }
    }

    /// Extracts a JPEG poster frame via `AVAssetImageGenerator`, needed as
    /// `video_poster_url` by `submitVideoPost`. The video is written to a
    /// temp file first because `AVAsset` needs a file URL.
    private static func generatePosterFrame(videoData: Data) async -> Data? {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        do {
            try videoData.write(to: tempURL)
        } catch {
            return nil
        }
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let asset = AVURLAsset(url: tempURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        do {
            let cgImage = try await generator.image(at: .zero).image
            #if canImport(UIKit)
            let uiImage = UIImage(cgImage: cgImage)
            return uiImage.jpegData(compressionQuality: 0.85)
            #elseif canImport(AppKit)
            let nsImage = NSImage(cgImage: cgImage, size: .zero)
            guard let tiffData = nsImage.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
            return bitmap.representation(using: .jpeg, properties: [:])
            #else
            return nil
            #endif
        } catch {
            return nil
        }
    }
}

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
