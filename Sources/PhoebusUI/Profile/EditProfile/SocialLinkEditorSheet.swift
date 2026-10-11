import SwiftUI
import PhoebusCore

/// Adds or edits one social link: the platform, then its username, or the text
/// and address of a platform that takes those. Hands the finished draft back; Edit Profile
/// stages it until Save.
struct SocialLinkEditorSheet: View {
    @State private var draft: SocialLinkDraft
    let platforms: [ProfileSocialPlatform]
    let isNew: Bool
    let onDone: (SocialLinkDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showsIssues = false

    init(draft: SocialLinkDraft, platforms: [ProfileSocialPlatform], isNew: Bool, onDone: @escaping (SocialLinkDraft) -> Void) {
        _draft = State(initialValue: draft)
        self.platforms = platforms
        self.isNew = isNew
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Platform", selection: $draft.platform) {
                        ForEach(platforms) { platform in
                            Label(platform.displayName, systemImage: platform.systemImageName).tag(platform)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .apolloPlainSettingsRowInsets(rule: false)
                    .accessibilityIdentifier("socialLink.platform")
                }
                Section {
                    if draft.platform.takesURL {
                        TextField("Display Text", text: $draft.title)
                            .submitLabel(.next)
                            .apolloPlainSettingsRowInsets()
                            .accessibilityIdentifier("socialLink.title")
                        TextField("https://example.com", text: $draft.url)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .apolloPlainSettingsRowInsets(rule: false)
                            .accessibilityIdentifier("socialLink.url")
                    } else {
                        TextField("Username", text: $draft.handle)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .apolloPlainSettingsRowInsets(rule: false)
                            .accessibilityIdentifier("socialLink.handle")
                    }
                } header: {
                    Text(draft.platform.takesURL ? "Link" : "Username").apolloSectionHeader()
                } footer: {
                    if showsIssues, let issue = draft.issues.first {
                        Text(issue.message).apolloSectionFooter()
                    } else if !draft.platform.takesURL {
                        Text("Just the username, without @ or a link.").apolloSectionFooter()
                    }
                }
            }
            .apolloSettingsListAppearance()
            .navigationTitle(isNew ? "Add Social Link" : "Edit Social Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("socialLink.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Done") {
                        guard draft.isValid else {
                            showsIssues = true
                            return
                        }
                        onDone(draft)
                        dismiss()
                    }
                    .accessibilityIdentifier("socialLink.done")
                }
            }
        }
    }
}
