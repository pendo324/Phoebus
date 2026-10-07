import SwiftUI
import PhoebusCore
import CoreImage

/// User profile: karma, tabbed post/comment history and trophies.
public struct UserProfileScreen: View {
    @Setting(NotificationBackendSettings.self) private var notificationBackendSettings
    let username: String
    let repository: RedditRepository
    let isOwnProfile: Bool
    /// Supplied only on your own profile, the only place the bar carries an "Accounts" button.
    var accountManager: AccountManager?
    @State private var showingAccounts = false
    /// Profile banner viewer (upstream #1186): tap the banner to see the
    /// uncropped original, or the supplied crop if that fails.
    @State private var showingBanner = false
    /// True while the immersive hero is on screen: the navigation bar is
    /// transparent so the artwork shows behind it, and returns once the art
    /// scrolls away (#1186).
    @State private var heroVisible = true
    @State private var bannerViewerURL: URL?

    @State private var user: RedditUser?
    @State private var errorMessage: String?
    // Reborn's social-link badges, scraped from Reddit's public profile page
    // HTML (no API field exposes them). Failures are silent: no band is shown.
    @State private var socialLinks: [SocialLink] = []
    /// Reborn "Profile Layout" wiring (`ProfileLayoutSettings.swift`);
    /// `profileHeader(user:)` reads every field this struct carries.
    @Setting(ProfileLayoutSettingsStore.storage) private var profileLayoutSettings

    public init(username: String, repository: RedditRepository,
                isOwnProfile: Bool = false, accountManager: AccountManager? = nil) {
        self.username = username
        self.repository = repository
        self.isOwnProfile = isOwnProfile
        self.accountManager = accountManager
    }

    enum ProfileTab: String, CaseIterable, Hashable {
        case overview = "Overview"
        case posts = "Posts"
        case comments = "Comments"
        case saved = "Saved"
        case friends = "Friends"
        case upvoted = "Upvoted"
        case downvoted = "Downvoted"
        case hidden = "Hidden"
        case trophies = "Trophies"
        case badges = "Badge Book"
        case multireddits = "Multis"

        /// Row icon per segment, shown as a navigation-row list under the header.
        /// Listing rows use accent blue RGB(75,150,247); the Moderator Zone row is
        /// green RGB(103,206,103) and its colour lives with its own row.
        var iconTint: Color { .accentColor }

        var systemImage: String {
            switch self {
            case .overview: return "list.bullet.rectangle"
            case .posts: return "doc.text"
            case .comments: return "bubble.right"
            case .saved: return "bookmark"
            case .friends: return "person.2"
            case .upvoted: return "arrow.up"
            case .downvoted: return "arrow.down"
            case .hidden: return "eye.slash"
            case .trophies: return "trophy"
            case .badges: return "medal"
            case .multireddits: return "square.stack"
            }
        }
    }

    public var body: some View {
        crashTrackedBody.onAppear { CrashRecorder.record(.openedProfile) }
    }

    @ViewBuilder private var crashTrackedBody: some View {
        // The status and navigation bars' height, read outside the list
        // that reaches behind them.
        GeometryReader { proxy in
            ProfileListingView(username: username, repository: repository, tab: .overview,
                               isOwnProfile: isOwnProfile,
                               header: AnyView(headerRows(chrome: proxy.safeAreaInsets.top)))
                // The hero reaches behind the status and navigation bars, so
                // the list starts at the very top of the screen.
                .ignoresSafeArea(.container, edges: usesHero ? .top : [])
                .onScrollGeometryChangeIfAvailable(for: Bool.self) { geo in
                    geo.contentOffset.y + geo.contentInsets.top < UIScreen.main.bounds.width * 0.64 - proxy.safeAreaInsets.top
                } action: { _, visible in
                    heroVisible = visible
                }
        }
        .toolbarBackground(usesHero && heroVisible ? .hidden : .automatic, for: .navigationBar)
        // Over the hero the bar is clear: iOS 26's blurred scroll edge would
        // draw a band of the artwork under it.
        .modifier(HiddenTopScrollEdge(hidden: usesHero && heroVisible))
        .navigationDestination(item: $subpage) { page in
            switch page {
            case .tab(let tab):
                ProfileTabDestination(username: username, repository: repository, tab: tab, isOwnProfile: isOwnProfile)
                    .navigationTitle(tab.rawValue)
            case .hiddenAndDeleted:
                HiddenContentScreen(username: username, repository: repository)
            case .gallery:
                GalleryViewScreen(subreddit: "", repository: repository)
            case .hiddenPosts:
                HiddenPostsScreen(username: username, repository: repository)
            case .recentlyRead:
                RecentlyReadScreen(repository: repository)
            case .moderatorZone:
                ModeratorZoneScreen(repository: repository)
            }
        }
        .apolloTracksForwardNavigation($subpage)
        .apolloOpensRedditTargetsHere()
        .apolloPopsOnTabReselection(item: $subpage)
        // Over the hero no title is shown; it appears once the artwork scrolls
        // away (Reborn's profile title fade).
        .navigationTitle(usesHero && heroVisible ? "" : (isOwnProfile || isNative ? username : "u/\(username)"))
        // INLINE, not large: a large title collapses away on scroll, leaving
        // the band blank. The title is the bare username on your own profile.
        .navigationBarTitleDisplayModeIfAvailable()
        .sheet(isPresented: $showingAccounts) {
            if let accountManager {
                NavigationStack {
                    AccountManagerScreen(accountManager: accountManager)
                }
            }
        }
        .toolbar {
            // Own-profile bar: "Accounts | <username> | •••".
            if isOwnProfile, let accountManager {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Accounts") { showingAccounts = true }
                        .accessibilityIdentifier("profile.accounts")
                }
            }
            if isOwnProfile {
                // Reborn's own-profile "•••" menu, unified rather than separate toolbar icons.
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { subpage = .gallery } label: {
                            Label("Gallery View", systemImage: "square.grid.2x2")
                        }
                        Button { subpage = .hiddenPosts } label: {
                            Label("Hidden Posts", systemImage: "eye.slash")
                        }
                        Button { subpage = .recentlyRead } label: {
                            Label("Recently Read", systemImage: "clock.arrow.circlepath")
                        }
                        Button {
                            editProfileURL = URL(string: "https://www.reddit.com/settings/profile")
                        } label: {
                            Label("Edit Profile", systemImage: "pencil")
                        }
                        if let url = URL(string: "https://www.reddit.com/user/\(username)") {
                            ShareLink(item: url) {
                                Label("Share Profile", systemImage: "square.and.arrow.up")
                            }
                        }
                        // Reborn avatar context-menu action.
                        Button {
                            PasteboardHelper.copy(username)
                        } label: {
                            Label("Copy Username", systemImage: "doc.on.doc")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                        .accessibilityLabel("More")
                    }
                    .accessibilityIdentifier("profile.overflowMenu")
                }
            }
            // Native is Apollo's stock bar: back / name / ••• only, so
            // Send Message moves into the menu.
            if !isOwnProfile, !isNative {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCompose = true
                    } label: {
                        Image(systemName: "envelope")
                        .accessibilityLabel("Send Message")
                    }
                }
            }
            if !isOwnProfile {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if isNative {
                            Button {
                                showingCompose = true
                            } label: {
                                Label("Send Message", systemImage: "envelope")
                            }
                        }
                        Button(role: .destructive) {
                            Task { await toggleBlock() }
                        } label: {
                            Label(isBlocked ? "Unblock User" : "Block User", systemImage: "nosign")
                        }
                        Button {
                            PasteboardHelper.copy(username)
                        } label: {
                            Label("Copy Username", systemImage: "doc.on.doc")
                        }
                        // The self-hosted backend's user watcher: a push for each new post
                        // by this user. Needs a registered backend; the user must allow followers.
                        if PushNotificationClient.deliveryActive(notificationBackendSettings),
                           PushRegistrationState.isRegistered(notificationBackendSettings) {
                            Button {
                                Task { await watchUser() }
                            } label: {
                                Label("Notify for New Posts", systemImage: "bell.badge")
                            }
                            .accessibilityIdentifier("profile.watchUser")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                        .accessibilityLabel("More")
                    }
                }
            }
        }
        .alert("New Post Notifications", isPresented: $watchUserMessage.isPresent()) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(watchUserMessage ?? "")
        }
        .apolloInAppBrowser(url: $editProfileURL)
        .apolloInAppBrowser(url: $socialLinkURL)
        .sheet(isPresented: $showingCompose) {
            ComposeMessageScreen(to: username, repository: repository) {
                showingCompose = false
            }
        }
        // Guarded as in `FeedScreen`'s `.task`: SwiftUI re-runs `.task` when a
        // screen reappears after a pop.
        .task {
            if user == nil {
                await load()
            }
        }
        // Refreshes the header when Profile Layout changed in Settings, as
        // `FeedScreen` does with its settings snapshot.
        .onAppear {
        }
    }

    /// Reborn renders up to 3 links as name pills and more as icon badges;
    /// here a single horizontally scrolling row of icon+name pills serves both.
    private var socialLinksBand: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(socialLinks) { link in
                    Button {
                        socialLinkURL = URL(string: link.urlString)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: SocialLinkScraper.systemImageName(forType: link.type))
                                .font(.caption)
                            Text(link.title)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.secondarySystemBackgroundIfAvailable))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("profile.socialLink.\(link.type)")
                }
            }
            .padding(.horizontal)
        }
        .accessibilityIdentifier("profile.socialLinksBand")
    }

    @State private var socialLinkURL: URL?

    /// A pushed profile subpage. Driven by an item binding rather than
    /// `NavigationLink` so the push is recorded for the back and
    /// forward page swipes.
    enum Subpage: Hashable {
        case tab(ProfileTab)
        case hiddenAndDeleted
        case gallery
        case hiddenPosts
        case recentlyRead
        case moderatorZone
    }
    @State private var subpage: Subpage?

    @State private var trophies: [RedditTrophy] = []

    @State private var isBlocked = false
    @State private var showingCompose = false
    /// Whether this (other) user exposes any public multireddits;
    /// drives whether the Multis segment is offered at all.
    @State private var hasPublicMultireddits = false
    /// Reborn "Edit Profile" row: opens Reddit's profile settings page, since
    /// no first-party profile-edit API exists.
    @State private var editProfileURL: URL?

    @State private var watchUserMessage: String?

    private func watchUser() async {
        do {
            let me = try await repository.fetchIdentity()
            let body = PushNotificationClient.watcherBody(type: "user", subreddit: nil, user: username, label: username)
            try await PushNotificationClient.createWatcher(settings: notificationBackendSettings, redditID: me.id, body: body)
            watchUserMessage = "You'll get a notification when u/\(username) posts."
        } catch let error as PushNotificationClient.BackendError where error.body.contains("unused argument") {
            // The backend's user-watcher create path currently fails server-side.
            watchUserMessage = "Your notification backend can't save user watchers yet (a bug in apollo-backend's user table insert). Subreddit and trending watchers work."
        } catch {
            watchUserMessage = error.localizedDescription
        }
    }

    private func toggleBlock() async {
        guard let user else { return }
        if isBlocked {
            try? await repository.unblockUser(username: username, containerFullname: user.name)
            isBlocked = false
        } else {
            try? await repository.blockUser(fullname: user.name)
            isBlocked = true
        }
    }

    /// The profile's rows as Apollo's table lists them: your own profile has
    /// Posts, Comments, Saved, Reborn's Hidden & Deleted (#1137), Friends,
    /// Upvoted, Downvoted, Hidden, Trophies; anyone else's Posts, Comments,
    /// Hidden & Deleted, Trophies, and their public multireddits when they have
    /// some. Overview is the listing below the rows and the Badge Book opens
    /// from its band.
    private var menuRows: [ProfileMenuRow] {
        if isOwnProfile {
            return [.tab(.posts), .tab(.comments), .tab(.saved), .hiddenAndDeleted, .tab(.friends),
                    .tab(.upvoted), .tab(.downvoted), .tab(.hidden), .tab(.trophies)]
        }
        // Multireddits sits above Trophies.
        var rows: [ProfileMenuRow] = [.tab(.posts), .tab(.comments), .hiddenAndDeleted]
        if hasPublicMultireddits { rows.append(.tab(.multireddits)) }
        rows.append(.tab(.trophies))
        return rows
    }

    /// Immersive layout with real banner artwork to show.
    private var usesHero: Bool {
        !isNative && profileLayoutSettings.headerImmersive && profileLayoutSettings.showBanner && user != nil
    }

    private var isNative: Bool { profileLayoutSettings.style == .native }

    /// Opens the banner fullscreen at its original size when Reddit
    /// serves it (`ProfileBannerURL.originalCandidate`), else the crop
    /// the profile supplied, mirroring upstream's fallback.
    private func openBanner(_ supplied: URL) async {
        let candidate = ProfileBannerURL.originalCandidate(supplied)
        var chosen = supplied
        if candidate != supplied {
            var request = URLRequest(url: candidate)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 6
            if let (_, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                chosen = candidate
            }
        }
        bannerViewerURL = chosen
        showingBanner = true
    }

    /// The rows above the Overview listing: header, menu, Moderator Zone
    /// and the OVERVIEW caption.
    @ViewBuilder
    private func headerRows(chrome: CGFloat) -> some View {
        Group {
            if let user, isNative {
                NativeProfileStats(user: user)
                    .contextMenu {
                        Button {
                            PasteboardHelper.copy(user.name)
                        } label: {
                            Label("Copy Username", systemImage: "doc.on.doc")
                        }
                    }
            } else if let user {
                profileHeader(user: user, chrome: chrome)
            } else {
                Color.clear.frame(height: usesHero ? chrome : 1)
            }
        }
        .profileFullBleedRow()
        ForEach(Array(menuRows.enumerated()), id: \.element) { index, row in
            ProfileMenuRowView(row: row, separator: index < menuRows.count - 1) {
                switch row {
                case .tab(let tab): subpage = .tab(tab)
                case .hiddenAndDeleted: subpage = .hiddenAndDeleted
                case .moderatorZone: subpage = .moderatorZone
                }
            }
            .profileFullBleedRow()
        }
        if isOwnProfile, user?.isMod == true {
            ProfileMenuRowView(row: .moderatorZone, separator: false) { subpage = .moderatorZone }
                .padding(.top, 20)
                .profileFullBleedRow()
        }
        ProfileOverviewCaption()
            .profileFullBleedRow()
    }

    /// Reborn's identity header:
    ///
    /// - Immersive: a 150pt banner band (the full-bleed hero when there is
    ///   artwork) with the 96pt avatar centred and hanging 48pt below it;
    ///   8pt under it the name, 28pt bold, and `u/name` in 15pt medium
    ///   when the display name differs; the body 10pt below, centred.
    /// - Classic: a 104pt banner, the avatar 15pt in, the name beside it
    ///   in 20pt bold; the body leading-aligned 16pt below.
    ///
    /// The body: Follow / Message on someone else's profile, the bio
    /// (three lines with more/less), social links, the Badge Book band
    /// and the three stat cards, then 14pt to the rows.
    @ViewBuilder
    private func profileHeader(user: RedditUser, chrome: CGFloat) -> some View {
        let immersive = profileLayoutSettings.headerImmersive
        let bannerHeight: CGFloat = profileLayoutSettings.showBanner ? (immersive ? 150 : 104) : 0
        // The hero's band is measured from below the bars it reaches behind.
        let top: CGFloat = usesHero ? chrome : 0
        let avatarTop = top + max(14, bannerHeight - 48)
        let bannerURL = user.bannerImage.flatMap(URL.init(string:))
        let displayName = Self.displayName(for: user)
        let showsHandle = displayName.caseInsensitiveCompare(user.name) != .orderedSame

        ZStack(alignment: .top) {
            if profileLayoutSettings.showBanner {
                Group {
                    if usesHero {
                        ProfileHeroArtwork(url: bannerURL,
                                           avatarURL: user.iconImage.flatMap { URL(string: $0.replacingOccurrences(of: "&amp;", with: "&")) })
                    } else if let bannerURL {
                        CachedAsyncImage(url: bannerURL, contentMode: .fill)
                            .frame(height: bannerHeight)
                            .frame(maxWidth: .infinity)
                            .clipped()
                    } else {
                        Color.gray.opacity(0.12).frame(height: bannerHeight)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard let bannerURL else { return }
                    Task { await openBanner(bannerURL) }
                }
                .accessibilityAddTraits(bannerURL == nil ? [] : .isButton)
                .accessibilityLabel("Profile banner")
                .apolloMediaPager(items: bannerViewerURL.map { [.image($0)] } ?? [],
                                  isPresented: $showingBanner, attachesTapGestures: false)
            }

            VStack(alignment: immersive ? .center : .leading, spacing: 0) {
                if immersive {
                    avatarView(user: user)
                        .padding(.top, avatarTop)
                    Text(displayName)
                        .font(.system(size: 28, weight: .bold))
                        .lineLimit(1)
                        .frame(height: 36)
                        .padding(.top, 8)
                        .padding(.horizontal, 24)
                    if showsHandle {
                        Text("u/\(user.name)")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(height: 20)
                            .padding(.top, 1)
                    }
                    Color.clear.frame(height: 10)
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        avatarView(user: user)
                            .padding(.top, avatarTop)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(displayName)
                                .font(.system(size: 20, weight: .bold))
                                .lineLimit(1)
                            if showsHandle {
                                Text("u/\(user.name)")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.top, bannerHeight > 0 ? bannerHeight + 4 : avatarTop + 30)
                    }
                    .padding(.horizontal, 15)
                    Color.clear.frame(height: 16)
                }
                profileBody(user: user, immersive: immersive)
                    .padding(.horizontal, immersive ? 24 : 15)
                Color.clear.frame(height: 14)
            }
            .frame(maxWidth: .infinity, alignment: immersive ? .center : .leading)
        }
        // Long-press anywhere on the header copies the username, as in Reborn.
        .contextMenu {
            Button {
                PasteboardHelper.copy(user.name)
            } label: {
                Label("Copy Username", systemImage: "doc.on.doc")
            }
        }
    }

    /// The profile's display name (`subreddit.title`), Reddit's `u_name`
    /// fallback read as the username.
    static func displayName(for user: RedditUser) -> String {
        guard let title = user.profileTitle, !title.isEmpty,
              title.caseInsensitiveCompare("u_" + user.name) != .orderedSame else { return user.name }
        return title
    }

    @ViewBuilder
    private func profileBody(user: RedditUser, immersive: Bool) -> some View {
        VStack(alignment: immersive ? .center : .leading, spacing: 0) {
            if !isOwnProfile, profileLayoutSettings.showActions {
                ProfileActionButtons(username: username, repository: repository) {
                    showingCompose = true
                }
                .padding(.bottom, 16)
            }
            if let about = user.publicDescription {
                ProfileBio(text: about, centered: immersive)
            }
            if profileLayoutSettings.showSocialLinks, !socialLinks.isEmpty {
                socialLinksBand
                    .padding(.top, 8)
            }
            if profileLayoutSettings.badgeBookEnabled {
                ProfileBadgeBookBand(trophies: trophies) {
                    subpage = .tab(.badges)
                }
                .padding(.top, 10)
            }
            if profileLayoutSettings.showStatCards {
                ProfileStatCards(user: user)
                    // The cards run to the rows' 15pt margin, past the
                    // body's 24pt.
                    .padding(.horizontal, immersive ? -9 : 0)
                    .padding(.top, 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: immersive ? .center : .leading)
    }

    /// `ProfileLayoutSettings.AvatarStyle`'s three clip shapes: Circle,
    /// Square (Reborn's 24% corners) and Full (unclipped).
    @ViewBuilder
    private func avatarView(user: RedditUser) -> some View {
        let size: CGFloat = 96
        let url = user.iconImage.flatMap { URL(string: $0.replacingOccurrences(of: "&amp;", with: "&")) }
        let image = Group {
            if let url {
                CachedAsyncImage(url: url, contentMode: .fill)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .background(Color.gray.opacity(0.15))
        switch profileLayoutSettings.avatarStyle {
        case .circle:
            image.clipShape(Circle())
        case .square:
            image.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        case .full:
            image
        }
    }

    private func load() async {
        // Clears an error from a previous attempt.
        errorMessage = nil
        do {
            user = try await repository.fetchUserProfile(username: username)
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
        // Probe up-front so the Multis segment can be hidden before
        // the user ever taps it (the tab's own loader can't gate the
        // picker that presents it).
        if !isOwnProfile {
            hasPublicMultireddits = ((try? await repository.fetchPublicMultireddits(username: username)) ?? []).isEmpty == false
        }
        // Best-effort: a scrape failure (network, page-shape mismatch, rate
        // limit) leaves the band empty rather than surfacing an error.
        socialLinks = (try? await SocialLinkService.fetchSocialLinks(username: username)) ?? []
        if profileLayoutSettings.badgeBookEnabled {
            trophies = (try? await repository.fetchTrophies(username: username, isOwnProfile: isOwnProfile)) ?? []
        }
    }
}

/// Fetches and displays the listing content for whichever profile tab
/// is selected — separated so switching tabs cleanly reloads.
/// Routes a tapped profile row to its real pushed destination - a post/
/// comment listing (`ProfileListingView`) for most tabs, or the
/// dedicated `FriendsListView` for Friends (a user list, not posts).
struct ProfileTabDestination: View {
    let username: String
    let repository: RedditRepository
    let tab: UserProfileScreen.ProfileTab
    var isOwnProfile: Bool = false

    var body: some View {
        if tab == .friends {
            FriendsListView(repository: repository)
        } else {
            ProfileListingView(username: username, repository: repository, tab: tab, isOwnProfile: isOwnProfile)
        }
    }
}

/// A plain list of the signed-in user's Reddit friends, each row navigating
/// to that user's profile. Adding friends is not implemented.
struct FriendsListView: View {
    let repository: RedditRepository
    @State private var friends: [ModeratorListedUser] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.footnote)
            }
            if friends.isEmpty && errorMessage == nil {
                Text("No friends").foregroundStyle(.secondary)
            }
            ForEach(friends) { friend in
                SettingsLink {
                    UserProfileScreen(username: friend.name, repository: repository)
                } label: {
                    Text("u/\(friend.name)")
                }
            }
        }
        .apolloFlatListAppearance()
        .navigationTitle("Friends")
        .apolloForwardSwipe()
        .task {
            if friends.isEmpty {
                await load()
            }
        }
    }

    private func load() async {
        // Clears an error from a previous attempt.
        errorMessage = nil
        do {
            friends = try await repository.fetchFriends()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}

/// The immersive profile hero (#1186).
///
/// The banner as full artwork across a width-derived canvas (0.64 x
/// width) from the top of the screen, behind the status and navigation
/// bars, faded progressively into the page through an 8-stop mask. Dark
/// pages fade further (0.65/0.45/0.35/0.18) than light ones
/// (0.92/0.80/0.65/0.32).
///
/// A profile without a banner gets Reborn's synthetic backdrop: a mesh of
/// three soft blobs around the accent's hue on a dark ground of it, under
/// the heavily blurred avatar.
struct ProfileHeroArtwork: View {
    let url: URL?
    var avatarURL: URL? = nil
    @Environment(\.colorScheme) private var colorScheme

    static let stops: [CGFloat] = [0.0, 0.40, 0.55, 0.64, 0.72, 0.84, 0.98, 1.0]
    static func alphas(lightPage: Bool) -> [Double] {
        lightPage ? [1, 1, 0.92, 0.80, 0.65, 0.32, 0, 0] : [1, 1, 0.65, 0.45, 0.35, 0.18, 0, 0]
    }

    var body: some View {
        GeometryReader { proxy in
            let alphas = Self.alphas(lightPage: colorScheme == .light)
            Group {
                if let url {
                    CachedAsyncImage(url: url, contentMode: .fill)
                } else {
                    synthetic(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .mask(
                LinearGradient(stops: zip(Self.stops, alphas).map {
                    .init(color: .white.opacity($0.1), location: $0.0)
                }, startPoint: .top, endPoint: .bottom))
        }
        .frame(height: UIScreen.main.bounds.width * 0.64)
        .accessibilityHidden(true)
    }

    private func synthetic(width: CGFloat, height: CGFloat) -> some View {
        var h: CGFloat = 0.72, s: CGFloat = 0.55, b: CGFloat = 0.6, a: CGFloat = 1
        UIColor(Color.apolloAccent).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        func color(_ hue: CGFloat, _ sat: CGFloat, _ bri: CGFloat) -> Color {
            Color(hue: Double(hue.truncatingRemainder(dividingBy: 1)), saturation: Double(min(1, sat)), brightness: Double(min(1, bri)))
        }
        func blob(_ c: Color, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> some View {
            RadialGradient(colors: [c.opacity(0.92), c.opacity(0)], center: UnitPoint(x: x, y: y),
                           startRadius: 0, endRadius: width * r)
        }
        // A default snoo is not used: it would only blur to grey.
        let usableAvatar = avatarURL.flatMap { $0.absoluteString.contains("avatar_default") ? nil : $0 }
        return ZStack {
            color(h, s * 0.85, max(0.12, b * 0.32))
            blob(color(h, s * 1.05, b * 1.05), 0.24, 0.28, 0.52)
            blob(color(h + 0.08, s, b * 1.1), 0.82, 0.22, 0.48)
            blob(color(h + 0.90, s * 0.95, b * 0.9), 0.58, 0.82, 0.58)
            if let usableAvatar {
                BlurredAvatarBackdrop(url: usableAvatar)
                    .frame(width: width, height: height)
                    .clipped()
            }
        }
    }
}

/// The avatar blurred with Core Image (sigma 22, as Reborn), aspect-filled
/// at 96% over the mesh. A pre-blurred bitmap rather than a live `.blur`,
/// which leaves a stray copy over the navigation bar once the header
/// scrolls away.
private struct BlurredAvatarBackdrop: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill().opacity(0.96)
            } else {
                Color.clear
            }
        }
        .task(id: url) { image = await Self.blurred(url) }
    }

    private static func blurred(_ url: URL) async -> UIImage? {
        var data = await ImageCache.shared.data(for: url)
        if data == nil, let (fetched, _) = try? await URLSession.shared.data(from: url) {
            data = fetched
            await ImageCache.shared.store(fetched, for: url)
        }
        guard let data else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let input = CIImage(data: data) else { return nil }
            let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: 22).cropped(to: input.extent)
            guard let cg = CIContext().createCGImage(blurred, from: input.extent) else { return nil }
            return UIImage(cgImage: cg)
        }.value
    }
}

private struct HiddenTopScrollEdge: ViewModifier {
    let hidden: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden(hidden, for: .top)
        } else {
            content
        }
    }
}
