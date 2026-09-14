import SwiftUI
import PhoebusCore

/// Reimplements Apollo-Reborn's "Hidden & Deleted" archive list (#1137).
///
/// Upstream shape, kept here:
///   - pushed from a native-looking profile row (see
///     `UserProfileScreen`'s `hiddenDeletedRow`),
///   - a Posts / Comments segmented control as the navigation title,
///     each tab keeping its own list,
///   - a determinate ring plus "Posts: <stage>" / "Comments: <stage>"
///     while loading. Posts are fetched first, then comments, never
///     both at once (Arctic Shift rate-limits concurrent requests),
///   - overview-style rows: author, score arrow, age, "<who> ·" and a
///     coloured DELETED / REMOVED / HIDDEN pill, then the archived
///     body, any archived media, and a grey context card holding the
///     post title and subreddit,
///   - tapping a row opens the live thread, since a deleted body can
///     still have a useful discussion around it,
///   - pull to refresh bypasses the one-hour cache.
struct HiddenContentScreen: View {
    let username: String
    let repository: RedditRepository

    @State private var tab: HiddenContentFinder.Kind = .post
    @State private var posts: [HiddenContentFinder.Item] = []
    @State private var comments: [HiddenContentFinder.Item] = []
    @State private var loading = false
    @State private var loadedOnce = false
    @State private var progress: Double = 0
    @State private var stage = ""
    @State private var errorMessage: String?
    @State private var threadTarget: InboxCommentTarget?
    @State private var detailItem: HiddenContentFinder.Item?
    @State private var viewer: HiddenContentViewerStart?

    private var items: [HiddenContentFinder.Item] { tab == .post ? posts : comments }

    var body: some View {
        List {
            ForEach(items) { item in
                HiddenContentRow(item: item, username: username, onOpenMedia: { index in
                    viewer = HiddenContentViewerStart(urls: item.mediaURLs.isEmpty ? [item.previewURL].compactMap { $0 } : item.mediaURLs, index: index)
                })
                .contentShape(Rectangle())
                .onTapGesture { open(item) }
                .contextMenu { menu(for: item) }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .overlay { statusOverlay }
        .refreshable { await load(force: true) }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Hidden and deleted content", selection: $tab) {
                    Text("Posts").tag(HiddenContentFinder.Kind.post)
                    Text("Comments").tag(HiddenContentFinder.Kind.comment)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityIdentifier("hiddenContent.tabs")
            }
        }
        .navigationBarTitleDisplayModeIfAvailable()
        .task {
            if !loadedOnce { await load(force: false) }
        }
        .alert("Couldn't Fetch Hidden Content", isPresented: $errorMessage.isPresent()) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        // Both pushes feed the forward stack, so a back swipe from a
        // thread or archived copy can be undone with a forward swipe.
        .apolloTracksForwardNavigation($threadTarget)
        .apolloTracksForwardNavigation($detailItem)
        .apolloForwardSwipe()
        .navigationDestination(item: $threadTarget) { target in
            CommentTreeScreen(subreddit: target.subreddit, postID: target.postID, repository: repository,
                              focusedCommentID: target.commentID.isEmpty ? nil : target.commentID)
        }
        .navigationDestination(item: $detailItem) { item in
            HiddenContentDetailScreen(item: item)
        }
        .fullScreenCoverIfAvailable(item: $viewer) { start in
            MediaPagerScreen(items: start.urls.map { .image($0) }, startIndex: start.index)
        }
        // Save All Media draws from the app root (`MainTabView`).

    }

    // MARK: Status

    @ViewBuilder private var statusOverlay: some View {
        if loading && items.isEmpty {
            VStack(spacing: 12) {
                HiddenContentProgressRing(progress: progress)
                    .frame(width: 56, height: 56)
                    .accessibilityLabel("Archive loading progress")
                    .accessibilityValue("\(Int(progress * 100))%")
                Text(stage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .offset(y: -12)
        } else if !loading && loadedOnce && items.isEmpty {
            // Upstream's verbatim empty/failed text.
            Text(failed ? "Couldn't load results. Pull down to try again."
                        : "No hidden or deleted \(tab == .post ? "posts" : "comments") found in the archive for this account.")
                .apolloFont(size: 15)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    @State private var failed = false

    // MARK: Loading

    private func load(force: Bool) async {
        guard !loading else { return }
        loading = true
        progress = 0
        defer { loading = false; loadedOnce = true }
        let get: HiddenContentFinder.RedditGET = { [repository] path, params in
            try await repository.rawGET(path: path, parameters: params)
        }
        do {
            let fetchedPosts = try await HiddenContentFinder.fetch(username: username, kind: .post, forceRefresh: force, redditGET: get) { fraction, text in
                Task { @MainActor in report(fraction * 0.5, "Posts: " + text) }
            }
            let fetchedComments = try await HiddenContentFinder.fetch(username: username, kind: .comment, forceRefresh: force, redditGET: get) { fraction, text in
                Task { @MainActor in report(0.5 + fraction * 0.5, "Comments: " + text) }
            }
            // One snapshot, committed only when both succeed.
            posts = fetchedPosts
            comments = fetchedComments
            failed = false
            report(1, "Loaded")
        } catch {
            // Loaded results survive a failed refresh.
            failed = posts.isEmpty && comments.isEmpty
            errorMessage = error.localizedDescription
        }
    }

    /// Progress only ever moves forward.
    private func report(_ fraction: Double, _ text: String) {
        withAnimation(.easeInOut(duration: 0.25)) { progress = max(progress, min(1, fraction)) }
        stage = text
    }

    // MARK: Actions

    private func open(_ item: HiddenContentFinder.Item) {
        guard let permalink = item.permalink,
              let target = Self.threadTarget(permalink: permalink) else {
            // No link to the live thread: show the archived copy.
            detailItem = item
            return
        }
        threadTarget = target
    }

    /// `/r/<sub>/comments/<post>/<slug>/<comment>/`, with the comment
    /// segment optional.
    static func threadTarget(permalink: String) -> InboxCommentTarget? {
        let parts = permalink.split(separator: "/").map(String.init)
        guard let r = parts.firstIndex(of: "r"), parts.count > r + 3, parts[r + 2] == "comments" else { return nil }
        let comment = parts.count > r + 5 ? parts[r + 5] : ""
        return InboxCommentTarget(subreddit: parts[r + 1], postID: parts[r + 3], commentID: comment)
    }

    @ViewBuilder private func menu(for item: HiddenContentFinder.Item) -> some View {
        Button {
            detailItem = item
        } label: {
            Label("View Archived Copy", systemImage: "archivebox")
        }
        if let url = Self.arcticShiftURL(for: item) {
            Link(destination: url) {
                Label("Open in Arctic Shift", systemImage: "safari")
            }
        }
        ShareLink(item: HiddenContentDetailScreen.shareText(for: item)) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        // Upstream's media menu: Save Image, plus Save All Media for
        // an album, through the shared batch.
        let media = item.mediaURLs
        if !media.isEmpty {
            Button {
                SaveAllMediaJob.shared.start([.image(media[0])])
            } label: {
                Label("Save Image", systemImage: "square.and.arrow.down")
            }
            if media.count > 1 {
                Button {
                    SaveAllMediaJob.shared.start(media.map { .image($0) })
                } label: {
                    Label(SaveAllMediaSummary.menuTitle, systemImage: SaveAllMediaSummary.menuSymbol)
                }
            }
        }
    }

    /// Arctic Shift has no per-item permalink; its search page runs an
    /// ID lookup from `?fun=ids&ids=<fullname>`.
    static func arcticShiftURL(for item: HiddenContentFinder.Item) -> URL? {
        var components = URLComponents(string: "https://arctic-shift.photon-reddit.com/search")
        components?.queryItems = [URLQueryItem(name: "fun", value: "ids"), URLQueryItem(name: "ids", value: item.fullName)]
        return components?.url
    }
}

struct HiddenContentViewerStart: Identifiable {
    let urls: [URL]
    let index: Int
    var id: String { "\(urls.first?.absoluteString ?? "")#\(index)" }
}

/// Apollo's circular progress look: a thin label-coloured
/// ring on a 16% track, clockwise from twelve o'clock.
struct HiddenContentProgressRing: View {
    let progress: Double
    var body: some View {
        GeometryReader { geo in
            let line = geo.size.width * 0.08
            ZStack {
                Circle().stroke(Color.primary.opacity(0.16), lineWidth: line)
                Circle().trim(from: 0, to: progress)
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: line, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            .padding(line / 2)
        }
    }
}

/// One archived item, laid out like Apollo's profile overview cell:
/// 14pt author/metadata, 15pt body, 14pt medium context title, an
/// 8pt band between rows.
struct HiddenContentRow: View {
    let item: HiddenContentFinder.Item
    let username: String
    var onOpenMedia: (Int) -> Void

    @State private var page = 0

    /// Apollo's pill background colors.
    private var pillColor: Color {
        switch item.reason {
        case .deleted: return Color(red: 1.0, green: 0.66, blue: 0.64)
        case .removed: return Color(red: 1.0, green: 0.71, blue: 0.42)
        case .hidden: return Color(red: 1.0, green: 0.84, blue: 0.55)
        }
    }

    private var author: String {
        if let a = item.author, !a.isEmpty, a != "[deleted]" { return a }
        return username
    }

    private var media: [URL] { item.mediaURLs.isEmpty ? [item.previewURL].compactMap { $0 } : item.mediaURLs }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header.padding(.horizontal, 15)
            if let text = bodyText {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(item.body?.isEmpty == false ? .primary : .secondary)
                    .padding(.horizontal, 15)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !media.isEmpty { mediaPager }
            contextCard.padding(.horizontal, 15)
        }
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(Color.systemBackgroundIfAvailable)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.secondarySystemBackgroundIfAvailable).frame(height: 8).offset(y: 8)
        }
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }

    /// Posts hide an empty body rather than repeating the title; a
    /// comment with nothing archived says so.
    private var bodyText: String? {
        if let body = item.body, !body.isEmpty { return body }
        return item.kind == .post ? nil : "No text in the archive"
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(author).apolloFont(size: 14, weight: .medium).lineLimit(1)
            if let score = item.score {
                Text("\(score < 0 ? "↓" : "↑") \(abs(score).apolloAbbreviated)")
                    .apolloFont(size: 14).foregroundStyle(.tertiary)
            }
            if let date = item.createdDate {
                Text(Self.age(date)).apolloFont(size: 14).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            if let who = item.removalDetail ?? (item.reason == .deleted ? "Author" : nil) {
                Text("\(who) ·").apolloFont(size: 14).foregroundStyle(.tertiary).lineLimit(1)
            }
            Text(item.reason.pillText)
                .apolloFont(size: 12)
                .foregroundStyle(.black)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(pillColor))
                .accessibilityIdentifier("hiddenContent.pill")
        }
    }

    private var mediaPager: some View {
        let ratio = (item.previewAspectRatio.isFinite && item.previewAspectRatio >= 0.1 && item.previewAspectRatio <= 10) ? item.previewAspectRatio : 1
        return TabView(selection: $page) {
            ForEach(Array(media.enumerated()), id: \.offset) { index, url in
                // Checked for a host's "image removed" card, see
                // `ArchivedImagePage`.
                ArchivedImagePage(url: url)
                    .contentShape(Rectangle())
                    .onTapGesture { onOpenMedia(index) }
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .aspectRatio(ratio, contentMode: .fit)
        .overlay(alignment: .topTrailing) {
            if media.count > 1 {
                Text("\(page + 1)/\(media.count)")
                    .apolloFont(size: 12, weight: .semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.7)))
                    .padding(10)
            }
        }
    }

    @ViewBuilder private var contextCard: some View {
        let title = item.kind == .post ? item.title : item.parentPostTitle
        let sub = item.subreddit.map { $0.hasPrefix("r/") ? String($0.dropFirst(2)) : $0 }
        if (title?.isEmpty == false) || (sub?.isEmpty == false) {
            VStack(alignment: .leading, spacing: 8) {
                if let title, !title.isEmpty {
                    Text(title).apolloFont(size: 14, weight: .medium).foregroundStyle(.secondary)
                }
                if let sub, !sub.isEmpty {
                    Text(sub).apolloFont(size: 14).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondarySystemBackgroundIfAvailable))
        }
    }

    /// Upstream's compact age format.
    static func age(_ date: Date, now: Date = Date()) -> String {
        let age = max(0, now.timeIntervalSince(date))
        let year: Double = 365 * 86400
        if age >= year { return "\(Int(age / year))y" }
        if age >= 86400 { return "\(Int(age / 86400))d" }
        if age >= 3600 { return "\(Int(age / 3600))h" }
        if age >= 60 { return "\(Int(age / 60))m" }
        return "\(Int(age))s"
    }
}

/// The archived copy of one item: title "Deleted/Removed Post/Comment",
/// a subreddit button, the archived text, plus Share and Open in
/// Arctic Shift.
struct HiddenContentDetailScreen: View {
    let item: HiddenContentFinder.Item
    @Environment(\.openURL) private var openURL

    private var title: String {
        let noun = item.kind == .post ? "Post" : "Comment"
        switch item.reason {
        case .removed: return "Removed \(noun)"
        case .deleted: return "Deleted \(noun)"
        // Upstream only ever reaches this screen for removed/deleted
        // items; a hidden one reads as what it is.
        case .hidden: return "Hidden \(noun)"
        }
    }

    /// Apollo's archived-text format.
    static func archivedText(for item: HiddenContentFinder.Item) -> String {
        var text = ""
        if let t = item.title, !t.isEmpty { text += t + "\n\n" }
        if let who = item.removalDetail, !who.isEmpty {
            text += "\(item.reason == .deleted ? "Deleted by" : "Removed by"): \(who)\n\n"
        }
        text += (item.body?.isEmpty == false ? item.body! : "(no body text in the archive)")
        return text
    }

    /// Apollo's share text: "r/<sub>\n\n" then the archived text.
    static func shareText(for item: HiddenContentFinder.Item) -> String {
        let sub = item.subreddit.map { $0.hasPrefix("r/") ? String($0.dropFirst(2)) : $0 } ?? ""
        return (sub.isEmpty ? "" : "r/\(sub)\n\n") + archivedText(for: item)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let sub = item.subreddit.map({ $0.hasPrefix("r/") ? String($0.dropFirst(2)) : $0 }), !sub.isEmpty {
                    Button {
                        if let url = URL(string: "https://www.reddit.com/r/\(sub)") { openURL(url) }
                    } label: {
                        HStack {
                            Text(sub).font(.subheadline).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondarySystemBackgroundIfAvailable))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(sub) subreddit")
                    .padding(.top, 12)
                    .padding(.horizontal, 16)
                }
                Text(Self.archivedText(for: item))
                    .apolloFont(size: 16)
                    .textSelection(.enabled)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayModeIfAvailable()
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let url = HiddenContentScreen.arcticShiftURL(for: item) {
                    Button { openURL(url) } label: { Image(systemName: "safari") }
                        .accessibilityLabel("Open in Arctic Shift")
                }
                ShareLink(item: Self.shareText(for: item)) { Image(systemName: "square.and.arrow.up") }
            }
        }
    }
}
