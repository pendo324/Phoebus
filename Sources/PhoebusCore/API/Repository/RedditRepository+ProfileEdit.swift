import Foundation

/// Editing your own profile, which lives in the user subreddit `u_<name>`.
extension RedditRepository {
    /// The profile's current settings (`about/edit`), which a save needs in
    /// full: `site_admin` resets whatever it isn't sent. The follow permission
    /// is the account's `enable_followers` preference when it can be read.
    public func fetchProfileSettings(username: String) async throws -> ProfileSettings {
        let data = try await client.get(path: "/r/u_\(username)/about/edit")
        let settings = try ProfileSettings.parse(data, username: username)
        guard let prefs = try? await client.get(path: ProfileFollowPreference.path),
              let allowed = ProfileFollowPreference.parse(prefs) else { return settings }
        return settings.settingFollowPermission(allowed)
    }

    /// Writes the display name, about text and NSFW label back through
    /// `site_admin`, then the follow permission to the account's preferences
    /// (after, since `site_admin` resends the old one). Refuses up front what
    /// Reddit would answer with a bare HTTP 500, such as a long display name.
    public func saveProfile(_ settings: ProfileSettings, applying edits: ProfileEdits, username: String) async throws {
        let issues = settings.issues(for: edits)
        guard issues.isEmpty else { throw ProfileEditRefusal(issues: issues) }
        if settings.hasSiteAdminChanges(edits) {
            let parameters = settings.siteAdminParameters(applying: edits, username: username)
            let data = try await client.post(path: "/api/site_admin", parameters: parameters)
            try PostedCommentResponse.throwIfRejected(data)
        }
        if settings.hasFollowPreferenceChange(edits) {
            try await client.patchJSON(path: ProfileFollowPreference.path,
                                       body: ProfileFollowPreference.patchBody(edits.acceptsFollowers))
        }
    }

    /// Replaces the banner with a prepared JPEG.
    public func uploadProfileBanner(jpeg: Data, username: String) async throws {
        let form = MultipartForm(
            fields: [(name: "upload_type", value: "banner"),
                     (name: "img_type", value: "jpg"),
                     (name: "api_type", value: "json")],
            file: MultipartForm.File(fieldName: "file", filename: "\(username)-banner.jpg",
                                     mimeType: "image/jpeg", data: jpeg))
        let data = try await client.postMultipart(path: "/r/u_\(username)/api/upload_sr_img", form: form)
        try ProfileImageUploadResponse.throwIfRejected(data)
    }

    /// Removes the banner, back to Reddit's default.
    public func removeProfileBanner(username: String) async throws {
        try await postChecked("/r/u_\(username)/api/delete_sr_banner", [:])
    }

    // MARK: Social links

    /// Social links go through reddit.com's web GraphQL, which takes a web
    /// session's cookie: an API-key account has one only after signing in on
    /// the web (the same one polls and Chat use).
    private func socialLinksSession() async throws -> WebSessionCredential {
        guard let session = await webFeatureSession() else { throw ProfileSocialLinksError.requiresWebSession }
        return session
    }

    /// The profile's social links, with the ids removing one takes, and the
    /// platforms a link can be added for, from reddit.com's profile settings page.
    public func fetchProfileSettingsPage() async throws -> ProfileSettingsPage {
        try await ProfileSocialLinksService.fetchPage(session: socialLinksSession())
    }

    /// Adds a social link; returns the list as it now is.
    public func addProfileSocialLink(_ draft: SocialLinkDraft) async throws -> [ProfileSocialLink] {
        try await ProfileSocialLinksService.add(draft, session: socialLinksSession())
    }

    /// Removes social links by id; returns the list as it now is.
    public func removeProfileSocialLinks(ids: [String]) async throws -> [ProfileSocialLink] {
        try await ProfileSocialLinksService.remove(ids: ids, session: socialLinksSession())
    }

    // MARK: Profile Visibility

    private func visibilitySession() async throws -> WebSessionCredential {
        guard let session = await webFeatureSession() else { throw ProfileVisibilityError.requiresWebSession }
        return session
    }

    /// Sends what the profile shows: the whole set, as reddit.com does.
    public func saveProfilePrivacy(_ input: ProfileVisibility.PrivacyInput) async throws {
        try await ProfileVisibilityService.save(input, session: visibilitySession())
    }

    /// Sends whether your follower count shows on your profile.
    public func saveProfileFollowerCount(shown: Bool) async throws {
        try await ProfileVisibilityService.saveFollowerCount(shown: shown, session: visibilitySession())
    }
}
