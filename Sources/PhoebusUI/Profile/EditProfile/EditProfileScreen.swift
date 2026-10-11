import SwiftUI
import PhotosUI
import PhoebusCore

/// Edit Profile, pushed from your own profile's "•••" menu: banner, display
/// name, about text, the follower and NSFW switches and social links. The avatar
/// is changed on reddit.com's profile settings, shown signed in
/// (`ProfileAvatarWebScreen`). Phoebus's own design; Reborn opens reddit.com's
/// profile settings instead.
struct EditProfileScreen: View {
    let username: String
    let repository: RedditRepository
    /// The profile as shown, for the current avatar and banner.
    let user: RedditUser?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accountManager) private var accountManager

    @State private var settings: ProfileSettings?
    @State private var edits = ProfileEdits(displayName: "", about: "", isNSFW: false, acceptsFollowers: true)
    @State private var isLoading = true
    @State private var loadFailure: String?
    @State private var bannerChange = ImageChange.none
    @State private var isSaving = false
    @State private var saveFailure: String?
    @State private var showingDiscard = false
    @State private var choosingBanner = false
    @State private var showingPicker = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var unreadablePhoto = false
    @State private var linksMode = LinksMode.loading
    @State private var socialEdits = SocialLinkEdits()
    @State private var platforms = ProfileSocialPlatform.builtIn
    @State private var linkEditor: LinkEditor?
    @State private var showingWebSignIn = false
    @State private var showingAvatarPage = false
    @State private var askingAvatarSignIn = false
    /// The web sign-in was started for the avatar page, which opens once the
    /// sign-in sheet has gone.
    @State private var openAvatarAfterSignIn = false

    private enum ImageChange {
        case none
        case replace(PreparedProfileImage)
        case remove

        var isNone: Bool {
            if case .none = self { return true }
            return false
        }
    }

    /// Social links are edited through a web session; without one they are
    /// shown as the profile page lists them.
    private enum LinksMode {
        case loading
        case editable
        case needsWebSession([SocialLink])
        case unavailable(String, [SocialLink])
    }

    /// The link sheet's subject: a new link, or the row it replaces.
    private struct LinkEditor: Identifiable {
        let id = UUID()
        let row: SocialLinkEdits.Row?
        let draft: SocialLinkDraft
    }

    private var issues: [ProfileEditIssue] { settings?.issues(for: edits) ?? [] }

    private var isDirty: Bool {
        (settings?.hasChanges(edits) ?? false) || !bannerChange.isNone || socialEdits.hasChanges
    }

    private var canSave: Bool { settings != nil && isDirty && issues.isEmpty && !isSaving }

    var body: some View {
        List {
            if isLoading {
                ApolloLoadingCell()
            } else if let loadFailure {
                loadFailureSection(loadFailure)
            } else {
                imagesSection
                displayNameSection
                aboutSection
                profileSection
                socialLinksSection
            }
            redditSection
        }
        .apolloSettingsListAppearance()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Edit Profile")
        .navigationBarBackButtonHidden(isDirty)
        // A back swipe would drop the edits, so it asks first, as Cancel does.
        .apolloConfirmsDiscard(isDirty: isDirty) {
            if !isSaving { showingDiscard = true }
        }
        .toolbar {
            // A back button that would drop edits becomes Cancel, which asks first.
            if isDirty {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingDiscard = true }
                        .disabled(isSaving)
                        .accessibilityIdentifier("editProfile.cancel")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") { Task { await save() } }
                        .disabled(!canSave)
                        .accessibilityIdentifier("editProfile.save")
                }
            }
        }
        .task { await load() }
        .confirmationDialog("Discard Changes?", isPresented: $showingDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("Your changes to this profile haven't been saved.")
        }
        .confirmationDialog("Banner", isPresented: $choosingBanner, titleVisibility: .hidden) {
            Button("Choose Photo") { showingPicker = true }
            if !bannerChange.isNone {
                Button("Undo Change") { bannerChange = .none }
            } else if currentURL(user?.bannerImage) != nil {
                Button("Remove Banner", role: .destructive) { bannerChange = .remove }
            }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showingPicker, selection: $pickedItem, matching: .images)
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task { await prepare(item) }
        }
        .sheet(item: $linkEditor) { editor in
            SocialLinkEditorSheet(draft: editor.draft, platforms: platforms, isNew: editor.row == nil) { draft in
                if let row = editor.row {
                    socialEdits.replace(row, with: draft)
                } else {
                    socialEdits.add(draft)
                }
            }
        }
        .sheet(isPresented: $showingWebSignIn, onDismiss: {
            if openAvatarAfterSignIn {
                openAvatarAfterSignIn = false
                showingAvatarPage = true
            }
        }) {
            NavigationStack {
                WebSessionLoginScreen(
                    requiredUsername: username,
                    onSuccess: { credential in
                        accountManager?.addWebSessionAccount(credential)
                        showingWebSignIn = false
                        Task { await loadLinks() }
                    },
                    onCancel: {
                        openAvatarAfterSignIn = false
                        showingWebSignIn = false
                    })
            }
        }
        .alert("Reddit Web Sign-In", isPresented: $askingAvatarSignIn) {
            Button("Not Now", role: .cancel) {}
            Button("Open in Safari") { openURL(ProfileEditLinks.webSettings) }
            Button("Continue") {
                openAvatarAfterSignIn = true
                showingWebSignIn = true
            }
        } message: {
            Text("Sign in once as u/\(username) to change your avatar in Phoebus. How you sign in to the app won’t change.")
        }
        .navigationDestination(isPresented: $showingAvatarPage) {
            ProfileAvatarWebScreen(username: username)
        }
        // The avatar may have changed on the page; the profile header and the
        // avatar cache refresh as they do after a save.
        .onChange(of: showingAvatarPage) { _, showing in
            if !showing { onSaved() }
        }
        .alert("Couldn't Save Profile", isPresented: $saveFailure.isPresent()) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveFailure ?? "")
        }
        .alert("Couldn't Use That Photo", isPresented: $unreadablePhoto) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Pick a different photo.")
        }
    }

    // MARK: Sections

    private var imagesSection: some View {
        Section {
            avatarRow
            bannerRow
        } header: {
            Text("Images").apolloSectionHeader()
        } footer: {
            Text("The avatar is changed on reddit.com’s profile page, signed in as you. Banner photos are cropped from the centre to fit.")
                .apolloSectionFooter()
        }
    }

    /// Reddit's avatar editor lives on the website, where a photo or the avatar
    /// builder can be chosen. The page opens in the app, signed in with the
    /// account's web session; without one the web sign-in is offered first.
    private var avatarRow: some View {
        Button {
            Task {
                if await repository.hasWebFeatureSession() {
                    showingAvatarPage = true
                } else {
                    askingAvatarSignIn = true
                }
            }
        } label: {
            HStack {
                Text("Avatar")
                Spacer(minLength: 12)
                thumbnail(url: currentURL(user?.iconImage), size: CGSize(width: 36, height: 36), corner: 18)
                    .accessibilityHidden(true)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .apolloPlainSettingsRowInsets()
        .accessibilityHint("Opens reddit.com’s profile page")
        .accessibilityIdentifier("editProfile.avatar")
    }

    private var bannerRow: some View {
        Button {
            choosingBanner = true
        } label: {
            HStack {
                Text("Banner")
                Spacer(minLength: 12)
                bannerThumbnail
                    .accessibilityHidden(true)
            }
        }
        .apolloPlainSettingsRowInsets(rule: false)
        .accessibilityIdentifier("editProfile.banner")
    }

    private var bannerThumbnail: some View {
        let size = CGSize(width: 72, height: 22)
        return Group {
            switch bannerChange {
            case .replace(let prepared):
                Image(uiImage: prepared.preview).resizable().scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            case .remove:
                thumbnail(url: nil, size: size, corner: 4)
            case .none:
                thumbnail(url: currentURL(user?.bannerImage), size: size, corner: 4)
            }
        }
    }

    private func thumbnail(url: URL?, size: CGSize, corner: CGFloat) -> some View {
        Group {
            if let url {
                CachedAsyncImage(url: url, contentMode: .fill)
            } else {
                Color.gray.opacity(0.2)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    private var displayNameSection: some View {
        Section {
            TextField("Display Name", text: $edits.displayName)
                .submitLabel(.done)
                .apolloPlainSettingsRowInsets(rule: false)
                .accessibilityIdentifier("editProfile.displayName")
        } header: {
            Text("Display Name").apolloSectionHeader()
        } footer: {
            countFooter("Shown above u/\(username). It doesn't change your username. Leave it blank to show your username.",
                        count: edits.normalized.displayName.unicodeScalars.count, limit: ProfileEditLimits.displayName)
        }
    }

    private var aboutSection: some View {
        Section {
            TextField("About you", text: $edits.about, axis: .vertical)
                .lineLimit(3...8)
                .apolloPlainSettingsRowInsets(rule: false)
                .accessibilityIdentifier("editProfile.about")
        } header: {
            Text("About").apolloSectionHeader()
        } footer: {
            countFooter("A short bio on your profile.",
                        count: edits.normalized.about.unicodeScalars.count, limit: ProfileEditLimits.about)
        }
    }

    private var profileSection: some View {
        Section {
            SettingsDetailToggle("Allow People to Follow You",
                                 detail: "Followers are notified about posts you make to your profile and see them in their home feed.",
                                 isOn: $edits.acceptsFollowers)
                .apolloPlainSettingsRowInsets()
                .accessibilityIdentifier("editProfile.acceptsFollowers")
            SettingsDetailToggle("Mark Profile as NSFW",
                                 detail: "Labels your profile Not Safe For Work (18+).",
                                 isOn: $edits.isNSFW)
                .apolloPlainSettingsRowInsets(rule: false)
                .accessibilityIdentifier("editProfile.nsfw")
        } header: {
            Text("Profile").apolloSectionHeader()
        }
    }

    // MARK: Social links

    private var socialLinksSection: some View {
        Section {
            switch linksMode {
            case .loading:
                ApolloLoadingCell()
            case .editable:
                ForEach(socialEdits.rows) { row in
                    linkRow(row)
                }
                Button {
                    linkEditor = LinkEditor(row: nil, draft: SocialLinkDraft(platform: platforms.first ?? ProfileSocialPlatform(.instagram)))
                } label: {
                    Label("Add Social Link", systemImage: "plus.circle.fill")
                }
                .disabled(!socialEdits.canAdd)
                .apolloPlainSettingsRowInsets(rule: false)
                .accessibilityIdentifier("editProfile.addSocialLink")
            case .needsWebSession(let links):
                readOnlyLinks(links)
                Button("Sign In to Edit Social Links") { showingWebSignIn = true }
                    .apolloPlainSettingsRowInsets(rule: false)
                    .accessibilityIdentifier("editProfile.socialLinksSignIn")
            case .unavailable(let message, let links):
                readOnlyLinks(links)
                Text(message)
                    .foregroundStyle(.secondary)
                    .apolloPlainSettingsRowInsets()
                Button("Try Again") { Task { await loadLinks() } }
                    .apolloPlainSettingsRowInsets(rule: false)
                    .accessibilityIdentifier("editProfile.socialLinksRetry")
            }
        } header: {
            Text("Social Links").apolloSectionHeader()
        } footer: {
            if !socialLinksFooter.isEmpty {
                Text(socialLinksFooter).apolloSectionFooter()
            }
        }
    }

    private var socialLinksFooter: String {
        switch linksMode {
        case .loading:
            return ""
        case .editable:
            return "Reddit allows up to \(SocialLinkEdits.maximum) social links. Changes apply when you tap Save."
        case .needsWebSession:
            return "Editing social links needs a Reddit web sign-in, which Polls use too. You can also edit them on reddit.com."
        case .unavailable:
            return "You can also edit your social links on reddit.com."
        }
    }

    private func readOnlyLinks(_ links: [SocialLink]) -> some View {
        ForEach(links) { link in
            HStack(spacing: 12) {
                Image(systemName: SocialLinkScraper.systemImageName(forType: link.type))
                    .frame(width: 24)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(link.title)
                    Text(URL(string: link.urlString)?.host ?? link.urlString)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .apolloPlainSettingsRowInsets()
        }
    }

    private func linkRow(_ row: SocialLinkEdits.Row) -> some View {
        let title: String, detail: String, icon: String, isPending: Bool, draft: SocialLinkDraft?
        switch row {
        case .saved(let link):
            title = link.heading(in: platforms)
            detail = link.detail
            icon = link.systemImageName
            isPending = false
            draft = SocialLinkDraft(editing: link, platforms: platforms)
        case .pending(let pending):
            title = pending.platform.takesURL ? pending.normalizedTitle : pending.platform.displayName
            detail = pending.detail
            icon = pending.platform.systemImageName
            isPending = true
            draft = pending
        }
        return Button {
            if let draft { linkEditor = LinkEditor(row: row, draft: draft) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 24)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if isPending {
                    Text("New")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                socialEdits.remove(row)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                socialEdits.remove(row)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .accessibilityAction(named: "Remove") { socialEdits.remove(row) }
        .apolloPlainSettingsRowInsets()
        .accessibilityIdentifier("editProfile.socialLink.\(row.id)")
    }

    private func loadFailureSection(_ message: String) -> some View {
        Section {
            Text(message)
                .foregroundStyle(.secondary)
                .apolloPlainSettingsRowInsets()
            Button("Try Again") { Task { await load() } }
                .apolloPlainSettingsRowInsets(rule: false)
                .accessibilityIdentifier("editProfile.retry")
        } footer: {
            Text("Reddit may not allow this sign-in to change your profile here. You can still edit it on reddit.com.")
                .apolloSectionFooter()
        }
    }

    private var redditSection: some View {
        Section {
            Button("Open on reddit.com") { openURL(ProfileEditLinks.webSettings) }
                .apolloPlainSettingsRowInsets(rule: false)
                .accessibilityIdentifier("editProfile.openOnReddit")
        } footer: {
            Text("Anything else about your profile can be changed on reddit.com.")
                .apolloSectionFooter()
        }
    }

    private func countFooter(_ note: String, count: Int, limit: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(note)
            Spacer(minLength: 0)
            Text("\(count)/\(limit)")
                .monospacedDigit()
                .foregroundStyle(count > limit ? Color.red : Color.apolloSettingsSecondary)
        }
        .apolloSectionFooter()
    }

    // MARK: Images

    /// The image on the profile now, if it has one of its own.
    private func currentURL(_ raw: String?) -> URL? {
        guard let raw = raw?.replacingOccurrences(of: "&amp;", with: "&"), !raw.isEmpty,
              !raw.contains("avatar_default") else { return nil }
        return URL(string: raw)
    }

    private func prepare(_ item: PhotosPickerItem) async {
        defer { pickedItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let prepared = await Task.detached(priority: .userInitiated, operation: {
                  ProfileImagePreparer.prepareBanner(data)
              }).value else {
            unreadablePhoto = true
            return
        }
        bannerChange = .replace(prepared)
    }

    // MARK: Loading and saving

    private func load() async {
        guard settings == nil else { return }
        isLoading = true
        loadFailure = nil
        do {
            let loaded = try await repository.fetchProfileSettings(username: username)
            settings = loaded
            edits = loaded.edits
        } catch {
            loadFailure = UserFacingError.message(for: error) ?? "Couldn't load your profile settings."
        }
        isLoading = false
        if loadFailure == nil { await loadLinks() }
    }

    /// With a web session the links come with the ids removing one takes; without
    /// one they are the profile page's list, read-only.
    private func loadLinks() async {
        linksMode = .loading
        guard await repository.hasWebFeatureSession() else {
            linksMode = .needsWebSession(await pageLinks())
            return
        }
        do {
            let page = try await repository.fetchProfileSettingsPage()
            socialEdits = SocialLinkEdits(current: page.socialLinks)
            if !page.platforms.isEmpty { platforms = page.platforms }
            linksMode = .editable
        } catch {
            linksMode = .unavailable(UserFacingError.message(for: error) ?? "Couldn't load your social links.",
                                     await pageLinks())
        }
    }

    private func pageLinks() async -> [SocialLink] {
        (try? await SocialLinkService.fetchSocialLinks(username: username)) ?? []
    }

    /// Settings first, so a refusal leaves nothing half-applied; then the
    /// banner; social links are separate (they go through the website) and
    /// follow either way. Whatever was applied stays applied and what failed
    /// stays staged for another try.
    private func save() async {
        guard let settings else { return }
        isSaving = true
        var failures: [String] = []
        var appliedAnything = false

        if settings.hasChanges(edits) {
            do {
                try await repository.saveProfile(settings, applying: edits, username: username)
                appliedAnything = true
                if let saved = try? await repository.fetchProfileSettings(username: username) {
                    self.settings = saved
                    edits = saved.edits
                }
            } catch {
                failures.append(UserFacingError.message(for: error) ?? "Couldn't save your changes.")
            }
        }
        if failures.isEmpty, !bannerChange.isNone {
            do {
                switch bannerChange {
                case .none: break
                case .replace(let prepared):
                    try await repository.uploadProfileBanner(jpeg: prepared.jpeg, username: username)
                case .remove:
                    try await repository.removeProfileBanner(username: username)
                }
                bannerChange = .none
                appliedAnything = true
            } catch {
                failures.append("Banner: \(UserFacingError.message(for: error) ?? "Couldn't update it.")")
            }
        }
        if await saveSocialLinks(failures: &failures) { appliedAnything = true }

        isSaving = false
        if appliedAnything { onSaved() }
        if failures.isEmpty {
            dismiss()
        } else {
            saveFailure = failures.joined(separator: "\n")
        }
    }

    /// Removals first, which a replaced link's addition follows; if they fail
    /// the additions wait, or an edit would leave the old link and the new one.
    private func saveSocialLinks(failures: inout [String]) async -> Bool {
        guard case .editable = linksMode, socialEdits.hasChanges else { return false }
        let plan = socialEdits.plan
        var applied = false
        if !plan.removing.isEmpty {
            do {
                socialEdits.didRemove(try await repository.removeProfileSocialLinks(ids: plan.removing))
                applied = true
            } catch {
                failures.append("Social links: \(UserFacingError.message(for: error) ?? "Couldn't remove them.")")
                return applied
            }
        }
        for draft in plan.adding {
            do {
                socialEdits.didAdd(draft.id, list: try await repository.addProfileSocialLink(draft))
                applied = true
            } catch {
                failures.append("\(draft.platform.displayName): \(UserFacingError.message(for: error) ?? "Couldn't add it.")")
            }
        }
        return applied
    }
}
