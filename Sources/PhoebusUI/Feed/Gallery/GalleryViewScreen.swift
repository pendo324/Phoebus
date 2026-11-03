import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import PhoebusCore

/// Reborn's "Gallery View": a waterfall/grid photo browser for a
/// subreddit, feed or Saved list's image/video posts, with fullscreen paging,
/// sorting, sharing and media saving inherited from the feed it was
/// opened from. Filters the feed down to posts with viewable media via
/// `GalleryPostMedia`.
public struct GalleryViewScreen: View {
    let subreddit: String
    /// The multireddit this gallery is showing, if opened from one. A
    /// multireddit has no subreddit name, so this stands in for it.
    let multiredditPath: String?
    /// The feed's own title, so the gallery says where it came from
    /// rather than a bare "Gallery".
    let feedTitle: String?
    /// The sort the feed was already showing, so the gallery matches
    /// (rather than always showing Hot regardless of the feed's sort).
    let initialSort: String
    let initialTimeframe: String
    /// Posts the feed has ALREADY loaded.
    ///
    /// Handed over so the gallery opens populated and instant, instead
    /// of showing nothing while it refetches a listing the feed is
    /// already holding. A sort change still refetches.
    let initialPosts: [RedditPost]
    let repository: RedditRepository
    /// Set when this gallery shows your Saved posts, or one Saved category,
    /// instead of a subreddit listing (Reborn `#1440`).
    private let savedUsername: String?
    @State private var savedScope: SavedGalleryScope

    @State private var posts: [RedditPost] = []
    @State private var errorMessage: String?
    /// True while the first fetch is in flight, so the empty state
    /// ("No media posts") does not show during the load.
    @State private var isLoading = false
    /// Pagination cursor and state, mirroring the grid's `loadMore` path:
    /// the gallery loads more as you scroll.
    @State private var afterToken: String?
    @State private var isLoadingMore = false
    @State private var isExhausted = false
    /// Transient footer line: "Loading more…" while a page is in flight,
    /// "That's everything" when the listing is exhausted, "Couldn't load
    /// more" on failure.
    @State private var footerText: String?
    @State private var sort: String
    @State private var timeframe: String
    @State private var selectedPost: RedditPost?
    /// The tapped tile's index, item-based so the viewer opens on the right
    /// page (a separate index + Bool presents the cover before the index
    /// lands; see `GalleryMediaView`).
    @State private var viewerStart: GalleryViewerStart?

    private struct GalleryViewerStart: Identifiable {
        let id: Int
    }
    /// Gallery View media filter (Reborn's `allowedKinds`); an empty set
    /// means all kinds.
    @State private var allowedKinds: Set<GalleryPostMedia.Kind> = []
    @Setting(GeneralSettingsStore.storage) private var generalSettings
    /// Reborn's 5-step tile size (`ApolloGalleryTileSizeV2`).
    @Setting(GalleryTileSize.storage) private var tileSizeIndex
    /// The tile to keep in view across a size change, picked when the
    /// size changes and consumed once the new column count has laid out.
    @State private var sizeChangeAnchor: String?
    @State private var visibleTiles = VisibleTileTracker()
    /// Which tiles may play, shared by every tile in the grid.
    @StateObject private var playback = GalleryTilePlayback()

    public init(
        subreddit: String,
        multiredditPath: String? = nil,
        feedTitle: String? = nil,
        sort: String = "hot",
        timeframe: String = "day",
        posts: [RedditPost] = [],
        repository: RedditRepository
    ) {
        self.subreddit = subreddit
        self.multiredditPath = multiredditPath
        self.feedTitle = feedTitle
        self.initialSort = sort
        self.initialTimeframe = timeframe
        self.initialPosts = posts
        self.repository = repository
        self.savedUsername = nil
        _savedScope = State(initialValue: SavedGalleryScope(category: nil, assignments: [:]))
        _sort = State(initialValue: sort)
        _timeframe = State(initialValue: timeframe)
        _posts = State(initialValue: GalleryPostMedia.filterMediaPosts(posts))
    }

    /// Gallery View of Saved (`category` nil) or of one Saved category.
    /// `loadedPosts` and `after` are what the Saved screen already holds, so
    /// the gallery opens populated and continues from its cursor.
    public init(savedUsername: String, category: String?, loadedPosts: [RedditPost] = [],
                after: String? = nil, repository: RedditRepository) {
        var scope = SavedGalleryScope(category: category, assignments: SavedCategoryStore.allAssignments())
        let media = GalleryPostMedia.filterMediaPosts(scope.admit(loadedPosts))
        self.subreddit = ""
        self.multiredditPath = nil
        self.feedTitle = nil
        self.initialSort = "new"
        self.initialTimeframe = "all"
        self.initialPosts = []
        self.repository = repository
        self.savedUsername = savedUsername
        let handedOver = !loadedPosts.isEmpty
        _afterToken = State(initialValue: handedOver ? after : nil)
        _isExhausted = State(initialValue: scope.isEmptyByConstruction
            || (handedOver && scope.outcome(gained: media.count, after: after, previousAfter: nil).exhausted))
        _savedScope = State(initialValue: scope)
        _sort = State(initialValue: "new")
        _timeframe = State(initialValue: "all")
        _posts = State(initialValue: media)
    }

    public var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { scroller in
            ScrollView {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).padding()
                }
                if filteredTiles.isEmpty && errorMessage == nil {
                    if isLoading {
                        ApolloLoadingCell()
                            .padding(.top, 40)
                    } else {
                        // Empty-state copy distinguishes "this feed has no media" from "your
                        // filter hid it all", and names the feed and its sort.
                        Text(emptyStateText)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 32)
                            .padding(.top, 60)
                    }
                }
                let columns = GalleryTileSize.columns(forWidth: Double(proxy.size.width), sizeIndex: tileSizeIndex)
                WaterfallGrid(items: filteredTiles, columns: columns, spacing: Self.tileSpacing, aspectRatio: { $0.aspectRatio ?? 1.0 }) { tile in
                    Button {
                        // Opens Reborn's own viewer in place, not the post screen,
                        // which stays one tap away via the viewer's info card.
                        viewerStart = GalleryViewerStart(id: filteredTiles.firstIndex(where: { $0.id == tile.id }) ?? 0)
                    } label: {
                        GalleryGridCell(tile: tile, nsfwBlurOverride: generalSettings.nsfwBlurOverride, playback: playback)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        visibleTiles.appeared(tile.id)
                        // Load-ahead: tops up when the visible index is within
                        // `columnCount * 3` rows of the end, so fast scrolling does not
                        // outrun the fetch and hit the grid's end.
                        guard let index = filteredTiles.firstIndex(where: { $0.id == tile.id })
                        else { return }
                        let slack = columns * 3
                        if index >= filteredTiles.count - slack {
                            Task { await loadMore() }
                        }
                    }
                    .onDisappear { visibleTiles.disappeared(tile.id) }
                    .galleryTileFrame(id: tile.id, in: Self.gridSpace)
                }
                .padding(.horizontal, Self.tileSpacing)
                // Footer: a transient line under the tiles reporting pagination state.
                if let footerText {
                    HStack(spacing: 8) {
                        if isLoadingMore { ProgressView() }
                        Text(footerText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .accessibilityIdentifier("gallery.footer")
                }
            }
            .coordinateSpace(name: Self.gridSpace)
            .onPreferenceChange(GalleryTileFramesKey.self) { playback.setFrames($0) }
            .onAppear { playback.setViewport(height: Double(proxy.size.height)) }
            .onChange(of: proxy.size.height) { _, height in playback.setViewport(height: Double(height)) }
            // Pinch to step the tile size; applied when the pinch ends.
            .simultaneousGesture(
                MagnifyGesture().onEnded { value in
                    setTileSize(GalleryTileSize.sizeIndex(afterPinchScale: Double(value.magnification), from: tileSizeIndex))
                })
            .onChange(of: tileSizeIndex) { _, _ in
                guard let anchor = sizeChangeAnchor else { return }
                sizeChangeAnchor = nil
                // After the new columns have laid out.
                DispatchQueue.main.async { scroller.scrollTo(anchor, anchor: .center) }
            }
            }
        }
        // The screen titles itself "Gallery"; the feed name appears only in
        // the empty-state and error copy (e.g. "No media found in r/swift
        // (Hot)").
        .navigationTitle("Gallery")
        // Apollo's back/forward page swipes.
        .apolloForwardSwipe()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Reborn's minus/plus pair: smaller/larger tiles, bounded at both ends.
            ToolbarItem(placement: .primaryAction) {
                Button { setTileSize(GalleryTileSize.stepped(tileSizeIndex, by: -1)) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .disabled(tileSizeIndex <= 0)
                .accessibilityLabel("Smaller gallery tiles")
                .accessibilityValue("Size \(tileSizeIndex + 1) of \(GalleryTileSize.count)")
                .accessibilityIdentifier("gallery.smallerTiles")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { setTileSize(GalleryTileSize.stepped(tileSizeIndex, by: 1)) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .disabled(tileSizeIndex >= GalleryTileSize.count - 1)
                .accessibilityLabel("Larger gallery tiles")
                .accessibilityValue("Size \(tileSizeIndex + 1) of \(GalleryTileSize.count)")
                .accessibilityIdentifier("gallery.largerTiles")
            }
            // Saved follows its own saved order, so there is nothing to sort.
            if savedUsername == nil {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    // The sort set includes Best and Controversial. "best" is home-only,
                    // as in `FeedScreen.availableSorts`: offering it on a subreddit or
                    // multireddit gallery would send a sort the listing does not support.
                    ForEach(availableSorts, id: \.self) { s in
                        // Top and Controversial open a time-window submenu, like Apollo's
                        // native menu.
                        if Self.windowedSorts.contains(s) {
                            Menu {
                                ForEach(Self.topWindows, id: \.value) { window in
                                    // Every window row carries its own icon (one asset per window).
                                    // No checkmark on an icon row: Reborn's icon rows never carry one;
                                    // only icon-less text rows do.
                                    Button {
                                        sort = s
                                        timeframe = window.value
                                        Task { await load() }
                                    } label: {
                                        Label(window.title,
                                              systemImage: FeedScreen.iconName(forTimeframe: window.value))
                                    }
                                }
                            } label: {
                                Label { Text(s.capitalized) } icon: { ApolloIconImage(FeedScreen.iconName(forSort: s)) }
                            }
                        } else {
                            // Each row keeps its own per-sort icon rather than
                            // swapping to a checkmark when active.
                            Button {
                                sort = s
                                Task { await load() }
                            } label: {
                                Label { Text(s.capitalized) } icon: { ApolloIconImage(FeedScreen.iconName(forSort: s)) }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                    .accessibilityLabel("Sort")
                }
            }
            }
            // Filter menu (Photos/GIFs/Videos) with Reborn's titles and SF Symbols,
            // and a filled glyph while filtering.
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(GalleryPostMedia.Kind.allCases, id: \.self) { kind in
                        // A multi-select filter, so unlike the sort rows it shows its on/off
                        // state: it keeps its per-kind icon and expresses state as a `Toggle`
                        // (UIKit renders a trailing checkmark). A separate "N loaded" subtitle
                        // line is omitted at N=0, and a row is disabled when it is the only
                        // kind still on, since tapping it would leave the filter showing
                        // nothing.
                        let n = count(of: kind)
                        GalleryFilterRow(
                            kind: kind,
                            loadedCount: n,
                            isOn: Binding(
                                get: { allowedKinds.isEmpty || allowedKinds.contains(kind) },
                                set: { _ in toggle(kind) }
                            ),
                            isDisabled: allowedKinds == [kind])
                    }
                } label: {
                    Image(systemName: allowedKinds.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    .accessibilityLabel("Filter Media")
                }
                .accessibilityIdentifier("gallery.filterMenu")
            }
        }
        .task {
            if savedUsername != nil { await startSaved(); return }
            // Only fetch if the feed handed nothing over, so the gallery does not
            // flash empty before repopulating. Handed-over posts have no
            // pagination cursor, so `loadMore` cannot continue from them; a quiet
            // background first-page fetch supplies one while the visible tiles
            // stay on screen.
            guard posts.isEmpty else {
                if afterToken == nil && !isExhausted {
                    await loadInitialCursor()
                }
                return
            }
            await load()
        }
        .refreshable { await load() }
        .fullScreenCoverIfAvailable(item: $viewerStart) { start in
            GalleryImageViewerScreen(
                tiles: filteredTiles,
                startIndex: start.id,
                repository: repository,
                // The info card taps through to the real post.
                onOpenPost: { selectedPost = $0 })
        }
        .apolloTracksForwardNavigation($selectedPost)
        .navigationDestination(isPresented: $selectedPost.isPresent()) {
            if let selectedPost {
                PostDetailScreen(post: selectedPost, repository: repository)
            }
        }
        // Gallery View exempts itself from the app's portrait lock: all
        // orientations but upside-down on this screen and its viewer.
        .galleryOrientationOverride()
    }

    private var filteredTiles: [GalleryTile] {
        guard !allowedKinds.isEmpty else { return allTiles }
        return allTiles.filter { allowedKinds.contains($0.kind) }
    }

    /// The flattened tile list the grid and viewer share; see
    /// `GalleryTile`.
    private var allTiles: [GalleryTile] {
        GalleryTile.tiles(for: posts)
    }

    private func count(of kind: GalleryPostMedia.Kind) -> Int {
        allTiles.filter { $0.kind == kind }.count
    }

    static let gridSpace = "galleryGrid"

    /// Tile gutter, 3pt.
    static let tileSpacing = CGFloat(GalleryTileSize.spacing)

    /// Changes the tile size, remembering a tile near the middle of the
    /// screen so the grid stays on it.
    private func setTileSize(_ next: Int) {
        let clamped = GalleryTileSize.clamped(next)
        guard clamped != tileSizeIndex else { return }
        sizeChangeAnchor = visibleTiles.middleTile(in: filteredTiles.map(\.id))
        $tileSizeIndex.update { $0 = clamped }
    }

    private func toggle(_ kind: GalleryPostMedia.Kind) {
        if allowedKinds.isEmpty {
            // All kinds on: tapping one narrows to just that kind.
            allowedKinds = [kind]
        } else if allowedKinds == [kind] {
            // The menu disables a row that is the sole active kind (see the
            // `.disabled` above), so this branch is a safety net for other
            // callers of `toggle(_:)`.
            return
        } else if allowedKinds.contains(kind) {
            allowedKinds.remove(kind)
        } else {
            allowedKinds.insert(kind)
        }
    }

    /// Top and Controversial open a time-window submenu; every other sort
    /// is a plain row.
    static let windowedSorts: Set<String> = ["top", "controversial"]

    /// The window list and its titles, with Reddit's `t` parameter values.
    static let topWindows: [(title: String, value: String)] = [
        ("Today", "day"),
        ("This Week", "week"),
        ("This Month", "month"),
        ("This Year", "year"),
        ("All Time", "all"),
    ]

    /// Same rule as `FeedScreen.availableSorts`: "best" is the home
    /// feed's own sort and is not valid for a subreddit or multireddit
    /// listing.
    private var availableSorts: [String] {
        (subreddit.isEmpty && multiredditPath == nil)
            ? ["best", "hot", "new", "top", "rising", "controversial"]
            : ["hot", "top", "new", "rising", "controversial"]
    }

    /// Empty-state text, including the feed's description ("Home",
    /// "r/<slug>", "m/<name>", "u/<name>") and current sort ("Top: This
    /// Week" and friends).
    private var emptyStateText: String {
        if !posts.isEmpty {
            return """
            Nothing matches the current filter.
            \(allTiles.count) items are loaded — tap the filter button to widen it.
            """
        }
        if savedUsername != nil {
            // Later pages can still bring media: Saved keeps walking quietly.
            return isLoadingMore
                ? "No media found yet in \(sourceDescription)."
                : "No media found in \(sourceDescription)."
        }
        return "No media found in \(sourceDescription) (\(sortDisplayName))."
    }

    /// Verbatim source-description shapes from Reborn.
    private var sourceDescription: String {
        if savedUsername != nil { return savedScope.sourceDescription }
        if let multiredditPath {
            return "m/" + (multiredditPath.split(separator: "/").last.map(String.init) ?? multiredditPath)
        }
        return subreddit.isEmpty ? "Home" : "r/\(subreddit)"
    }

    /// Verbatim sort display-name from Reborn.
    private var sortDisplayName: String {
        guard Self.windowedSorts.contains(sort) else { return sort.capitalized }
        let window = Self.topWindows.first { $0.value == timeframe }?.title ?? "This Week"
        return "\(sort.capitalized): \(window)"
    }

    /// Fetches page one purely for its `after` cursor, without
    /// disturbing what is on screen.
    ///
    /// The feed hands its posts over so the gallery opens instantly,
    /// but a handed-over array has no cursor attached. Re-rendering
    /// from this response would undo that instant open, so only the
    /// cursor and any genuinely new tiles are taken.
    private func loadInitialCursor() async {
        do {
            let listing: RedditListing
            if let multiredditPath {
                listing = try await repository.fetchMultiredditListing(path: multiredditPath, sort: sort)
            } else {
                listing = try await repository.fetchListing(subreddit: subreddit, sort: sort, timeframe: timeframe)
            }
            let existing = Set(posts.map(\.id))
            let fetched = GalleryPostMedia.filterMediaPosts(await listing.postsInBackground())
            posts.append(contentsOf: fetched.filter { !existing.contains($0.id) })
            afterToken = listing.data.after
            isExhausted = listing.data.after == nil
        } catch {
            // Non-fatal: the grid still shows the handed-over tiles,
            // it just cannot paginate until the next refresh.
        }
    }

    /// Next page, including the footer states.
    private func loadMore() async {
        guard !isLoadingMore, !isExhausted, let after = afterToken else { return }
        isLoadingMore = true
        footerText = "Loading more…"
        defer { isLoadingMore = false }
        if savedUsername != nil {
            do {
                try await loadSavedPages(from: after, replacing: false)
            } catch {
                footerText = "Couldn't load more"
            }
            return
        }
        do {
            let listing: RedditListing
            if let multiredditPath {
                listing = try await repository.fetchMultiredditListing(path: multiredditPath, sort: sort, after: after)
            } else {
                listing = try await repository.fetchListing(subreddit: subreddit, sort: sort, timeframe: timeframe, after: after)
            }
            let fetched = await listing.postsInBackground()
            // Reddit repeats posts across page boundaries, and a
            // duplicate id in a SwiftUI ForEach is a runtime warning
            // plus a visibly doubled tile.
            let existing = Set(posts.map(\.id))
            posts.append(contentsOf: GalleryPostMedia.filterMediaPosts(fetched).filter { !existing.contains($0.id) })
            afterToken = listing.data.after
            if listing.data.after == nil {
                isExhausted = true
                footerText = "That's everything"
            } else {
                footerText = nil
            }
        } catch {
            // A failed page must not wedge pagination: `afterToken` is
            // left intact so the next tile that appears simply retries.
            footerText = "Couldn't load more"
        }
    }

    private func load() async {
        // Only when there is nothing on screen: a sort change keeps the
        // current grid up and swaps it, rather than blanking.
        if posts.isEmpty { isLoading = true }
        defer { isLoading = false }
        if let savedUsername {
            await loadSaved(username: savedUsername)
            return
        }
        do {
            let listing: RedditListing
            // A multireddit has no subreddit name and would fall through to
            // `fetchListing(subreddit: "")`, the signed-in user's home feed.
            if let multiredditPath {
                listing = try await repository.fetchMultiredditListing(path: multiredditPath, sort: sort)
            } else {
                listing = try await repository.fetchListing(subreddit: subreddit, sort: sort, timeframe: timeframe)
            }
            posts = GalleryPostMedia.filterMediaPosts(await listing.postsInBackground())
            // Seed the pagination cursor; without it `loadMore` has no `after`
            // to send and the grid stops after one page.
            afterToken = listing.data.after
            isExhausted = listing.data.after == nil
            footerText = nil
            errorMessage = nil
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }
}

/// The ids of the tiles currently built on screen. A class, so tracking
/// appear/disappear during a scroll does not invalidate the grid.
@MainActor
private final class VisibleTileTracker {
    private var ids = Set<String>()

    func appeared(_ id: String) { ids.insert(id) }
    func disappeared(_ id: String) { ids.remove(id) }

    /// The on-screen tile in the middle of grid order, which sits near
    /// the middle of the screen.
    func middleTile(in order: [String]) -> String? {
        let visible = order.filter { ids.contains($0) }
        return visible.isEmpty ? nil : visible[visible.count / 2]
    }
}

// MARK: Saved source

extension GalleryViewScreen {
    /// Opens a Saved gallery: what the Saved screen handed over is already
    /// shown, so only a gallery with nothing yet (or no media yet) fetches.
    fileprivate func startSaved() async {
        guard !isExhausted else { return }
        if afterToken != nil {
            if posts.isEmpty { await loadMore() }
        } else {
            await load()
        }
    }

    /// First page(s) of Saved, from the top.
    fileprivate func loadSaved(username: String) async {
        savedScope = SavedGalleryScope(category: savedScope.category, assignments: SavedCategoryStore.allAssignments())
        errorMessage = nil
        if savedScope.isEmptyByConstruction {
            posts = []
            afterToken = nil
            isExhausted = true
            footerText = nil
            return
        }
        do {
            try await loadSavedPages(from: nil, replacing: true)
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    /// Fetches Saved pages until one adds media or the listing ends: an empty
    /// grid has no tile whose appearance would load the next page.
    fileprivate func loadSavedPages(from start: String?, replacing: Bool) async throws {
        guard let savedUsername else { return }
        var cursor = start
        var replace = replacing
        while true {
            let listing = try await repository.fetchSavedItems(
                username: savedUsername, after: cursor, limit: SavedGalleryScope.pageSize)
            let media = GalleryPostMedia.filterMediaPosts(savedScope.admit(await listing.postsInBackground()))
            let existing = replace ? [] : Set(posts.map(\.id))
            let fresh = media.filter { !existing.contains($0.id) }
            posts = replace ? fresh : posts + fresh
            let outcome = savedScope.outcome(gained: fresh.count, after: listing.data.after, previousAfter: cursor)
            afterToken = outcome.exhausted ? nil : listing.data.after
            isExhausted = outcome.exhausted
            footerText = (outcome.exhausted && !replace) ? "That's everything" : nil
            guard outcome.walkOn else { return }
            cursor = listing.data.after
            replace = false
        }
    }
}

/// One row of the filter menu, split out of the `Menu` builder closure
/// to stay within the type checker's budget.
private struct GalleryFilterRow: View {
    let kind: GalleryPostMedia.Kind
    let loadedCount: Int
    @Binding var isOn: Bool
    let isDisabled: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            if loadedCount > 0 {
                Label {
                    Text(kind.title)
                    Text("\(loadedCount) loaded")
                } icon: {
                    Image(systemName: kind.systemImage)
                }
            } else {
                Label(kind.title, systemImage: kind.systemImage)
            }
        }
        .disabled(isDisabled)
    }
}

private struct GalleryGridCell: View {
    @Setting(TagFilterSettings.self) private var tagFilterSettings
    @Setting(MatureMediaPreference.storage) private var matureMediaPrefs
    let tile: GalleryTile
    let nsfwBlurOverride: NSFWBlurOverride
    let playback: GalleryTilePlayback

    @State private var isRevealed = false

    var body: some View {
        Group {
            // `.fit` would letterbox each image inside a fitted frame, leaving
            // vertical gaps. Filling the column width and deriving height from
            // the aspect ratio packs the columns tightly.
            Color.clear
                .aspectRatio(tile.aspectRatio ?? 1.0, contentMode: .fit)
                .overlay {
                    CachedAsyncImage(url: tile.thumbnailURL, downsampleTarget: .galleryTile)
                        .scaledToFill()
                }
                #if canImport(UIKit)
                // Muted looping playback over the poster (Reborn
                // "Play Videos / GIFs in Gallery View").
                .overlay {
                    GalleryTileAutoplayOverlay(
                        tile: tile,
                        isVisibleToReader: !needsWarning || isRevealed,
                        playback: playback)
                }
                #endif
                .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            // Gallery tiles honor the same NSFW/spoiler content warning the
            // feed's own media does, via the same per-subreddit tag-filter
            // preference. A Material overlay matches FeedScreen's own NSFW
            // cover and lets the reveal tap simply remove the overlay
            // instead of re-rendering the image.
            if needsWarning && !isRevealed {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Text(tile.isNSFW ? "NSFW" : "SPOILER")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { isRevealed = true }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // Non-photo media is badged with text: "▶ 1:23" for a video with a
            // known duration, "GIF" for an animated image.
            if tile.kind == .video {
                Text(tile.durationText.map { "▶ \($0)" } ?? "▶")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(4)
            } else if tile.kind == .gif {
                Text("GIF")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(4)
            }
        }
    }

    private var needsWarning: Bool {
        tagFilterSettings.shouldBlurMedia(
            subreddit: tile.subreddit,
            isNSFW: tile.isNSFW,
            isSpoiler: tile.isSpoiler,
            nsfwBlurOverride: nsfwBlurOverride,
            accountPref: MatureMediaPreference.activeAccountValue(in: matureMediaPrefs))
    }
}
