import SwiftUI
import PhoebusCore

/// A user's mod notes in one subreddit: hand-written notes and the mod
/// actions Reddit records against them, filterable by type, with an Add
/// Note sheet and swipe to delete.
public struct ModNotesScreen: View {
    let subreddit: String
    let user: String
    let repository: RedditRepository
    /// Fullname of the post or comment the screen was opened from; new notes attach to it.
    let attachTo: String?

    @State private var notes: [ModNote] = []
    @State private var filter: ModNoteFilter = .all
    @State private var nextCursor: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingAdd = false

    public init(subreddit: String, user: String, repository: RedditRepository, attachTo: String? = nil) {
        self.subreddit = subreddit
        self.user = user
        self.repository = repository
        self.attachTo = attachTo
    }

    public var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            ForEach(notes) { note in
                ModNoteRow(note: note, subreddit: subreddit, repository: repository)
                    .swipeActions {
                        if note.isDeletable {
                            Button("Delete", role: .destructive) { Task { await delete(note) } }
                        }
                    }
                    .onAppear {
                        if note.id == notes.last?.id { Task { await loadMore() } }
                    }
            }
            if isLoading {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .overlay {
            if notes.isEmpty && errorMessage == nil && !isLoading {
                Text("No mod notes yet.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .apolloFlatListAppearance()
        .navigationTitle("u/\(user)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: {
                    Image(systemName: "plus").accessibilityLabel("Add Note")
                }
                .accessibilityIdentifier("modNotes.add")
            }
            ToolbarItem(placement: .secondaryAction) {
                Picker("Filter", selection: $filter) {
                    ForEach(ModNoteFilter.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("modNotes.filter")
            }
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack {
                AddModNoteSheet(subreddit: subreddit, user: user, repository: repository, attachTo: attachTo) { created in
                    showingAdd = false
                    if let created, filter == .all || filter == .note { notes.insert(created, at: 0) }
                }
            }
        }
        .task(id: filter) { await reload() }
    }

    private func reload() async {
        notes = []
        nextCursor = nil
        errorMessage = nil
        await fetch(before: nil)
    }

    private func loadMore() async {
        guard nextCursor != nil, !isLoading else { return }
        await fetch(before: nextCursor)
    }

    private func fetch(before: String?) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await repository.fetchModNotes(subreddit: subreddit, user: user, filter: filter, before: before)
            notes += page.notes
            nextCursor = page.nextCursor
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    private func delete(_ note: ModNote) async {
        do {
            try await repository.deleteModNote(subreddit: subreddit, user: user, noteID: note.id)
            notes.removeAll { $0.id == note.id }
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}

/// One row: type and label chips, the note or action text, operator, relative date.
private struct ModNoteRow: View {
    let note: ModNote
    let subreddit: String
    let repository: RedditRepository

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                chip(note.type == .unknown ? "Other" : note.type.title, color: .secondary)
                if let label = note.label {
                    chip(label.title, color: Color(hex: label.colorHex))
                }
                Spacer()
                Text(note.created, style: .relative).font(.caption2).foregroundStyle(.secondary)
            }
            if let text = bodyText {
                Text(text).font(.subheadline)
            }
            HStack {
                Text("u/\(note.operator)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let redditID = note.redditID {
                    Button { openLinkedItem(redditID) } label: {
                        Label(redditID.hasPrefix("t1_") ? "Comment" : "Post", systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("modNotes.openLinked")
                }
            }
        }
    }

    private var bodyText: String? {
        let text = note.note ?? [note.actionDescription, note.details, note.action]
            .compactMap { $0 }.first { !$0.isEmpty }
        return text?.isEmpty == false ? text : nil
    }

    private func chip(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    private func openLinkedItem(_ redditID: String) {
        Task {
            if let target = await repository.modNoteTarget(redditID: redditID, subreddit: subreddit) {
                RedditLinkNavigator.open(target)
            }
        }
    }
}

/// Add-note sheet: label picker, text with a 250-character counter.
struct AddModNoteSheet: View {
    let subreddit: String
    let user: String
    let repository: RedditRepository
    let attachTo: String?
    let onDone: (ModNote?) -> Void

    @State private var text = ""
    @State private var label: ModNoteLabel?
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            Section {
                Picker("Label", selection: $label) {
                    Text("None").tag(ModNoteLabel?.none)
                    ForEach(ModNoteLabel.allCases, id: \.self) { Text($0.title).tag(ModNoteLabel?.some($0)) }
                }
                .accessibilityIdentifier("modNotes.label")
            }
            Section {
                TextField("Note", text: $text, axis: .vertical)
                    .lineLimit(3...8)
                    .accessibilityIdentifier("modNotes.text")
            } footer: {
                Text("\(text.count)/\(ModNoteRequest.characterLimit)")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .foregroundStyle(text.count > ModNoteRequest.characterLimit ? .red : .secondary)
                    .accessibilityIdentifier("modNotes.counter")
            }
        }
        .navigationTitle("Add Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onDone(nil) }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await submit() } }
                    .disabled(isSubmitting || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || text.count > ModNoteRequest.characterLimit)
                    .accessibilityIdentifier("modNotes.save")
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let created = try await repository.addModNote(subreddit: subreddit, user: user, note: text,
                                                          label: label, redditID: attachTo)
            onDone(created)
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}

/// A navigation-wrapped Mod Notes screen for presenting as a sheet from a menu.
public struct ModNotesSheet: View {
    let subreddit: String
    let user: String
    let repository: RedditRepository
    let attachTo: String?
    @Environment(\.dismiss) private var dismiss

    public init(subreddit: String, user: String, repository: RedditRepository, attachTo: String? = nil) {
        self.subreddit = subreddit
        self.user = user
        self.repository = repository
        self.attachTo = attachTo
    }

    public var body: some View {
        NavigationStack {
            ModNotesScreen(subreddit: subreddit, user: user, repository: repository, attachTo: attachTo)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                }
        }
    }
}
