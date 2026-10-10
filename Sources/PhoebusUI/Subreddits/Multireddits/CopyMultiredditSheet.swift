import SwiftUI
import PhoebusCore

/// "Copy to My Multireddits", from someone else's multireddit feed "•••" menu.
/// Not in Apollo or Reborn. The name rules and request live in `MultiredditCopy`.
public struct CopyMultiredditSheet: View {
    let sourcePath: String
    let username: String
    let repository: RedditRepository
    let onCancel: () -> Void
    let onCopied: (CopiedMultireddit) -> Void

    @State private var displayName: String
    @State private var existingPaths: [String] = []
    @State private var isCopying = false
    @State private var errorMessage: String?

    public init(sourcePath: String, sourceDisplayName: String, username: String, repository: RedditRepository,
                onCancel: @escaping () -> Void, onCopied: @escaping (CopiedMultireddit) -> Void) {
        self.sourcePath = sourcePath
        self.username = username
        self.repository = repository
        self.onCancel = onCancel
        self.onCopied = onCopied
        _displayName = State(initialValue: sourceDisplayName)
    }

    private var problem: MultiredditCopy.NameProblem? {
        MultiredditCopy.problem(with: displayName)
    }

    private var destinationPath: String {
        MultiredditCopy.destinationPath(displayName: displayName, username: username, existingPaths: existingPaths)
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Multireddit name", text: $displayName)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("copyMultireddit.name")
                } header: {
                    Text("Name")
                        .apolloSectionHeader()
                } footer: {
                    Text(problem?.message ?? "Copies \(sourcePath) to \(destinationPath).")
                        .apolloSectionFooter()
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .apolloFlatListAppearance()
            .navigationTitle("Copy Multireddit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                        .accessibilityIdentifier("copyMultireddit.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Copy") { Task { await copy() } }
                        .disabled(isCopying || problem != nil)
                        .accessibilityIdentifier("copyMultireddit.copy")
                }
            }
            // Numbers the path past the user's existing multireddits instead of
            // letting Reddit refuse it.
            .task { existingPaths = ((try? await repository.fetchMultireddits()) ?? []).map(\.path) }
        }
        .accessibilityIdentifier("copyMultireddit.screen")
    }

    private func copy() async {
        isCopying = true
        defer { isCopying = false }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = destinationPath
        do {
            let copy = try await repository.copyMultireddit(sourcePath: sourcePath, destinationPath: path, displayName: name)
            // The Subreddits list reads its multireddits from this cache.
            await SubscribedSubredditsCache.shared.invalidate()
            onCopied(CopiedMultireddit(path: copy?.path ?? path, displayName: copy?.displayName ?? name))
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}

/// The copy just made, for the confirmation and its Open button. Its own type so
/// its `.navigationDestination(item:)` cannot collide with another on the stack.
public struct CopiedMultireddit: Identifiable, Hashable, Sendable {
    public let path: String
    public let displayName: String
    public var id: String { path }
}
