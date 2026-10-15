import SwiftUI
import PhoebusCore

/// The user's own tag on `username`, as a small pill after the name, or
/// nothing when they have none. Phoebus-only user tags (`UserTags`): every
/// pill shares one in-memory copy of the tags, so a row costs a dictionary
/// lookup and visible rows update when a tag changes.
struct UserTagPill: View {
    let username: String
    /// Space before the pill, for bylines laid out with no HStack spacing.
    var leadingPadding: CGFloat = 0
    @Setting(UserTags.self) private var tags

    var body: some View {
        if let tag = tags.tag(for: username) {
            UserTagLabel(text: tag.text, color: tag.color)
                .padding(.leading, leadingPadding)
                // Below a name's -1, so a long tag truncates before the username.
                .layoutPriority(-2)
                .accessibilityLabel("Tag: \(tag.text)")
        }
    }
}

/// The pill itself, styled like the comment header's OP badge.
struct UserTagLabel: View {
    let text: String
    let color: UserTagColor

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color(hex: color.hex)))
    }
}

/// The menu item that opens the tag editor: "Tag User…", or "Edit Tag…"
/// when the user already has a tag. Reads the shared tags itself so the
/// label is current even when the hosting row's body hasn't re-run.
struct UserTagMenuItem: View {
    let username: String
    let action: () -> Void
    @Setting(UserTags.self) private var tags

    var body: some View {
        Button(action: action) {
            Label(tags.tag(for: username) == nil ? "Tag User…" : "Edit Tag…", systemImage: "tag")
        }
    }
}

/// A user whose tag is being edited, for `sheet(item:)` on screens that
/// list many authors.
struct UserTagTarget: Identifiable {
    let username: String
    var id: String { username.lowercased() }
}

extension View {
    /// Presents the tag editor for `username` ("Tag User…" in the profile,
    /// comment and post-header menus).
    func userTagEditor(isPresented: Binding<Bool>, username: String) -> some View {
        sheet(isPresented: isPresented) {
            UserTagEditorSheet(username: username)
        }
    }

    /// The same editor for whichever author a list's menu picked.
    func userTagEditor(target: Binding<UserTagTarget?>) -> some View {
        sheet(item: target) { target in
            UserTagEditorSheet(username: target.username)
        }
    }
}

/// "Tag User…": the tag's text (up to `UserTags.maxLength` characters), a
/// colour from the palette, and Remove Tag for an existing one. With an
/// empty `username` (Settings → User Tags → Add Tag…) it asks for the user.
struct UserTagEditorSheet: View {
    let username: String
    @Environment(\.dismiss) private var dismiss
    @Setting(UserTags.self) private var tags
    @State private var name: String
    @State private var text: String
    @State private var color: UserTagColor
    @FocusState private var textFocused: Bool

    init(username: String) {
        self.username = username
        let existing = UserTagStore.tag(for: username)
        _name = State(initialValue: username)
        _text = State(initialValue: existing?.text ?? "")
        _color = State(initialValue: existing?.color ?? .blue)
    }

    private var existing: UserTag? { username.isEmpty ? nil : tags.tag(for: username) }
    private var cleanedName: String { UserTags.normalizedUsername(name) }
    private var cleanedText: String { UserTags.normalizedText(text) }

    var body: some View {
        NavigationStack {
            List {
                if username.isEmpty {
                    Section {
                        TextField("Username", text: $name)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("userTag.username")
                            .apolloPlainSettingsRowInsets()
                    } header: {
                        Text("User").apolloSectionHeader()
                    }
                }
                Section {
                    TextField("Tag", text: $text)
                        .focused($textFocused)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .onChange(of: text) { _, value in
                            if value.count > UserTags.maxLength { text = String(value.prefix(UserTags.maxLength)) }
                        }
                        .accessibilityIdentifier("userTag.text")
                        .apolloPlainSettingsRowInsets(rule: false)
                } header: {
                    Text("Tag").apolloSectionHeader()
                } footer: {
                    Text("Only you see this tag. It's kept on this device and shown after this user's name in comments, posts and the inbox.")
                        .apolloSectionFooter()
                }
                Section {
                    HStack(spacing: 0) {
                        ForEach(UserTagColor.allCases) { option in
                            Button { color = option } label: {
                                Circle()
                                    .fill(Color(hex: option.hex))
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        if option == color {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.displayName)
                            .accessibilityAddTraits(option == color ? .isSelected : [])
                            .accessibilityIdentifier("userTag.color.\(option.rawValue)")
                        }
                    }
                    .padding(.vertical, 6)
                    .apolloPlainSettingsRowInsets(rule: !cleanedText.isEmpty)
                    if !cleanedText.isEmpty {
                        HStack(spacing: 6) {
                            Text(cleanedName.isEmpty ? "username" : cleanedName)
                                .font(.system(size: 15, weight: .medium))
                            UserTagLabel(text: cleanedText, color: color)
                        }
                        .accessibilityIdentifier("userTag.preview")
                        .apolloPlainSettingsRowInsets(rule: false)
                    }
                } header: {
                    Text("Colour").apolloSectionHeader()
                }
                if existing != nil {
                    Section {
                        Button("Remove Tag", role: .destructive) {
                            UserTagStore.removeTag(for: username)
                            dismiss()
                        }
                        .accessibilityIdentifier("userTag.remove")
                        .apolloPlainSettingsRowInsets(rule: false)
                    }
                }
            }
            .apolloSettingsListAppearance()
            .navigationTitle(username.isEmpty ? "Add Tag" : "Tag u/\(username)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("userTag.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(cleanedName.isEmpty || (cleanedText.isEmpty && existing == nil))
                        .accessibilityIdentifier("userTag.save")
                }
            }
            .onAppear { if !username.isEmpty { textFocused = true } }
        }
        .accessibilityIdentifier("userTag.editor")
    }

    /// Saving empty text removes the tag, as Remove Tag does.
    private func save() {
        guard !cleanedName.isEmpty else { return }
        UserTagStore.setTag(cleanedText, color: color, for: cleanedName)
        dismiss()
    }
}

/// Settings → Filters → User Tags: every tag, alphabetical. Tap to
/// edit, swipe to delete, "Add Tag…" to tag someone by name.
struct UserTagsSettingsScreen: View {
    @Setting(UserTags.self) private var tags
    @State private var editing: EditTarget?

    private struct EditTarget: Identifiable {
        let username: String
        var id: String { username.isEmpty ? "+new" : username.lowercased() }
    }

    var body: some View {
        let sorted = tags.sorted
        List {
            Section {
                if sorted.isEmpty {
                    Text("No tagged users.").foregroundStyle(.secondary)
                        .apolloPlainSettingsRowInsets()
                }
                ForEach(sorted) { tag in
                    Button { editing = EditTarget(username: tag.username) } label: {
                        HStack(spacing: 8) {
                            Text(tag.username)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            UserTagLabel(text: tag.text, color: tag.color)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .apolloPlainSettingsRowInsets()
                    .accessibilityIdentifier("userTags.row.\(tag.id)")
                }
                .onDelete { offsets in
                    let names = offsets.map { sorted[$0].username }
                    $tags.update { all in names.forEach { all.removeTag(for: $0) } }
                }
                Button("Add Tag…") { editing = EditTarget(username: "") }
                    .foregroundStyle(Color.apolloAccent)
                    .apolloPlainSettingsRowInsets(rule: false)
                    .accessibilityIdentifier("userTags.add")
            } footer: {
                Text("Your own labels on Reddit users, shown after their names. Kept on this device and included in backups.")
                    .apolloSectionFooter()
            }
        }
        .apolloSettingsListAppearance()
        .navigationTitle("User Tags")
        .accessibilityIdentifier("userTags.screen")
        .sheet(item: $editing) { target in
            UserTagEditorSheet(username: target.username)
        }
    }
}
