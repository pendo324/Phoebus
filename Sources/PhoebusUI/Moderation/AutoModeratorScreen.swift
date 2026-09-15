import SwiftUI
import PhoebusCore

/// A raw text editor for a subreddit's AutoModerator YAML configuration, stored
/// as a wiki page (`config/automoderator`). Like Apollo, a plain editable text
/// view rather than a structured rule builder, since most moderators edit the
/// YAML directly.
public struct AutoModeratorScreen: View {
    let subreddit: String
    let repository: RedditRepository

    @State private var content = ""
    @State private var originalContent = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var notConfigured = false

    public init(subreddit: String, repository: RedditRepository) {
        self.subreddit = subreddit
        self.repository = repository
    }

    public var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if notConfigured {
                // Apollo's title is "AutoMod Not Configured", with a message framed as an
                // offer rather than an instruction.
                ContentUnavailableViewIfAvailable(
                    title: "AutoMod Not Configured",
                    message: "AutoModerator has yet to be configured for the \(subreddit) subreddit. Would you like Phoebus to automatically set it up so you can begin editing?",
                    systemImage: "shield.slash"
                )
                editor
            } else {
                editor
            }
        }
        .navigationTitle("AutoModerator")
        .toolbar {
            // Help button (`questionmark.circle`) linking to Reddit's AutoModerator wiki
            // documentation. Apollo's "AutoModerator is all set up..." string tells the
            // user to "select the ? icon in the navigation bar".
            ToolbarItem(placement: .navigationBarTrailing) {
                Link(destination: URL(string: "https://reddit.com/wiki/automoderator/full-documentation")!) {
                    Image(systemName: "questionmark.circle")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Save") {
                    Task { await save() }
                }
                .disabled(isSaving || content == originalContent)
            }
        }
        .task { await load() }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red).padding()
            }
            TextEditor(text: $content)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                #if canImport(UIKit)
                .textInputAutocapitalization(.never)
                #endif
                .padding(4)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            content = try await repository.fetchAutoModeratorConfig(subreddit: subreddit)
            originalContent = content
        } catch {
            // A missing wiki page (404) means AutoModerator has never
            // been configured for this subreddit, a normal, common
            // state, not an error.
            notConfigured = true
            content = ""
            originalContent = ""
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.saveAutoModeratorConfig(subreddit: subreddit, content: content)
            originalContent = content
            notConfigured = false
        } catch {
            errorMessage = "Couldn't save: \(UserFacingError.text(for: error))"
        }
    }
}
