import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import PhotosUI
#endif

/// Identifiable wrapper so a URL can drive `.sheet(item:)`. A `Bool` plus a
/// separate stored URL can desynchronise; one item binding carries its own
/// payload.
public struct ShareableURL: Identifiable {
    public let url: URL
    public var id: String { url.absoluteString }

    public init(_ url: URL) {
        self.url = url
    }
}

/// "Edit Multireddit", reachable from a multireddit feed's "•••" menu.
///
/// Fetches the multireddit by path, since a feed only knows its own path. That
/// also gives the current description, which is round-tripped as Reborn does.
public struct MultiredditEditSheet: View {
    let path: String
    let repository: RedditRepository
    let onDone: () -> Void

    @State private var multireddit: RedditMultireddit?
    @State private var displayName = ""
    @State private var descriptionMarkdown = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    #if canImport(UIKit)
    @ObservedObject private var customArt = SubredditCustomArtStore.shared
    @State private var showingIconPicker = false
    @State private var pickedIcon: PhotosPickerItem?
    #endif

    public init(path: String, repository: RedditRepository, onDone: @escaping () -> Void) {
        self.path = path
        self.repository = repository
        self.onDone = onDone
    }

    public var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ApolloLoadingCell()
                } else {
                    Section("Name") {
                        TextField("Display Name", text: $displayName)
                            .accessibilityIdentifier("multiredditEdit.name")
                    }
                    Section("Description") {
                        TextEditor(text: $descriptionMarkdown)
                            .frame(minHeight: 100)
                            .accessibilityIdentifier("multiredditEdit.description")
                    }
                    #if canImport(UIKit)
                    // Reborn "Choose Icon" / "Remove Icon" in the editor.
                    Section("Icon") {
                        Button(customArt.has(multiredditIconKey(path: path), kind: .icon) ? "Change Icon" : "Choose Icon") {
                            showingIconPicker = true
                        }
                        .accessibilityIdentifier("multiredditEdit.chooseIcon")
                        if customArt.has(multiredditIconKey(path: path), kind: .icon) {
                            Button("Remove Icon", role: .destructive) {
                                customArt.remove(multiredditIconKey(path: path), kind: .icon)
                            }
                        }
                    }
                    #endif
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .apolloFlatListAppearance()
            .navigationTitle("Edit Multireddit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDone() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving || isLoading
                                  || displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("multiredditEdit.save")
                }
            }
            .task { await load() }
            #if canImport(UIKit)
            .photosPicker(isPresented: $showingIconPicker, selection: $pickedIcon, matching: .images)
            .onChange(of: pickedIcon) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        customArt.save(image, for: multiredditIconKey(path: path), kind: .icon)
                    }
                    pickedIcon = nil
                }
            }
            #endif
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let all = try await repository.fetchMultireddits()
            guard let match = all.first(where: { $0.path == path }) else {
                errorMessage = "Couldn't find this multireddit."
                return
            }
            multireddit = match
            displayName = match.displayName
            // The current description, not an empty box: `updateMultireddit` PUTs a full
            // model.
            descriptionMarkdown = match.descriptionMarkdown ?? ""
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    private func save() async {
        guard let multireddit else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.updateMultireddit(
                path: multireddit.path,
                displayName: displayName,
                descriptionMarkdown: descriptionMarkdown,
                // Preserved, not rewritten: `updateMultireddit` PUTs a full model, so omitting
                // these would empty the multireddit on rename.
                subredditNames: multireddit.subreddits.map(\.name)
            )
            onDone()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}

/// `.sheet(item:)` payload for the feed's Edit Multireddit row. `String` is not
/// `Identifiable`; see `ShareableURL`.
public struct EditingMultireddit: Identifiable {
    public let path: String
    public var id: String { path }

    public init(path: String) {
        self.path = path
    }
}
