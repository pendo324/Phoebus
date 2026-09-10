import SwiftUI
import PhotosUI
import PhoebusCore

/// Apollo's comment composer: a full-screen modal with a nav bar reading Cancel
/// / "New Comment" / Post, a full-height markdown editor, the docked
/// quoted-parent band, and the Quick Bar pinned above the keyboard.
public struct CommentComposerScreen: View {
    @Setting(GeneralSettings.self) private var generalSettings
    let parentFullname: String
    let repository: RedditRepository
    /// The comment being replied to, shown in the docked band above the Quick Bar.
    var quotedPreview: (author: String, snippet: String, age: String?)?
    var initialText: String = ""
    /// The thread's subreddit, for Prefer Native Images' per-subreddit
    /// check. nil = unknown, which uses the link host.
    var subreddit: String?
    let onSubmitted: () -> Void
    /// The posted comment as Reddit returned it, so the thread can
    /// insert it in place (Reborn #1196) instead of reloading.
    let onPosted: ((RedditComment) -> Void)?

    @State private var text = ""
    @StateObject private var editor = MarkdownEditorController(locksFocus: true)
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    // MARK: - "Comment Link Host" wiring
    //
    // `GeneralSettings.commentLinkHost` and `commentLinkPreferNative` ("Prefer
    // Native Images") drive the Quick Bar's "Add photos" button (`onAddPhoto`):
    // picking a photo uploads it to the configured host (Imgur/Image Chest) and
    // inserts a markdown image link into the comment body. "Prefer Native Images"
    // uploads to Reddit natively wherever the subreddit allows image comments (see
    // `NativeCommentImages`) and uses the link host otherwise.
    @State private var showingPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isUploadingPhoto = false
    /// Assets uploaded natively in this composer; only these become
    /// RTJSON image blocks on submit.
    @State private var nativeAssetIDs: Set<String> = []

    public init(
        parentFullname: String,
        repository: RedditRepository,
        quotedPreview: (author: String, snippet: String, age: String?)? = nil,
        initialText: String = "",
        subreddit: String? = nil,
        onSubmitted: @escaping () -> Void,
        onPosted: ((RedditComment) -> Void)? = nil
    ) {
        self.subreddit = subreddit
        self.parentFullname = parentFullname
        self.repository = repository
        self.quotedPreview = quotedPreview
        self.initialText = initialText
        self.onSubmitted = onSubmitted
        self.onPosted = onPosted
    }

    public var body: some View {
        crashTrackedBody.onAppear { CrashRecorder.record(.openedComposer) }
    }

    @ViewBuilder private var crashTrackedBody: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }

                // Full-height editor, not a 2-4 line inline field.
                MarkdownComposerField(text: $text, placeholder: "", fillsAvailableSpace: true, editor: editor,
                                      onAddPhoto: addPhotoTapped)
                    .padding(.horizontal, 16)
                    .frame(maxHeight: .infinity)
                    .accessibilityIdentifier("commentComposer.field")
                    .overlay(alignment: .bottom) {
                        if isUploadingPhoto {
                            ProgressView("Uploading image…")
                                .padding(8)
                                .background(.thinMaterial, in: Capsule())
                        }
                    }

                if let quotedPreview {
                    // Flat edge-to-edge gray band with "↳ author"
                    // and a right-aligned relative age.
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("↳ \(quotedPreview.author)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let age = quotedPreview.age {
                                Text(age)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(quotedPreview.snippet)
                            .font(.subheadline)
                            .lineLimit(3)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.15))
                }
            }
            // Apollo's composer sits on the app's own page colour (black
            // under Pure Black), not the sheet's grey.
            .background(ComposerBackground().ignoresSafeArea())
            .navigationTitle("New Comment")
            .navigationBarTitleDisplayModeIfAvailable()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editor.release(); dismiss() }
                        .accessibilityIdentifier("commentComposer.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("Post") { Task { await submit() } }
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            // Apollo's "Submit" key command (Command-Return).
                            .keyboardShortcut(.return, modifiers: .command)
                            .accessibilityIdentifier("commentComposer.post")
                    }
                }
            }
            .onAppear { if text.isEmpty { text = initialText } }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: showingPhotoPicker) { _, shown in if !shown { editor.presenting(false) } }
            .onChange(of: selectedPhotoItem) { _, newValue in
                guard let newValue else { return }
                Task {
                    await uploadAndInsertPhoto(newValue)
                    selectedPhotoItem = nil
                }
            }
        }
    }

    /// "Comment Link Host": Off (the default) means no link host, so comment
    /// images upload to Reddit natively, as Apollo's own; Imgur or Image
    /// Chest insert a plain link instead, except where Prefer Native Images
    /// finds the subreddit allows images.
    private func addPhotoTapped() {
        editor.presenting(true)
        showingPhotoPicker = true
    }

    private func uploadAndInsertPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        isUploadingPhoto = true
        defer { isUploadingPhoto = false }
        do {
            let settings = generalSettings
            var native = settings.commentLinkHost == .off
            // Reborn Auto mode: native only where the subreddit is
            // KNOWN to allow image comments.
            if !native, settings.commentLinkPreferNative, let subreddit,
               await repository.subredditAllowsImageComments(subreddit) == true {
                native = true
            }
            if native {
                let (upload, type) = webSafeImage(data)
                let uploaded = try await repository.uploadCommentImage(
                    fileData: upload, filename: "apollo-upload.\(type.fileExtension)", mimeType: type.mimeType)
                nativeAssetIDs.insert(uploaded.assetID)
                text += text.isEmpty ? uploaded.url : "\n\(uploaded.url)"
                return
            }
            let link: String
            switch settings.commentLinkHost {
            case .off:
                return
            case .imgur:
                link = try await ImgurClient.uploadImage(data: data).link
            case .imgChest:
                link = try await ImgChestClient.uploadImage(data: data).link
            }
            text += text.isEmpty ? "![img](\(link))" : "\n![img](\(link))"
        } catch {
            errorMessage = "Couldn't upload image: \(error.localizedDescription)"
        }
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let response = try await repository.submitComment(parentFullname: parentFullname, text: text, nativeImageAssetIDs: nativeAssetIDs)
            if let onPosted, let posted = PostedCommentResponse.comment(from: response) {
                onPosted(posted)
            } else {
                onSubmitted()
            }
            editor.release()
            dismiss()
        } catch {
            // Presents the "Sign In to Reply" alert for a signed-out
            // reply, instead of surfacing the raw thrown error.
            if SignInRequiredPresenter.shared.presentIfNotAuthenticated(error, action: .reply) {
                return
            }
            let failure = await repository.explainCommentFailure(error, parentFullname: parentFullname)
            errorMessage = "\(failure.title): \(failure.message)"
        }
    }
}

/// The page colour behind the composer: the theme's background, the Pure
/// Black tier's page in dark mode, else the system's.
private struct ComposerBackground: View {
    @Environment(\.apolloTheme) private var apolloTheme
    @Environment(\.colorScheme) private var colorScheme
    @Setting(PureBlackSettingsStore.storage) private var pureBlack

    var body: some View {
        if let themed = apolloTheme.color(.background) {
            themed
        } else if colorScheme == .dark {
            Color(hex: pureBlack.darkPageHex)
        } else {
            Color(.systemBackground)
        }
    }
}
