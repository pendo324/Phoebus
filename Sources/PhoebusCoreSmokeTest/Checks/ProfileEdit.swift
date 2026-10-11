import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import PhoebusCore

// MARK: - Native Edit Profile
//
// The settings fixture is shaped like `GET /r/u_<name>/about/edit` with
// synthetic values.

private final class ProfileEditStub: URLProtocol, @unchecked Sendable {
    struct Captured {
        let url: URL
        let method: String
        let headers: [String: String]
        let body: Data
    }

    nonisolated(unsafe) static var captured: [Captured] = []
    nonisolated(unsafe) static var respond: @Sendable (URL) -> Data = { _ in Data(#"{"json":{"errors":[]}}"#.utf8) }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.captured.append(Captured(url: url, method: request.httpMethod ?? "GET",
                                      headers: request.allHTTPHeaderFields ?? [:], body: Self.body(of: request)))
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.respond(url))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

@MainActor func checkNativeEditProfile() async throws {
    let fixtureData = try Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/profile-about-edit.json"))
    let settings = try ProfileSettings.parse(fixtureData, username: "exampleuser")

    check("the profile settings read the subreddit fullname", settings.subredditFullname == "t5_abc123")
    check("...the display name, about text and toggles",
          settings.edits == ProfileEdits(displayName: "Example Name", about: "Synthetic bio.\nSecond line.",
                                         isNSFW: false, acceptsFollowers: true))
    check("a response that isn't settings is unreadable, not a blank profile",
          (try? ProfileSettings.parse(Data(#"{"kind":"Listing","data":{"children":[]}}"#.utf8), username: "x")) == nil
          && (try? ProfileSettings.parse(Data("<html>".utf8), username: "x")) == nil)

    // Reddit's `u_<name>` title fallback is no display name.
    var fallbackRoot = try JSONSerialization.jsonObject(with: fixtureData) as! [String: Any]
    var fallbackData = fallbackRoot["data"] as! [String: Any]
    fallbackData["title"] = "u_ExampleUser"
    fallbackRoot["data"] = fallbackData
    let fallback = try ProfileSettings.parse(try JSONSerialization.data(withJSONObject: fallbackRoot), username: "exampleuser")
    check("the u_<name> title fallback reads as a blank display name", fallback.edits.displayName.isEmpty)
    check("...and is sent back as it was when the display name is left alone",
          fallback.siteAdminParameters(applying: fallback.edits, username: "exampleuser")["title"] == "u_ExampleUser")

    fallbackData["title"] = ""
    fallbackRoot["data"] = fallbackData
    let untitled = try ProfileSettings.parse(try JSONSerialization.data(withJSONObject: fallbackRoot), username: "exampleuser")
    var aboutOnly = untitled.edits
    aboutOnly.about = "A bio"
    check("an account with no title still sends one when only the bio changes, since a title can't be empty",
          untitled.siteAdminParameters(applying: aboutOnly, username: "exampleuser")["title"] == "exampleuser")

    // The save form.
    let unchanged = settings.siteAdminParameters(applying: settings.edits, username: "exampleuser")
    check("the save form targets the user subreddit by fullname and name",
          unchanged["sr"] == "t5_abc123" && unchanged["name"] == "u_exampleuser"
          && unchanged["api_type"] == "json" && unchanged["type"] == "user")
    check("settings Reddit names differently are sent under site_admin's names",
          unchanged["link_type"] == "any" && unchanged["lang"] == "en" && unchanged["allow_top"] == "true"
          && unchanged["subreddit_id"] == nil && unchanged["subreddit_type"] == nil
          && unchanged["content_options"] == nil && unchanged["language"] == nil && unchanged["default_set"] == nil)
    check("numbers and flags keep their form: 1 is not true",
          unchanged["crowd_control_level"] == "1" && unchanged["wiki_edit_karma"] == "100"
          && unchanged["prediction_leaderboard_entry_type"] == "2"
          && unchanged["restrict_posting"] == "true" && unchanged["hide_ads"] == "false")
    check("null settings are left out rather than sent as text",
          unchanged["header-title"] == nil && unchanged["welcome_message_text"] == nil
          && unchanged["suggested_comment_sort"] == nil && unchanged["domain"] == nil)
    check("a nested setting goes as JSON text",
          unchanged["comment_contribution_settings"] == #"{"allowed_media_types":["static","animated"]}"#)
    check("an untouched profile resends every setting as it was",
          unchanged["title"] == "Example Name" && unchanged["public_description"] == "Synthetic bio.\nSecond line."
          && unchanged["over_18"] == "false" && unchanged["accept_followers"] == "true"
          && unchanged["spam_links"] == "high" && unchanged["allow_polls"] == "true")

    let edited = settings.siteAdminParameters(
        applying: ProfileEdits(displayName: "  New Name \n", about: "  Hello  ", isNSFW: true, acceptsFollowers: false),
        username: "exampleuser")
    check("the edited fields replace the old ones, trimmed",
          edited["title"] == "New Name" && edited["public_description"] == "Hello"
          && edited["over_18"] == "true")
    check("...but the follow permission is not set here: site_admin ignores it, so it goes as read",
          edited["accept_followers"] == "true")
    check("...and everything else is still sent", edited["spam_links"] == "high" && edited["sr"] == "t5_abc123")
    let blank = settings.siteAdminParameters(
        applying: ProfileEdits(displayName: "   ", about: "", isNSFW: false, acceptsFollowers: true), username: "exampleuser")
    check("a blank display name is sent as the username, since a title can't be empty",
          blank["title"] == "exampleuser" && blank["public_description"] == "")

    // Changes and limits.
    var probe = settings.edits
    check("no edits is no change", !settings.hasChanges(probe))
    probe.about = "  Synthetic bio.\nSecond line.  "
    check("edge whitespace alone is no change", !settings.hasChanges(probe))
    probe.acceptsFollowers = false
    check("a toggle is a change", settings.hasChanges(probe))
    check("the follow permission is an account preference change, not a subreddit setting one",
          settings.hasFollowPreferenceChange(probe) && !settings.hasSiteAdminChanges(probe))
    probe.acceptsFollowers = true
    probe.isNSFW = true
    check("the NSFW label and text are subreddit setting changes",
          settings.hasSiteAdminChanges(probe) && !settings.hasFollowPreferenceChange(probe))
    probe = settings.edits
    probe.acceptsFollowers = false

    func issues(name: String = "Example Name", about: String = "Synthetic bio.\nSecond line.") -> [ProfileEditIssue] {
        settings.issues(for: ProfileEdits(displayName: name, about: about, isNSFW: false, acceptsFollowers: true))
    }
    check("the limits are what site_admin saves: a 30 character display name and a 200 character about",
          ProfileEditLimits.displayName == 30 && ProfileEditLimits.about == 200)
    check("a 30 character display name and 200 character about are fine",
          issues(name: String(repeating: "n", count: 30), about: String(repeating: "a", count: 200)).isEmpty)
    check("a 31 character display name is over, since site_admin answers HTTP 500 to it",
          issues(name: String(repeating: "n", count: 31)) == [.displayNameTooLong(limit: 30)])
    check("a 201 character about is over",
          issues(about: String(repeating: "a", count: 201)) == [.aboutTooLong(limit: 200)])
    check("spaces at the edges don't count toward the limit",
          issues(name: " " + String(repeating: "n", count: 30) + " ").isEmpty)

    var longRoot = try JSONSerialization.jsonObject(with: fixtureData) as! [String: Any]
    var longData = longRoot["data"] as! [String: Any]
    longData["title"] = String(repeating: "t", count: 100)
    longRoot["data"] = longData
    let longTitled = try ProfileSettings.parse(try JSONSerialization.data(withJSONObject: longRoot), username: "exampleuser")
    check("a display name already over the limit is only flagged once it is edited",
          longTitled.issues(for: longTitled.edits).isEmpty
          && longTitled.issues(for: ProfileEdits(displayName: String(repeating: "t", count: 101), about: longTitled.edits.about,
                                                 isNSFW: false, acceptsFollowers: true)) == [.displayNameTooLong(limit: 30)])

    // Image geometry.
    check("a banner keeps its width between 640 and 1280, at 10:3",
          ProfileImageSpec.bannerSize(sourceWidth: 3000) == .init(width: 1280, height: 384)
          && ProfileImageSpec.bannerSize(sourceWidth: 800) == .init(width: 800, height: 240)
          && ProfileImageSpec.bannerSize(sourceWidth: 400) == .init(width: 640, height: 192))
    check("a square photo fills a banner by cropping top and bottom evenly",
          ProfileImageSpec.fillRect(sourceWidth: 1000, sourceHeight: 1000, target: .init(width: 1280, height: 384))
              == .init(x: 0, y: -448, width: 1280, height: 1280))
    check("a wide photo fills a banner by cropping left and right evenly",
          ProfileImageSpec.fillRect(sourceWidth: 4000, sourceHeight: 1000, target: .init(width: 1280, height: 384))
              == .init(x: -128, y: 0, width: 1536, height: 384))
    check("the upload limit is the endpoint's 500 KiB, tried from the best JPEG quality down",
          ProfileImageSpec.maxBytes == 512_000 && ProfileImageSpec.jpegQualities.first == 0.9
          && ProfileImageSpec.jpegQualities == ProfileImageSpec.jpegQualities.sorted(by: >))
    check("the avatar is changed on reddit.com's profile settings",
          ProfileEditLinks.webSettings.absoluteString == "https://www.reddit.com/settings/profile")

    // The upload response.
    func rejection(_ json: String) -> String? {
        do { try ProfileImageUploadResponse.throwIfRejected(Data(json.utf8)); return nil } catch { return UserFacingError.message(for: error) }
    }
    check("an accepted image upload is not an error",
          rejection(#"{"errors":[],"img_src":"https://styles.redditmedia.com/t5_abc123/x.jpg"}"#) == nil)
    check("a rejected image says why, in Reddit's words",
          rejection(#"{"errors":["IMAGE_ERROR"],"errors_values":["Invalid image or general image error"]}"#)
              == "Invalid image or general image error.")
    check("a rejection with no explanation quotes its code",
          rejection(#"{"errors":["BAD_CSS_NAME"]}"#) == "BAD_CSS_NAME.")

    // Requests, through a stubbed transport.
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ProfileEditStub.self]
    let session = URLSession(configuration: configuration)

    let credentials = InMemoryCredentialStore()
    try credentials.save(RedditCredential(accessToken: "tok", refreshToken: "rt",
                                          expiration: Date().addingTimeInterval(3600), isPermanent: true))
    let oauthAuth = RedditAuthClient(session: session, credentialStore: credentials, webSessionStore: InMemoryWebSessionStore())
    let repository = RedditRepository(client: RedditAPIClient(auth: oauthAuth, session: session))

    ProfileEditStub.captured = []
    ProfileEditStub.respond = { _ in fixtureData }
    let fetched = try await repository.fetchProfileSettings(username: "exampleuser")
    let fetchRequest = ProfileEditStub.captured.first
    check("settings are read from the user subreddit's about/edit on the OAuth host",
          fetchRequest?.url.host == "oauth.reddit.com" && fetchRequest?.url.path == "/r/u_exampleuser/about/edit"
          && fetchRequest?.method == "GET" && fetched == settings)

    ProfileEditStub.respond = { _ in Data(#"{"json":{"errors":[]}}"#.utf8) }
    ProfileEditStub.captured = []
    try await repository.saveProfile(settings, applying: ProfileEdits(displayName: "New Name", about: "Hi & bye", isNSFW: true,
                                                                       acceptsFollowers: true), username: "exampleuser")
    let saveRequest = ProfileEditStub.captured.last
    let saveBody = String(data: saveRequest?.body ?? Data(), encoding: .utf8) ?? ""
    check("a save posts the whole form to site_admin",
          saveRequest?.url.path == "/api/site_admin" && saveRequest?.method == "POST"
          && saveRequest?.headers["Authorization"] == "Bearer tok"
          && saveBody.contains("sr=t5_abc123") && saveBody.contains("title=New%20Name")
          && saveBody.contains("public_description=Hi%20%26%20bye") && saveBody.contains("over_18=true")
          && saveBody.contains("spam_links=high"))
    check("...and leaves the account preferences alone when the follow permission is unchanged",
          ProfileEditStub.captured.count == 1)

    ProfileEditStub.respond = { _ in Data(#"{"json":{"errors":[["TOO_LONG","this is too long (max: 100)","title"]]}}"#.utf8) }
    var saveRefusal: String?
    var aboutEdit = settings.edits
    aboutEdit.about = "Another bio"
    do { try await repository.saveProfile(settings, applying: aboutEdit, username: "exampleuser") }
    catch { saveRefusal = UserFacingError.message(for: error) }
    check("a refused save surfaces Reddit's reason", saveRefusal == "This is too long (max: 100).")

    ProfileEditStub.captured = []
    var longName = settings.edits
    longName.displayName = String(repeating: "n", count: 40)
    var longNameRefusal: String?
    do { try await repository.saveProfile(settings, applying: longName, username: "exampleuser") }
    catch { longNameRefusal = UserFacingError.message(for: error) }
    check("a display name over 30 is refused before sending, with the limit rather than Reddit's HTTP 500",
          longNameRefusal == "Display name can be up to 30 characters." && ProfileEditStub.captured.isEmpty)

    // The follow permission: an account preference, saved after the subreddit settings.
    let prefsFollowing = Data(#"{"enable_followers":true,"over_18":false}"#.utf8)
    let prefsNotFollowing = Data(#"{"enable_followers":false}"#.utf8)
    check("the follow preference is read from the prefs object",
          ProfileFollowPreference.parse(prefsFollowing) == true && ProfileFollowPreference.parse(prefsNotFollowing) == false
          && ProfileFollowPreference.parse(Data(#"{"over_18":false}"#.utf8)) == nil
          && ProfileFollowPreference.parse(Data("<html>".utf8)) == nil)
    let notFollowed = settings.settingFollowPermission(false)
    check("settings take the follow permission from the preference, and resend it as that",
          !notFollowed.edits.acceptsFollowers && notFollowed.edits.displayName == settings.edits.displayName
          && notFollowed.siteAdminParameters(applying: notFollowed.edits, username: "exampleuser")["accept_followers"] == "false")

    ProfileEditStub.captured = []
    ProfileEditStub.respond = { url in url.path == "/api/v1/me/prefs" ? prefsNotFollowing : fixtureData }
    let withPreference = try await repository.fetchProfileSettings(username: "exampleuser")
    check("the settings read the follow permission from /api/v1/me/prefs over the subreddit's accept_followers",
          ProfileEditStub.captured.map(\.url.path) == ["/r/u_exampleuser/about/edit", "/api/v1/me/prefs"]
          && withPreference.edits.acceptsFollowers == false)

    ProfileEditStub.captured = []
    ProfileEditStub.respond = { _ in Data(#"{"json":{"errors":[]}}"#.utf8) }
    var followOff = settings.edits
    followOff.acceptsFollowers = false
    try await repository.saveProfile(settings, applying: followOff, username: "exampleuser")
    let followPatch = ProfileEditStub.captured.last
    check("turning off following alone PATCHes enable_followers as JSON, without a site_admin save",
          ProfileEditStub.captured.count == 1 && followPatch?.method == "PATCH"
          && followPatch?.url.host == "oauth.reddit.com" && followPatch?.url.path == "/api/v1/me/prefs"
          && followPatch?.headers["Authorization"] == "Bearer tok"
          && followPatch?.headers["Content-Type"] == "application/json"
          && String(decoding: followPatch?.body ?? Data(), as: UTF8.self) == #"{"enable_followers":false}"#)

    ProfileEditStub.captured = []
    followOff.about = "And a new bio"
    try await repository.saveProfile(settings, applying: followOff, username: "exampleuser")
    check("with text changed too, site_admin goes first and the preference after, so it isn't reset",
          ProfileEditStub.captured.map(\.url.path) == ["/api/site_admin", "/api/v1/me/prefs"])

    ProfileEditStub.respond = { _ in Data(#"{"errors":[],"img_src":"https://example.invalid/x.jpg"}"#.utf8) }
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
    try await repository.uploadProfileBanner(jpeg: jpeg, username: "exampleuser")
    let bannerUpload = ProfileEditStub.captured.last
    let bannerBody = bannerUpload?.body ?? Data()
    let bannerText = String(decoding: bannerBody, as: UTF8.self)
    check("a banner goes to the user subreddit's upload_sr_img as the banner, in a multipart body",
          bannerUpload?.url.path == "/r/u_exampleuser/api/upload_sr_img" && bannerUpload?.method == "POST"
          && bannerUpload?.headers["Content-Type"]?.hasPrefix("multipart/form-data; boundary=") == true
          && bannerText.contains("name=\"upload_type\"\r\n\r\nbanner\r\n")
          && bannerText.contains("name=\"img_type\"\r\n\r\njpg\r\n")
          && bannerText.contains("name=\"file\"; filename=\"exampleuser-banner.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n")
          && bannerBody.range(of: jpeg) != nil)
    check("the multipart boundary in the header is the one in the body",
          bannerUpload?.headers["Content-Type"].map { header in
              guard let boundary = header.components(separatedBy: "boundary=").last else { return false }
              return bannerText.hasPrefix("--\(boundary)\r\n") && bannerText.hasSuffix("\r\n--\(boundary)--\r\n")
          } == true)

    ProfileEditStub.respond = { _ in Data(#"{"errors":["IMAGE_ERROR"],"errors_values":["Invalid image"]}"#.utf8) }
    var uploadRefusal: String?
    do { try await repository.uploadProfileBanner(jpeg: jpeg, username: "exampleuser") }
    catch { uploadRefusal = UserFacingError.message(for: error) }
    check("a refused banner upload surfaces Reddit's reason", uploadRefusal == "Invalid image.")

    ProfileEditStub.respond = { _ in Data(#"{"json":{"errors":[]}}"#.utf8) }
    try await repository.removeProfileBanner(username: "exampleuser")
    check("removing the banner posts to delete_sr_banner",
          ProfileEditStub.captured.last?.url.path == "/r/u_exampleuser/api/delete_sr_banner")

    // The same requests over a web session: the profile's endpoints go to
    // oauth.reddit.com with the session's web bearer, the upload still multipart.
    let bearer = makeChatJWT(expiringIn: 3600)
    let webAuth = RedditAuthClient(session: session, credentialStore: InMemoryCredentialStore(), webSessionStore: InMemoryWebSessionStore())
    await webAuth.setWebSession(WebSessionCredential(username: "profilewebuser", cookieHeader: "reddit_session=abc; token_v2=\(bearer)",
                                                     modhash: "mh"))
    let webRepository = RedditRepository(client: RedditAPIClient(auth: webAuth, session: session))

    ProfileEditStub.captured = []
    ProfileEditStub.respond = { _ in fixtureData }
    _ = try await webRepository.fetchProfileSettings(username: "exampleuser")
    let webFetch = ProfileEditStub.captured.first
    check("a web session reads the settings from oauth.reddit.com with its bearer, not the cookie",
          webFetch?.url.host == "oauth.reddit.com" && webFetch?.url.path == "/r/u_exampleuser/about/edit"
          && webFetch?.headers["Authorization"] == "Bearer \(bearer)" && webFetch?.headers["Cookie"] == nil)

    ProfileEditStub.respond = { _ in Data(#"{"json":{"errors":[]}}"#.utf8) }
    try await webRepository.saveProfile(settings, applying: aboutEdit, username: "exampleuser")
    let webSave = ProfileEditStub.captured.last
    check("...and saves them there, as a form",
          webSave?.url.host == "oauth.reddit.com" && webSave?.url.path == "/api/site_admin"
          && webSave?.headers["Authorization"] == "Bearer \(bearer)"
          && webSave?.headers["Content-Type"] == "application/x-www-form-urlencoded"
          && String(decoding: webSave?.body ?? Data(), as: UTF8.self).contains("sr=t5_abc123"))

    ProfileEditStub.captured = []
    try await webRepository.saveProfile(settings, applying: followOff, username: "exampleuser")
    let webPatch = ProfileEditStub.captured.last
    check("...and the follow preference too, as JSON with the bearer",
          webPatch?.method == "PATCH" && webPatch?.url.host == "oauth.reddit.com" && webPatch?.url.path == "/api/v1/me/prefs"
          && webPatch?.headers["Authorization"] == "Bearer \(bearer)" && webPatch?.headers["Cookie"] == nil
          && webPatch?.headers["Content-Type"] == "application/json")

    ProfileEditStub.respond = { _ in Data(#"{"errors":[],"img_src":"https://example.invalid/x.jpg"}"#.utf8) }
    try await webRepository.uploadProfileBanner(jpeg: jpeg, username: "exampleuser")
    let webUpload = ProfileEditStub.captured.last
    check("...and uploads the banner there with the bearer, still multipart",
          webUpload?.url.host == "oauth.reddit.com" && webUpload?.url.path == "/r/u_exampleuser/api/upload_sr_img"
          && webUpload?.headers["Authorization"] == "Bearer \(bearer)" && webUpload?.headers["Cookie"] == nil
          && webUpload?.headers["Content-Type"]?.hasPrefix("multipart/form-data; boundary=") == true
          && String(decoding: webUpload?.body ?? Data(), as: UTF8.self).contains("name=\"upload_type\"\r\n\r\nbanner\r\n")
          && (webUpload?.body ?? Data()).range(of: jpeg) != nil)

    ProfileEditStub.respond = { _ in Data(#"{"json":{"errors":[]}}"#.utf8) }
    try await webRepository.removeProfileBanner(username: "exampleuser")
    check("...and removes it there",
          ProfileEditStub.captured.last?.url.host == "oauth.reddit.com"
          && ProfileEditStub.captured.last?.url.path == "/r/u_exampleuser/api/delete_sr_banner"
          && ProfileEditStub.captured.last?.headers["Authorization"] == "Bearer \(bearer)")
}

// MARK: - Native Edit Profile: social links
//
// The fixtures are shaped like the Shreddit GraphQL answers to
// `SetProfileSocialLinks` and `DeleteProfileSocialLinks`, with synthetic values.

@MainActor func checkNativeEditProfileSocialLinks() async throws {
    let setFixture = try Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/profile-social-links-set.json"))
    let deleteFixture = try Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/profile-social-links-delete.json"))
    func json(_ data: Data) -> [String: Any] { (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:] }

    // The types.
    let types = ProfileSocialLinkType.allCases
    check("Reddit's 26 social link types are offered, Reddit first and custom last",
          types.count == 26 && types.first == .reddit && types.last == .custom && Set(types.map(\.rawValue)).count == 26)
    check("the types the captures and Reborn showed keep Reddit's names",
          ProfileSocialLinkType(rawValue: "CUSTOM") == .custom && ProfileSocialLinkType(rawValue: "INSTAGRAM") == .instagram
          && ProfileSocialLinkType(rawValue: "BUY_ME_A_COFFEE") == .buyMeACoffee)
    check("the platforms that take display text and a URL are the nine Reddit lists",
          types.filter(\.takesURL) == [.discord, .facebook, .indiegogo, .kickstarter, .shopify, .spotify, .substack, .youTube, .custom])
    check("every type has a name and an icon", types.allSatisfy { !$0.displayName.isEmpty && !$0.systemImageName.isEmpty })
    check("names are the ones Reddit's settings page shows",
          ProfileSocialLinkType.kofi.displayName == "Kofi" && ProfileSocialLinkType.twitter.displayName == "Twitter"
          && ProfileSocialLinkType.youTube.displayName == "Youtube" && ProfileSocialLinkType.custom.displayName == "Custom")

    // A draft's input.
    check("a named platform sends its username without @ or edge whitespace",
          SocialLinkDraft(type: .instagram, handle: " @test \n").input == ["type": "INSTAGRAM", "handle": "test"])
    let custom = SocialLinkDraft(type: .custom, title: " GitHub \n", url: " github.com/example ")
    check("a custom link sends display text and an https URL, added when none was typed",
          custom.input == ["type": "CUSTOM", "title": "GitHub", "outboundUrl": "https://github.com/example"])
    check("a URL typed with its scheme is kept",
          SocialLinkDraft(type: .custom, title: "A", url: "http://example.com/a?b=c").normalizedURL == "http://example.com/a?b=c")
    check("a username platform needs a username", SocialLinkDraft(type: .twitch, handle: " @ ").issues == [.missingUsername])
    let discord = SocialLinkDraft(type: .discord, title: " Example Server ", url: "discord.gg/example")
    check("a platform that takes display text and a URL sends those, not a handle",
          discord.input == ["type": "DISCORD", "title": "Example Server", "outboundUrl": "https://discord.gg/example"]
          && SocialLinkDraft(type: .discord, handle: "someone").issues == [.missingTitle, .missingURL])
    check("limits: 30 for a username, 21 for display text, 250 for a URL",
          SocialLinkDraft(type: .instagram, handle: String(repeating: "a", count: 30)).isValid
          && SocialLinkDraft(type: .instagram, handle: String(repeating: "a", count: 31)).issues == [.usernameTooLong(limit: 30)]
          && SocialLinkDraft(type: .custom, title: String(repeating: "t", count: 21), url: "example.com").isValid
          && SocialLinkDraft(type: .custom, title: String(repeating: "t", count: 22), url: "example.com").issues == [.titleTooLong(limit: 21)]
          && SocialLinkDraft(type: .custom, title: "A", url: "https://example.com/" + String(repeating: "u", count: 230)).isValid
          && SocialLinkDraft(type: .custom, title: "A", url: "https://example.com/" + String(repeating: "u", count: 231)).issues == [.urlTooLong(limit: 250)])
    check("a custom link needs text and a link",
          SocialLinkDraft(type: .custom).issues == [.missingTitle, .missingURL])
    check("...and the link must be a web address",
          ["not a url", "ftp://example.com", "javascript:alert(1)", "https://nodot", "https://exa mple.com"].allSatisfy {
              SocialLinkDraft(type: .custom, title: "A", url: $0).issues == [.invalidURL]
          })
    check("an invalid draft has no input", SocialLinkDraft(type: .custom, title: "A", url: "x").input == nil)

    // The list being edited.
    let saved = try ProfileSocialLinksService.decode(json(setFixture), field: "setSocialLinks")
    check("Reddit's answer reads as the full list, with ids",
          saved.map(\.id) == ["00000000-0000-4000-8000-000000000001", "00000000-0000-4000-8000-000000000002"]
          && saved.map(\.type) == [.custom, .instagram] && saved[1].handle == "exampleuser"
          && saved[0].outboundURL == "https://example.com/me" && saved[0].handle == nil)
    let afterDelete = try ProfileSocialLinksService.decode(json(deleteFixture), field: "deleteSocialLinks")
    check("a removal answers in the same shape under its own field", afterDelete.map(\.title) == ["Example Site"])
    let unknown = try ProfileSocialLinksService.decode(
        ["data": ["deleteSocialLinks": ["ok": true, "errors": NSNull(), "socialLinks": [
            ["id": "x1", "type": "SOMETHING_NEW", "title": "New", "handle": NSNull(), "outboundUrl": "https://example.com"]]]]],
        field: "deleteSocialLinks")
    check("a type this app doesn't know is kept, but can't be edited",
          unknown.count == 1 && unknown[0].type == nil && unknown[0].rawType == "SOMETHING_NEW"
          && SocialLinkDraft(editing: unknown[0]) == nil)
    let editable = SocialLinkDraft(editing: saved[1])
    check("a saved link becomes a draft to edit",
          editable?.platform.type == "INSTAGRAM" && editable?.handle == "exampleuser")
    check("...a custom one with its text and address",
          SocialLinkDraft(editing: saved[0]).map { $0.title == "Example Site" && $0.url == "https://example.com/me" } == true)

    var edits = SocialLinkEdits(current: saved)
    check("nothing staged is no change", !edits.hasChanges && edits.plan.isEmpty && edits.count == 2 && edits.canAdd)
    edits.remove(edits.rows[0])
    check("removing a saved link stages its id and drops the row",
          edits.plan.removing == ["00000000-0000-4000-8000-000000000001"] && edits.count == 1 && edits.hasChanges)
    edits.add(SocialLinkDraft(type: .twitch, handle: "streamer"))
    check("an added link is staged after the saved ones",
          edits.plan.adding.count == 1 && edits.count == 2
          && edits.rows.last.map { if case .pending = $0 { return true } else { return false } } == true)
    edits.add(SocialLinkDraft(type: .custom))
    check("an incomplete draft is not added", edits.plan.adding.count == 1)

    guard case .saved(let instagram) = edits.rows[0] else { fatalError("expected the saved Instagram row") }
    edits.replace(.saved(instagram), with: SocialLinkDraft(type: .instagram, handle: "EXAMPLEUSER"))
    check("saving a link as it was is no change", edits.plan.removing.count == 1 && edits.plan.adding.count == 1)
    edits.replace(.saved(instagram), with: SocialLinkDraft(type: .instagram, handle: "renamed"))
    check("editing a saved link removes it and adds the new one",
          edits.plan.removing.count == 2 && edits.plan.adding.map(\.handle) == ["streamer", "renamed"] && edits.count == 2)
    if case .pending(let streamer) = edits.rows[0] {
        edits.replace(.pending(streamer), with: SocialLinkDraft(type: .twitch, handle: "other"))
    }
    check("editing a staged link changes it in place",
          edits.plan.adding.map(\.handle) == ["other", "renamed"] && edits.plan.adding[0].platform.type == "TWITCH")
    if case .pending(let first) = edits.rows[0] { edits.remove(.pending(first)) }
    check("removing a staged link just unstages it",
          edits.plan.adding.map(\.handle) == ["renamed"] && edits.plan.removing.count == 2)

    var full = SocialLinkEdits(current: [])
    for index in 0..<7 { full.add(SocialLinkDraft(type: .instagram, handle: "user\(index)")) }
    check("Reddit's five-link limit stops more being added",
          SocialLinkEdits.maximum == 5 && full.count == 5 && !full.canAdd)
    full.remove(full.rows[0])
    check("...until one is removed", full.canAdd)

    var applying = SocialLinkEdits(current: saved)
    applying.remove(.saved(saved[1]))
    let staged = SocialLinkDraft(type: .twitch, handle: "streamer")
    applying.add(staged)
    applying.didRemove([saved[0]])
    check("after Reddit applies the removals, only the additions stay staged",
          applying.current == [saved[0]] && applying.plan.removing.isEmpty && applying.plan.adding.count == 1)
    applying.didAdd(staged.id, list: saved)
    check("after it adds a link the list is Reddit's and the draft is gone",
          applying.current == saved && !applying.hasChanges)

    // Requests, through a stubbed transport.
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ProfileEditStub.self]
    let stubbed = URLSession(configuration: configuration)
    let webSession = WebSessionCredential(username: "exampleuser",
                                          cookieHeader: "reddit_session=abc; csrf_token=synthetic-csrf; loid=1", modhash: nil)

    ProfileEditStub.captured = []
    ProfileEditStub.respond = { _ in setFixture }
    let afterAdd = try await ProfileSocialLinksService.add(SocialLinkDraft(type: .instagram, handle: "@exampleuser"),
                                                           session: webSession, urlSession: stubbed)
    let addRequest = ProfileEditStub.captured.last
    let addBody = json(addRequest?.body ?? Data())
    let addInput = ((addBody["variables"] as? [String: Any])?["input"] as? [String: Any])?["socialLinks"] as? [[String: String]]
    check("adding a link posts SetProfileSocialLinks to the Shreddit GraphQL endpoint",
          addRequest?.url.absoluteString == "https://www.reddit.com/svc/shreddit/graphql" && addRequest?.method == "POST"
          && addBody["operation"] as? String == "SetProfileSocialLinks"
          && addInput == [["type": "INSTAGRAM", "handle": "exampleuser"]])
    check("...with the csrf_token cookie's value in the body, and the cookie, origin and referer",
          addBody["csrf_token"] as? String == "synthetic-csrf"
          && addRequest?.headers["Cookie"] == webSession.cookieHeader
          && addRequest?.headers["Content-Type"] == "application/json"
          && addRequest?.headers["Origin"] == "https://www.reddit.com"
          && addRequest?.headers["Referer"] == "https://www.reddit.com/settings/profile")
    check("...and returns the list Reddit answers with", afterAdd == saved)

    ProfileEditStub.respond = { _ in deleteFixture }
    let afterRemove = try await ProfileSocialLinksService.remove(ids: ["00000000-0000-4000-8000-000000000002"],
                                                                 session: webSession, urlSession: stubbed)
    let removeBody = json(ProfileEditStub.captured.last?.body ?? Data())
    check("removing posts DeleteProfileSocialLinks with the ids",
          removeBody["operation"] as? String == "DeleteProfileSocialLinks"
          && ((removeBody["variables"] as? [String: Any])?["input"] as? [String: Any])?["socialLinkIds"] as? [String]
              == ["00000000-0000-4000-8000-000000000002"]
          && afterRemove.count == 1)

    // The settings page.
    let pageFixture = try Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/profile-settings-page.html"))
    let pageHTML = String(decoding: pageFixture, as: UTF8.self)
    let page = ProfileSettingsPage.parse(html: pageHTML)
    check("the page's initialState gives the current links with their ids, entities decoded",
          page?.socialLinks.map(\.id) == ["00000000-0000-4000-8000-000000000001", "00000000-0000-4000-8000-000000000002",
                                          "00000000-0000-4000-8000-000000000003"]
          && page?.socialLinks.map(\.rawType) == ["CUSTOM", "INSTAGRAM", "DISCORD"]
          && page?.socialLinks[0].title == "Tom & Jerry's Site"
          && page?.socialLinks[0].outboundURL == "https://example.com/me?a=1&b=2"
          && page?.socialLinks[0].handle == nil && page?.socialLinks[1].handle == "exampleuser")
    check("...and the platforms in the page's order, with each one's fields",
          page?.platforms.count == 26 && page?.platforms.first?.type == "REDDIT" && page?.platforms.last?.type == "CUSTOM"
          && page?.platforms.first { $0.type == "KOFI" }?.displayName == "Kofi"
          && page?.platforms.first { $0.type == "INSTAGRAM" }?.input == .username(limit: 30)
          && page?.platforms.first { $0.type == "YOUTUBE" }?.input == .textAndURL(textLimit: 21, urlLimit: 250))
    check("the built-in table agrees with the page",
          page?.platforms == ProfileSocialPlatform.builtIn)
    let editableFromPage = page.flatMap { page in
        SocialLinkDraft(editing: page.socialLinks[2], platforms: page.platforms)
    }
    check("a link from the page edits as the fields its platform takes",
          editableFromPage?.platform.type == "DISCORD" && editableFromPage?.title == "Example Server"
          && editableFromPage?.url == "https://discord.gg/example" && editableFromPage?.handle == "")
    check("a row is named for its platform when it is a username, else for its text",
          page.map { page in page.socialLinks.map { $0.heading(in: page.platforms) } } == ["Tom & Jerry's Site", "Instagram", "Example Server"])
    let reshaped = ProfileSettingsPage.parse(html: """
        <settings-profile-section INITIALSTATE='{"socialPlatforms":[{"type":"NEWSITE","displayName":"New Site","fields":[{"type":"USERNAME","limit":12}]},\
        {"type":"ODD","displayName":"Odd","fields":[{"type":"SOMETHING","limit":1}]},{"type":"NOFIELDS"}],\
        "identity":{"redditor":{"profile":{"socialLinks":[{"id":"x1","type":"NEWSITE","title":"u","handle":"u","outboundUrl":null},{"title":"no id"},\
        {"id":"x2","type":"CUSTOM","title":"a &amp;quot; &#x27; &lt;b&gt; &bogus;","outboundUrl":"https://e.co"}]}}}}'>
        """)
    check("a platform the page adds is offered as it describes it; one with fields this app can't fill is left out",
          reshaped?.platforms == [ProfileSocialPlatform(type: "NEWSITE", displayName: "New Site", input: .username(limit: 12))]
          && reshaped?.socialLinks.map(\.id) == ["x1", "x2"])
    check("entities in the state decode in one pass, so an escaped entity stays text",
          reshaped?.socialLinks.last?.title == "a &quot; ' <b> &bogus;")
    check("an unknown platform's draft is limited by the page's limit",
          reshaped?.platforms.first.map { SocialLinkDraft(platform: $0, handle: String(repeating: "a", count: 13)).issues } == [.usernameTooLong(limit: 12)])
    check("a page without the element, or without readable state, is nil",
          ProfileSettingsPage.parse(html: "<html><body>Log in</body></html>") == nil
          && ProfileSettingsPage.parse(html: "<settings-profile-section initialState=\"{&quot;a\">") == nil
          && ProfileSettingsPage.parse(html: "<settings-profile-section-extra initialState=\"{}\">") == nil)
    ProfileEditStub.captured = []
    ProfileEditStub.respond = { _ in pageFixture }
    let fetched = try await ProfileSocialLinksService.fetchPage(session: webSession, urlSession: stubbed)
    let pageRequest = ProfileEditStub.captured.last
    check("the page is loaded with a GET of reddit.com/settings/profile carrying the session cookie",
          pageRequest?.url.absoluteString == "https://www.reddit.com/settings/profile" && pageRequest?.method == "GET"
          && pageRequest?.headers["Cookie"] == webSession.cookieHeader && pageRequest?.body.isEmpty == true
          && ProfileEditStub.captured.count == 1)
    check("...and read links and platforms from it", fetched == page)
    ProfileEditStub.respond = { _ in Data("<html>Log in</html>".utf8) }
    var unreadablePage: Error?
    do { _ = try await ProfileSocialLinksService.fetchPage(session: webSession, urlSession: stubbed) } catch { unreadablePage = error }
    check("a page without the profile settings is unreadable", unreadablePage as? ProfileSocialLinksError == .unreadable)
    ProfileEditStub.respond = { _ in Data("<html>Prove your humanity</html>".utf8) }
    var botCheck: Error?
    do { _ = try await ProfileSocialLinksService.fetchPage(session: webSession, urlSession: stubbed) } catch { botCheck = error }
    check("a bot-check page is a rate limit", botCheck as? ProfileSocialLinksError == .rateLimited)

    // Refusals.
    func failure(_ body: String, session: WebSessionCredential = webSession) async -> Error? {
        ProfileEditStub.respond = { _ in Data(body.utf8) }
        do { _ = try await ProfileSocialLinksService.remove(ids: ["x"], session: session, urlSession: stubbed); return nil } catch { return error }
    }
    let refused = await failure(#"{"data":{"deleteSocialLinks":{"ok":false,"errors":[{"message":"too many social links"}],"socialLinks":null}},"errors":[]}"#)
    check("a refused change surfaces Reddit's reason",
          refused.flatMap { UserFacingError.message(for: $0) } == "Too many social links.")
    let unexplained = await failure(#"{"data":{"deleteSocialLinks":{"ok":false,"errors":null,"socialLinks":null}},"errors":[]}"#)
    check("a refusal with no reason still says so",
          unexplained.flatMap { UserFacingError.message(for: $0) } == "Reddit didn't accept the change to your social links.")
    let unreadable = await failure(#"{"data":{},"errors":[]}"#)
    check("a reply without the field is unreadable", unreadable as? ProfileSocialLinksError == .unreadable)
    let noCSRF = await failure("{}", session: WebSessionCredential(username: "exampleuser", cookieHeader: "reddit_session=abc", modhash: nil))
    check("a session without a csrf_token cookie can't send", noCSRF as? ModmailWebService.ServiceError == .missingCSRFToken)

    // Without a web session.
    let credentials = InMemoryCredentialStore()
    try credentials.save(RedditCredential(accessToken: "tok", refreshToken: "rt",
                                          expiration: Date().addingTimeInterval(3600), isPermanent: true))
    let oauthAuth = RedditAuthClient(session: stubbed, credentialStore: credentials, webSessionStore: InMemoryWebSessionStore())
    let oauthRepository = RedditRepository(client: RedditAPIClient(auth: oauthAuth, session: stubbed))
    ProfileEditStub.captured = []
    var withoutSession: Error?
    do { _ = try await oauthRepository.fetchProfileSettingsPage() } catch { withoutSession = error }
    check("an account with no web session can't edit social links, and sends nothing",
          withoutSession as? ProfileSocialLinksError == .requiresWebSession && ProfileEditStub.captured.isEmpty)
}

// MARK: - Profile Visibility

@MainActor func checkProfileVisibility() async throws {
    func json(_ data: Data) -> [String: Any] { (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:] }
    let pageHTML = String(decoding: try Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/profile-settings-page.html")), as: UTF8.self)
    let visibility = ProfileSettingsPage.parse(html: pageHTML)?.visibility

    check("the page's preferences give what the profile shows, from the visibility section",
          visibility?.isHideAllContribution == false && visibility?.isHideProfileNsfw == true
          && visibility?.showsFollowerCount == true && visibility?.shownSubredditIDs == ["t5_exa", "t5_exc"])
    check("...and the communities the account is active in, in the page's order, the own profile first",
          visibility?.communities.map(\.id) == ["t5_exown", "t5_exa", "t5_exb", "t5_exc"]
          && visibility?.communities.first?.isProfile == true && visibility?.communities.first?.title == "Your profile posts"
          && visibility?.communities[1].title == "r/examplea" && visibility?.communities[1].iconURL == "https://www.example.invalid/a.png"
          && visibility?.communities[2].iconURL == nil)
    check("a switch the page reports DISABLED is locked; the others are not",
          visibility?.isFollowerCountLocked == true && visibility?.isNSFWLocked == false && visibility?.isActivityLocked == false)

    guard let visibility else { return }
    let current = visibility.edits
    check("some of the communities chosen reads as Customize, with those visible",
          current.activity == .customize && current.visibleIDs == ["t5_exa", "t5_exc"]
          && current.showsNSFW == false && current.showsFollowerCount == true)
    check("unchanged edits change nothing", !visibility.hasChanges(current))

    let everything = ProfileVisibility(communities: visibility.communities, isHideAllContribution: false, isHideProfileNsfw: false,
                                       shownSubredditIDs: [], showsFollowerCount: false)
    check("no chosen communities and no hide-all flag is Show all, with every community visible",
          everything.edits.activity == .showAll && everything.edits.visibleIDs.count == 4 && everything.edits.showsNSFW)
    let hidden = ProfileVisibility(communities: visibility.communities, isHideAllContribution: true, isHideProfileNsfw: false,
                                   shownSubredditIDs: ["t5_exa"], showsFollowerCount: false)
    check("the hide-all flag is Hide all whatever communities are listed", hidden.edits.activity == .hideAll)
    let allChosen = ProfileVisibility(communities: visibility.communities, isHideAllContribution: false, isHideProfileNsfw: false,
                                      shownSubredditIDs: visibility.communities.map(\.id), showsFollowerCount: false)
    check("every community chosen is Show all", allChosen.edits.activity == .showAll)

    func input(_ edits: ProfileVisibility.Edits, of state: ProfileVisibility = visibility) -> [String: Any] {
        state.privacyInput(for: edits).variables["input"] as? [String: Any] ?? [:]
    }
    let unchangedInput = input(current)
    check("the mutation sends the whole set, in the page's order, with isShowTopSubreddits true as the page does",
          unchangedInput["shownSubredditIds"] as? [String] == ["t5_exa", "t5_exc"]
          && unchangedInput["isHideAllContribution"] as? Bool == false && unchangedInput["isHideProfileNsfw"] as? Bool == true
          && unchangedInput["isShowTopSubreddits"] as? Bool == true && unchangedInput.count == 4)

    let showAll = visibility.settingActivity(.showAll, in: current)
    let showAllInput = input(showAll)
    check("Show all sends no chosen communities and no hide-all flag",
          showAllInput["shownSubredditIds"] as? [String] == [] && showAllInput["isHideAllContribution"] as? Bool == false
          && visibility.hasPrivacyChanges(showAll) && !visibility.hasFollowerCountChange(showAll))
    let hideAll = visibility.settingActivity(.hideAll, in: current)
    let hideAllInput = input(hideAll)
    check("Hide all sets the flag and sends no communities",
          hideAllInput["shownSubredditIds"] as? [String] == [] && hideAllInput["isHideAllContribution"] as? Bool == true)
    let custom = visibility.settingVisible(["t5_exb"], in: current)
    let customInput = input(custom)
    check("Customize sends the chosen communities",
          custom.activity == .customize && customInput["shownSubredditIds"] as? [String] == ["t5_exb"]
          && customInput["isHideAllContribution"] as? Bool == false)
    check("choosing every community is Show all, and choosing none is Hide all, as on reddit.com",
          visibility.settingVisible(Set(visibility.communities.map(\.id)), in: current).activity == .showAll
          && visibility.settingVisible([], in: current).activity == .hideAll
          && visibility.settingVisible(["t5_unknown"], in: current).activity == .hideAll)
    check("a chosen set in a different order is no change",
          !visibility.hasChanges(visibility.settingVisible(["t5_exc", "t5_exa"], in: current)))

    var nsfw = current
    nsfw.showsNSFW = true
    check("Show NSFW Activity off sends isHideProfileNsfw true, on sends false; only the privacy mutation changes",
          input(current)["isHideProfileNsfw"] as? Bool == true && input(nsfw)["isHideProfileNsfw"] as? Bool == false
          && visibility.hasPrivacyChanges(nsfw) && !visibility.hasFollowerCountChange(nsfw))
    var followers = current
    followers.showsFollowerCount = false
    check("the follower count is its own change and leaves the privacy mutation alone",
          visibility.hasFollowerCountChange(followers) && !visibility.hasPrivacyChanges(followers))
    let applied = visibility.applying(hideAll, privacy: true, followerCount: false)
    check("after a save the state is what was applied, and a follower change not yet applied stays pending",
          applied.edits.activity == .hideAll && applied.showsFollowerCount == visibility.showsFollowerCount
          && !applied.hasPrivacyChanges(hideAll))

    check("a page without preferences has no visibility",
          ProfileSettingsPage.parse(html: """
              <settings-profile-section initialState='{"identity":{"redditor":{"profile":{"socialLinks":[]}}}}'>
              """)?.visibility == nil)
    let fallback = ProfileSettingsPage.parse(html: """
        <settings-profile-section initialState='{"identity":{"preferences":{"isHideAllContribution":true},"redditor":{"profile":{"socialLinks":[]}}}}'>
        """)
    check("the profile section's own state is used when there is no visibility section",
          fallback?.visibility?.isHideAllContribution == true && fallback?.visibility?.communities.isEmpty == true
          && fallback?.visibility?.shownSubredditIDs.isEmpty == true)

    // Requests, through a stubbed transport.
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ProfileEditStub.self]
    let stubbed = URLSession(configuration: configuration)
    let webSession = WebSessionCredential(username: "exampleuser",
                                          cookieHeader: "reddit_session=abc; csrf_token=synthetic-csrf; loid=1", modhash: nil)

    ProfileEditStub.captured = []
    ProfileEditStub.respond = { _ in
        Data(#"{"data":{"updateProfilePrivacyPreferencesV2":{"ok":true,"errors":null}},"errors":[],"operation":"UpdateProfilePrivacyPreferencesV2"}"#.utf8)
    }
    try await ProfileVisibilityService.save(visibility.privacyInput(for: hideAll), session: webSession, urlSession: stubbed)
    let privacyRequest = ProfileEditStub.captured.last
    let privacyBody = json(privacyRequest?.body ?? Data())
    check("saving posts UpdateProfilePrivacyPreferencesV2 to the Shreddit GraphQL endpoint with the whole input",
          privacyRequest?.url.absoluteString == "https://www.reddit.com/svc/shreddit/graphql" && privacyRequest?.method == "POST"
          && privacyBody["operation"] as? String == "UpdateProfilePrivacyPreferencesV2"
          && privacyBody["csrf_token"] as? String == "synthetic-csrf"
          && ((privacyBody["variables"] as? [String: Any])?["input"] as? [String: Any]).map {
              $0["isHideAllContribution"] as? Bool == true && $0["isShowTopSubreddits"] as? Bool == true
                  && $0["shownSubredditIds"] as? [String] == [] && $0["isHideProfileNsfw"] as? Bool == true
          } == true)
    check("...with the cookie, origin and the settings page as referer",
          privacyRequest?.headers["Cookie"] == webSession.cookieHeader
          && privacyRequest?.headers["Origin"] == "https://www.reddit.com"
          && privacyRequest?.headers["Referer"] == "https://www.reddit.com/settings/profile")

    ProfileEditStub.respond = { _ in Data(#"{"data":{"updateAccountPreferences":{"ok":true,"errors":null}},"errors":[]}"#.utf8) }
    try await ProfileVisibilityService.saveFollowerCount(shown: false, session: webSession, urlSession: stubbed)
    let followerBody = json(ProfileEditStub.captured.last?.body ?? Data())
    check("the follower count posts UpdateAccountPreferences with showFollowersCount",
          followerBody["operation"] as? String == "UpdateAccountPreferences"
          && ((followerBody["variables"] as? [String: Any])?["input"] as? [String: Bool]) == ["showFollowersCount": false])
    ProfileEditStub.respond = { _ in Data(#"{"data":{},"errors":[]}"#.utf8) }
    var unverifiedShape = false
    do { try await ProfileVisibilityService.saveFollowerCount(shown: true, session: webSession, urlSession: stubbed); unverifiedShape = true } catch {}
    check("...and a reply without a payload is accepted, since the page itself only looks at errors", unverifiedShape)

    func failure(_ body: String, follower: Bool = false) async -> Error? {
        ProfileEditStub.respond = { _ in Data(body.utf8) }
        do {
            if follower {
                try await ProfileVisibilityService.saveFollowerCount(shown: true, session: webSession, urlSession: stubbed)
            } else {
                try await ProfileVisibilityService.save(visibility.privacyInput(for: current), session: webSession, urlSession: stubbed)
            }
            return nil
        } catch { return error }
    }
    let refused = await failure(#"{"data":{"updateProfilePrivacyPreferencesV2":{"ok":false,"errors":[{"message":"not allowed"}]}},"errors":[]}"#)
    check("a refused change surfaces Reddit's reason", refused.flatMap { UserFacingError.message(for: $0) } == "Not allowed.")
    let unexplained = await failure(#"{"data":{"updateProfilePrivacyPreferencesV2":{"ok":false,"errors":null}},"errors":[]}"#)
    check("a refusal with no reason still says so",
          unexplained.flatMap { UserFacingError.message(for: $0) } == "Reddit didn't accept the change to what your profile shows.")
    let missing = await failure(#"{"data":{},"errors":[]}"#)
    check("a reply without the mutation's payload is a failure", missing is ProfileVisibilityError)
    let warned = await failure(#"{"data":{"updateProfilePrivacyPreferencesV2":{"ok":true,"errors":null}},"errors":[],"extensions":{"warnings":[{"extensions":{"code":"FORBIDDEN"}}]}}"#)
    check("an ok reply carrying a warning is not taken as applied",
          warned.flatMap { UserFacingError.message(for: $0) }?.contains("FORBIDDEN") == true)
    let accountRefused = await failure(#"{"data":{"updateAccountPreferences":{"ok":false,"errors":[{"message":"nope"}]}},"errors":[]}"#, follower: true)
    check("a refused follower count change fails too", accountRefused is ProfileVisibilityError)

    // Without a web session.
    let credentials = InMemoryCredentialStore()
    try credentials.save(RedditCredential(accessToken: "tok", refreshToken: "rt",
                                          expiration: Date().addingTimeInterval(3600), isPermanent: true))
    let oauthAuth = RedditAuthClient(session: stubbed, credentialStore: credentials, webSessionStore: InMemoryWebSessionStore())
    let oauthRepository = RedditRepository(client: RedditAPIClient(auth: oauthAuth, session: stubbed))
    ProfileEditStub.captured = []
    var withoutSession: Error?
    do { try await oauthRepository.saveProfilePrivacy(visibility.privacyInput(for: current)) } catch { withoutSession = error }
    var withoutSessionFollowers: Error?
    do { try await oauthRepository.saveProfileFollowerCount(shown: true) } catch { withoutSessionFollowers = error }
    check("an account with no web session can't change them, and sends nothing",
          withoutSession as? ProfileVisibilityError == .requiresWebSession
          && withoutSessionFollowers as? ProfileVisibilityError == .requiresWebSession && ProfileEditStub.captured.isEmpty)
}

// MARK: - Avatar page

@MainActor func checkProfileAvatarWebPage() async throws {
    func url(_ string: String) -> URL { URL(string: string)! }

    let cookies = WebSessionCookies.cookies(
        fromHeader: "reddit_session=abc; __Host-example=1; token_v2=old; csrf_token=a=b; junk; =x",
        skipping: ["token_v2"])
    check("a session header becomes one cookie per pair, minus the skipped and the malformed",
          cookies.map(\.name) == ["reddit_session", "__Host-example", "csrf_token"])
    check("a cookie value keeps an '=' inside it",
          cookies.first { $0.name == "csrf_token" }?.value == "a=b")
    check("a __Host- cookie is host-only on www.reddit.com; the rest are .reddit.com",
          cookies.first { $0.name == "__Host-example" }?.domain == "www.reddit.com"
          && cookies.first { $0.name == "reddit_session" }?.domain == ".reddit.com"
          && cookies.allSatisfy { $0.isSecure && $0.path == "/" })

    check("the avatar page is reddit.com's profile settings",
          ProfileAvatarWeb.pageURL.absoluteString == "https://www.reddit.com/settings/profile")
    check("a redirect to Reddit's login means the session was refused",
          ProfileAvatarWeb.decision(for: url("https://www.reddit.com/login/?dest=%2Fsettings"), tapped: false, frame: .main) == .sessionRejected
          && ProfileAvatarWeb.decision(for: url("https://www.reddit.com/account/login"), tapped: false, frame: .main) == .sessionRejected
          && ProfileAvatarWeb.decision(for: url("https://www.reddit.com/loginhelp"), tapped: false, frame: .main) == .allow)
    check("a 401 or 403 from Reddit means the session was refused; other statuses and hosts do not",
          ProfileAvatarWeb.isSessionRefusal(statusCode: 403, url: url("https://www.reddit.com/settings/profile"))
          && ProfileAvatarWeb.isSessionRefusal(statusCode: 401, url: url("https://old.reddit.com/x"))
          && !ProfileAvatarWeb.isSessionRefusal(statusCode: 200, url: url("https://www.reddit.com/settings/profile"))
          && !ProfileAvatarWeb.isSessionRefusal(statusCode: 403, url: url("https://example.com/")))
    check("the page loads, and its other Reddit pages and sub-frames load, in the view",
          ProfileAvatarWeb.decision(for: ProfileAvatarWeb.pageURL, tapped: false, frame: .main) == .allow
          && ProfileAvatarWeb.decision(for: url("https://www.reddit.com/avatar"), tapped: true, frame: .main) == .allow
          && ProfileAvatarWeb.decision(for: url("https://example.com/captcha"), tapped: false, frame: .sub) == .allow
          && ProfileAvatarWeb.decision(for: url("about:blank"), tapped: false, frame: .sub) == .allow)
    check("signing out on the web is blocked",
          ProfileAvatarWeb.decision(for: url("https://www.reddit.com/logout"), tapped: true, frame: .main) == .cancel)
    check("a tapped link to another site opens outside the signed-in view; a script's redirect is dropped",
          ProfileAvatarWeb.decision(for: url("https://example.com/"), tapped: true, frame: .main) == .openInSystem
          && ProfileAvatarWeb.decision(for: url("https://example.com/"), tapped: false, frame: .newWindow) == .openInSystem
          && ProfileAvatarWeb.decision(for: url("https://example.com/"), tapped: false, frame: .main) == .cancel
          && ProfileAvatarWeb.decision(for: url("mailto:hi@example.com"), tapped: true, frame: .main) == .openInSystem
          && ProfileAvatarWeb.decision(for: url("reddit://open"), tapped: false, frame: .main) == .cancel)
    check("a reload returns to the Reddit page on screen, never the login or logout page",
          ProfileAvatarWeb.reloadURL(current: url("https://www.reddit.com/avatar")).absoluteString == "https://www.reddit.com/avatar"
          && ProfileAvatarWeb.reloadURL(current: url("https://www.reddit.com/login")) == ProfileAvatarWeb.pageURL
          && ProfileAvatarWeb.reloadURL(current: url("https://www.reddit.com/logout")) == ProfileAvatarWeb.pageURL
          && ProfileAvatarWeb.reloadURL(current: url("https://example.com/")) == ProfileAvatarWeb.pageURL
          && ProfileAvatarWeb.reloadURL(current: nil) == ProfileAvatarWeb.pageURL)
}
