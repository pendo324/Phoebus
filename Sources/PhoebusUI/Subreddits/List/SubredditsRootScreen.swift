import SwiftUI
import PhoebusCore

/// Row metrics for the Subreddits list. Apollo's favourite-star hit
/// target is a fixed width with the height taken from the cell.
enum SubredditRowMetrics {
    static let starHitWidth: CGFloat = 60
    static let iconDiameter: CGFloat = 28
}


/// Posts-tab root screen: Home / Popular Posts / All Posts / Moderator Posts rows
/// at top, then FAVORITES, then the subscription list sectioned alphabetically
/// with an A-Z index sidebar. Feeds push on top, with a "< Subreddits" back button.
public struct SubredditsRootScreen: View {
    #if canImport(UIKit)
    @ObservedObject private var customArt = SubredditCustomArtStore.shared
    #endif

    /// Horizontal room the A-Z scrubber occupies, insetting row content
    /// so trailing accessories stop just left of the letters.
    private let scrubberWidth: CGFloat = 22
    /// Measured height of the index scrubber, for the drag-to-scan
    /// gesture. See `indexScrubber`.
    @State private var scrubberHeight: CGFloat = 0
    let repository: RedditRepository
    let onSelect: (SubredditsRootDestination) -> Void

    @State private var subscriptions: [RedditSubreddit] = []
    @State private var favorites: Set<String> = FavoriteSubredditsStore.load()
    /// Reborn Confirm Favorite Changes: the star tapped, awaiting confirmation.
    @State private var pendingFavoriteToggle: String?
    /// See `favoriteSubreddits`. Held in `@State` so toggling the
    /// setting re-sorts the visible list immediately.
    @State private var sortFavoritesAlphabetically: Bool = FavoriteSubredditsStore.sortAlphabetically
    /// `ExpandedMultireddits`: which multireddits show their members inline.
    /// Persisted, like Apollo's key.
    @State private var expandedMultireddits: Set<String> = ExpandedMultiredditsStore.load()
    /// "Hide Moderated Subreddits" state - see
    /// `filteredModeratedSubreddits`.
    @State private var hiddenModeratedSubreddits: Set<String> = HiddenModeratorSubredditsStore.load()
    @Environment(\.editMode) private var editMode
    @State private var isLoading = false
    /// True while the lists on screen came from disk and have not yet
    /// been confirmed by a network load. Drives a quiet "Updating"
    /// indicator rather than a spinner over content that's already
    /// correct.
    @State private var isShowingCachedLists = false
    /// The account name from the cached snapshot, so the Profile tab
    /// can show a username in the first frame.
    @State private var cachedProfileName: String?
    @State private var errorMessage: String?
    @Setting(GeneralSettingsStore.storage) private var generalSettings
    /// Reborn "Subreddit Sections": resolves the order of the
    /// Favorites/Multireddits/Moderator/Following sections, and whether Following is
    /// split out. The default order (Favorites, Multireddits, Moderator) with
    /// Following appended last and hidden matches an untouched install.
    @Setting(SubredditSectionsSettingsStore.storage) private var sectionsSettings
    /// "Show Subreddit Icons" - governs the small per-subreddit circular
    /// icon shown on every row.
    @Setting(AppearanceSettingsStore.storage) private var appearanceSettings
    /// Apollo shows a gray, rounded, always-visible "Filter
    /// Subreddits" field directly under the nav bar.
    @State private var filterText = ""
    /// `FollowedUsersOrder` (Apollo-Reborn): the user's hand-arranged
    /// order for the Following section.
    @Setting(FollowedUsersOrderStore.storage) private var followedUsersOrder
    /// The active gallery theme's colours, for the filter pill below.
    @Environment(\.apolloTheme) private var apolloTheme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var multireddits: [RedditMultireddit] = []
    @State private var showingAddSubreddit = false
    @State private var showingCreateMultireddit = false
    /// Reborn's Edit-mode multireddit editor.
    @State private var editingMultireddit: EditingMultireddit?
    @State private var newMultiredditName = ""
    @State private var addSubredditName = ""
    /// "MODERATOR" section on the Subreddits root: subreddits the
    /// user moderates are broken out from the rest of the list.
    @State private var moderatedSubreddits: [RedditSubreddit] = []

    public init(repository: RedditRepository, onSelect: @escaping (SubredditsRootDestination) -> Void) {
        self.repository = repository
        self.onSelect = onSelect
        // Read the cached lists synchronously, here, so they are in the
        // first frame, avoiding a flash of an empty list while
        // `/subreddits/mine/subscriber` paginates.
        let cached = SubredditListCache.load(
            for: FavoriteSubredditsAccountContext.currentUsernameProvider() ?? "")
        _subscriptions = State(initialValue: cached?.subscriptions ?? [])
        _multireddits = State(initialValue: cached?.multireddits ?? [])
        _moderatedSubreddits = State(initialValue: cached?.moderated ?? [])
        _isShowingCachedLists = State(initialValue: cached != nil)
        _cachedProfileName = State(initialValue: cached?.accountUsername)
        // Seed the icon cache from the cached listings right away, since
        // it's memory-only and would otherwise draw placeholder circles
        // while re-fetching `/r/<name>/about` per subreddit.
        if let cached {
            let all = cached.subscriptions + cached.moderated
            Task { await SubredditIconCache.shared.seed(from: all) }
        }
    }

    /// A favorite's display casing from the imported backup when there is
    /// no subscription to take it from.
    private func storedFavoriteName(_ lowercased: String) -> String {
        FavoriteSubredditsStore.displayName(for: lowercased) ?? lowercased
    }

    private var filteredSubscriptions: [RedditSubreddit] {
        guard !filterText.trimmingCharacters(in: .whitespaces).isEmpty else { return subscriptions }
        return subscriptions.filter { $0.displayName.localizedCaseInsensitiveContains(filterText) }
    }

    /// Apollo-Reborn "Sort Favorites Alphabetically" (#1042). Default
    /// off = Apollo's native order. Uses `localizedStandardCompare`
    /// (Finder-style, so "sub10" sorts after "sub9").
    private var favoriteSubreddits: [RedditSubreddit] {
        // Every favorite, subscribed or not (Apollo keeps favorites like
        // u_<you> or r/Randnsfw that are not subscriptions), in the
        // native order.
        let bySubscription = Dictionary(subscriptions.map { ($0.displayName.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        let query = filterText.trimmingCharacters(in: .whitespaces)
        let matching = FavoriteSubredditsStore.loadOrdered()
            .filter { favorites.contains($0) }
            .compactMap { bySubscription[$0] ?? RedditSubreddit.named(storedFavoriteName($0)) }
            .filter { query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) }
        return FavoriteSubredditsStore.applySorting(
            matching,
            name: { $0.displayName },
            sortAlphabetically: sortFavoritesAlphabetically
        )
    }

    /// Filtered/searched multireddits: section 2 (MULTIREDDITS), between Favorites and
    /// Moderator.
    private var filteredMultireddits: [RedditMultireddit] {
        guard !filterText.trimmingCharacters(in: .whitespaces).isEmpty else { return multireddits }
        return multireddits.filter { $0.displayName.localizedCaseInsensitiveContains(filterText) }
    }

    /// Filtered/searched moderated subreddits, matching the real
    /// section layout: below Favorites and Multireddits, above the
    /// alphabetized list.
    private var filteredModeratedSubreddits: [RedditSubreddit] {
        let sorted = moderatedSubreddits.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        // Apollo-Reborn "Hide Moderated Subreddits": Reddit offers no
        // way to leave a dead subreddit you moderate, so they're stuck
        // in this section forever. Purely a display filter; bypassed in
        // Edit mode so hidden rows can be unhidden.
        let base = HiddenModeratorSubredditsStore.visible(
            sorted,
            hidden: hiddenModeratedSubreddits,
            isEditing: editMode?.wrappedValue.isEditing == true
        ) { $0.displayName }
        guard !filterText.trimmingCharacters(in: .whitespaces).isEmpty else { return base }
        return base.filter { $0.displayName.localizedCaseInsensitiveContains(filterText) }
    }

    /// Apollo-Reborn "Following" section: Reddit represents a followed
    /// user's profile as a subscribed subreddit named `u_<username>`.
    /// This section singles those out from the alphabetized list.
    private var followedUserSubreddits: [RedditSubreddit] {
        let natural = filteredSubscriptions
            .filter { $0.displayName.lowercased().hasPrefix("u_") }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        // Reborn lets this section be hand-ordered and persisted
        // (`FollowedUsersOrder`). Newly followed users go to the end
        // rather than interleaving into a hand-arranged list.
        let rank = FollowedUsersOrderStore.apply(
            savedOrder: followedUsersOrder,
            to: natural.map(\.displayName)
        )
        var index: [String: Int] = [:]
        for (position, name) in rank.enumerated() { index[name.lowercased()] = position }
        return natural.sorted {
            (index[$0.displayName.lowercased()] ?? 0) < (index[$1.displayName.lowercased()] ?? 0)
        }
    }

    /// "Filter Subreddits", the list's first row. Apollo keeps it just above the
    /// visible area at rest, revealed by pulling the list down.
    private var filterField: some View {
                // Same metrics as `GlassSearchField` (44pt capsule, 17pt icon, 12pt inset);
                // Apollo's `UISearchBar` also grows to the iOS 26 field height.
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("Filter Subreddits", text: $filterText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        #endif
                    // Clear affordance: otherwise the only way to clear it is selecting and deleting.
                    if !filterText.isEmpty {
                        Button { filterText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear filter")
                        .accessibilityIdentifier("subreddits.filter.clear")
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                // `.compositingGroup()` flattens this HStack into
                // one layer before the capsule is drawn behind it.
                // Without it, iOS 26 renders the focused TextField's
                // own fill as a separate layer on top of the
                // capsule while focused; no styling modifier removes
                // it since the fill belongs to the field itself.
                .compositingGroup()
                // Themed, not `Color.secondary.opacity(0.12)`: a hand-drawn fill would opt out of
                // the active gallery theme. `.tertiaryFill` mixes the theme's background toward
                // its label; it falls back to the system colour with no gallery theme.
                .background(Capsule().fill(
                    apolloTheme.color(.tertiaryFill) ?? Color.secondary.opacity(0.12)
                ))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
    }

    private static let filterRowID = "subreddits.filterRow"

    /// Persists a drag inside the Following section: moves the entry,
    /// then stores the resulting order.
    private func moveFollowedUsers(from source: IndexSet, to destination: Int) {
        var names = followedUserSubreddits.map(\.displayName)
        names.move(fromOffsets: source, toOffset: destination)
        FollowedUsersOrderStore.save(names)
        $followedUsersOrder.binding.wrappedValue = names
    }

    /// The non-favorited subscriptions in A-Z sections, "#" last.
    private var alphabetizedGroups: [(letter: String, subreddits: [RedditSubreddit])] {
        let remaining = filteredSubscriptions
            .filter { !favorites.contains($0.displayName.lowercased()) }
            .filter { !(sectionsSettings.separateFollowedUsers && $0.displayName.lowercased().hasPrefix("u_")) }
        return SubredditIndexTitle.alphabetized(remaining, name: \.displayName)
            .map { (letter: $0.letter, subreddits: $0.items) }
    }

    public var body: some View {
        ScrollViewReader { proxy in
            // The scrubber overlays the list rather than taking a column
            // of its own. Laying it out as an HStack sibling shrinks
            // every row by the scrubber's width.
            ZStack(alignment: .trailing) {
                List {
                   Group {
                   Section {
                       filterField
                           .listRowInsets(EdgeInsets())
                           .listRowSeparator(.hidden)
                           .listRowBackground(Color.clear)
                           .id(Self.filterRowID)
                   }
                   Section {
                       // Reborn's feed shortcuts appearance: full-width Rows, or a compact equal-width
                       // horizontal strip. Side-by-Side falls back to Rows at accessibility text sizes.
                       if generalSettings.subredditFeedLayout == .rows
                           || (generalSettings.subredditFeedLayout == .sideBySide && dynamicTypeSize.isAccessibilitySize) {
                           feedShortcutRows
                       } else {
                           feedShortcutStrip
                       }
                   }
                   .buttonStyle(.plain)
                   // The index's ☰ glyph jumps here.
                   .id(SubredditIndexTitle.feedShortcuts)

                    // Reborn "Subreddit Sections" order.
                    ForEach(sectionsSettings.visibleOrder) { token in
                        sectionView(for: token)
                    }

                    ForEach(alphabetizedGroups, id: \.letter) { group in
                        Section(group.letter) {
                            ForEach(group.subreddits) { subreddit in
                                favoriteRow(subreddit)
                            }
                            // Stock Apollo Edit mode: deleting an A-Z
                            // row unsubscribes.
                            .onDelete { offsets in
                                let targets = offsets.compactMap { group.subreddits.indices.contains($0) ? group.subreddits[$0] : nil }
                                Task { await unsubscribe(targets) }
                            }
                        }
                        .id(group.letter)
                    }

                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                   }
                   // A theme with its own surfaces paints the rows its card
                   // colour; stock themes keep the system row fill.
                   .modifier(ApolloCardRowBackground(color: apolloTheme.color(.secondaryBackground)))
                }
                .listStyle(.plain)
                // No gap before a section: each header follows the row above it directly (the
                // list's default 22pt would push rows below Apollo's).
                .apolloListSectionSpacingZero()
                // Stock dark surface + Pure Black tiers (`ApolloStockSurface`).
                .scrollContentBackground(.hidden)
                .apolloStockSurface()
                // NO vertical scroll indicator: a `UITableView` with a
                // section index hides its own vertical indicator,
                // because the index IS the scrubbing affordance and
                // the two would otherwise overlap.
                .scrollIndicators(.hidden, axes: .vertical)
                // No row separators. The real Subreddits list draws no
                // hairline between rows; the only rules are inside each
                // section header.

                // Row content is inset clear of the scrubber, while the
                // rows and separators still run full width.
                .safeAreaPadding(.trailing, Self.indexInkWidth)
                // Reserve room for the floating Liquid Glass tab bar,
                // which otherwise covers the last rows.

                // A-Z index scrubber on the right edge, as `UITableView.sectionIndexTitles`. It
                // sits in its own ZStack layer with hit-testing on an opaque shape, so the List
                // gets priority only where the scrubber is not; as an HStack sibling it would
                // take a column and shrink every row. Always shown: the four leading glyphs index
                // the Favorites / Multireddits / Moderator sections, which exist independently of
                // the A-Z list.
                indexScrubber(proxy: proxy)
            }
        }
        .navigationTitle("Subreddits")
        .confirmationDialog(
            pendingFavoriteToggle.map {
                FavoriteSubredditsStore.confirmPrompt(name: $0, isFavorite: favorites.contains($0.lowercased())).title
            } ?? "",
            isPresented: $pendingFavoriteToggle.isPresent(),
            titleVisibility: .visible
        ) {
            if let name = pendingFavoriteToggle {
                let isFavorite = favorites.contains(name.lowercased())
                Button(FavoriteSubredditsStore.confirmPrompt(name: name, isFavorite: isFavorite).action,
                       role: isFavorite ? .destructive : nil) {
                    toggleFavorite(name)
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        // Inline, not large: a large title collapses into the nav bar as the list
        // scrolls, sweeping across the "Filter Subreddits" pill (a `safeAreaInset` pinned
        // to the list) and desyncing the two.
        .navigationBarTitleDisplayMode(.inline)
        // Nav chrome: "+" to add/subscribe by name, "Edit" to manage the list.
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                // "+" presents an action sheet with two options - "Add
                // Subscription" and "Create Multireddit".
                ApolloOverflowMenu(systemImage: "plus", rows: addSheetRows)
                .accessibilityIdentifier("subreddits.add")
                    .apolloGlassBarTint()
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
                    .accessibilityIdentifier("subreddits.edit")
                    .apolloGlassBarTint()
            }
            // A quiet spinner beside Edit while the cached list is being
            // confirmed, rather than a full-screen indicator covering a
            // list that's usually already correct.
            ToolbarItem(placement: .topBarTrailing) {
                if isLoading && !subscriptions.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Updating subreddits")
                        .accessibilityIdentifier("subreddits.updating")
                }
            }
        }

        // Field placeholder: "Multireddit name".
        .sheet(item: $editingMultireddit) { editing in
            MultiredditEditSheet(path: editing.path, repository: repository) {
                editingMultireddit = nil
                Task {
                    await SubscribedSubredditsCache.shared.invalidate()
                    await load()
                }
            }
        }
        .alert("Create Multireddit", isPresented: $showingCreateMultireddit) {
            TextField("Multireddit name", text: $newMultiredditName)
            Button("Create") {
                let name = newMultiredditName.trimmingCharacters(in: .whitespaces)
                newMultiredditName = ""
                guard !name.isEmpty else { return }
                Task { await createMultireddit(named: name) }
            }
            Button("Cancel", role: .cancel) { newMultiredditName = "" }
        }
        .alert("Add Subreddit", isPresented: $showingAddSubreddit) {
            TextField("Subreddit name", text: $addSubredditName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Subscribe") {
                let name = addSubredditName.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "r/", with: "", options: [.caseInsensitive])
                addSubredditName = ""
                guard !name.isEmpty else { return }
                Task {
                    try? await repository.subscribe(subredditName: name, subscribe: true)
                    await SubscribedSubredditsCache.shared.invalidate()
                    await load()
                }
            }
            Button("Cancel", role: .cancel) { addSubredditName = "" }
        } message: {
            Text("Enter the name of a subreddit to subscribe to.")
        }
        // Loaded only when there is nothing to show: SwiftUI re-runs
        // `.task` when a screen reappears after a pop, so this would
        // otherwise refetch the whole subscription list every time the
        // user swiped back to it.
        .task {
            // Always refresh when there is nothing yet. When the cache
            // supplied the list, refresh once per launch to confirm it,
            // so a subscription changed on another device is picked up
            // without pulling to refresh.
            if subscriptions.isEmpty {
                await load()
            } else if isShowingCachedLists {
                await load()
            }
        }
        .refreshable { await load() }
        // Re-read here so changing Feed Shortcuts Appearance or other
        // settings and coming back shows the current values.
        .onAppear { refreshSettingsSnapshots() }
        .background(FirstRowTucker().frame(width: 0, height: 0))
        // The Liquid Glass tab bar keeps every tab's content alive and
        // only changes its opacity, so `.onAppear` fires once per
        // launch and never again on a tab switch. See
        // `TabReappearNotifier`.
        .onReceive(NotificationCenter.default.publisher(for: .apolloTabDidReappear)) { _ in
            refreshSettingsSnapshots()
        }
        // Joined or left anywhere else (a feed's Join pill or ••• menu, an
        // interactive post): the list follows without a relaunch (#1264).
        .onReceive(NotificationCenter.default.publisher(for: .apolloSubscriptionsChanged)) { _ in
            Task { await load() }
        }
    }

    /// Re-reads every settings snapshot this screen renders from, so
    /// changes to Feed Shortcuts appearance, Subreddit Sections order,
    /// Show Subreddit Icons, or Sort Favorites Alphabetically take
    /// effect without a fresh app launch.
    private func refreshSettingsSnapshots() {
        favorites = FavoriteSubredditsStore.load()
        sortFavoritesAlphabetically = FavoriteSubredditsStore.sortAlphabetically
    }

    /// The A-Z (plus "#") index scrubber, laid out as a List sibling.
    /// Tracks drag location for continuous-scan scrolling through
    /// sections, matching the real control's fast-scan behavior.
    private func indexScrubber(proxy: ScrollViewProxy) -> some View {
        // The full strip, always: four glyphs, A-Z, "#". A real
        // `UITableView` section index is a fixed scrubbing scale. A
        // title with no section of its own resolves to the nearest one
        // (`SubredditIndexResolver`).
        let titles = SubredditIndexTitle.all()
        let availableLetters = alphabetizedGroups.map(\.letter)

        // Not a `GeometryReader`: it has no intrinsic size, so
        // `.fixedSize(vertical:)` would collapse it. The drag needs the
        // strip's height, read via a `background` geometry probe
        // instead.
        return VStack(spacing: 0) {
                ForEach(titles, id: \.self) { title in
                    Text(title)
                        // 11pt semibold, sized directly rather than
                        // borrowing a Dynamic-Type-scaling text style;
                        // a section index does not scale.
                        .apolloFont(size: 11, weight: .semibold)
                        // Accent blue, as a `UITableView` section index tint.
                        .foregroundStyle(apolloTheme.color(.accent) ?? .accentColor)
                        // 14pt pitch.
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.indexTitlePitch)
                        .contentShape(Rectangle())
                        // A plain per-row tap alongside the continuous-
                        // drag gesture below: a synthetic single-point
                        // click doesn't always trigger `DragGesture
                        // .onChanged`, while `.onTapGesture` fires
                        // reliably for that input shape.
                        .onTapGesture {
                            scrub(to: title, availableLetters: availableLetters, proxy: proxy)
                        }
                        .accessibilityIdentifier("subreddits.indexScrubber.\(title)")
                        .accessibilityLabel(SubredditIndexTitle.accessibilityLabel(for: title))
                }
            }
        // Only this strip takes touches, so list rows beside it stay
        // tappable.
        .contentShape(Rectangle())
        .background(
            GeometryReader { geo in
                Color.clear.onAppear { scrubberHeight = geo.size.height }
                    .onChange(of: geo.size.height) { _, h in scrubberHeight = h }
            }
        )
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard !titles.isEmpty, scrubberHeight > 0 else { return }
                    let rowHeight = scrubberHeight / CGFloat(titles.count)
                    let index = min(titles.count - 1, max(0, Int(value.location.y / rowHeight)))
                    scrub(to: titles[index], availableLetters: availableLetters, proxy: proxy)
                }
        )
        // A fixed, intrinsic width pinned to the trailing edge. An
        // unconstrained width would let the GeometryReader claim the
        // whole row width and swallow row taps.
        .frame(width: Self.indexInkWidth)
        .padding(.trailing, Self.indexTrailingMargin)
        // Intrinsic height, vertically centred, not stretched to fill,
        // matching real `sectionIndexTitles` behaviour.
        .frame(maxHeight: .infinity, alignment: .center)
    }

    /// Glyph pitch, ink width and right margin for the index scrubber.
    static let indexTitlePitch: CGFloat = 14
    static let indexInkWidth: CGFloat = 10
    static let indexTrailingMargin: CGFloat = 6

    /// Scrolls to the section a title names, resolving a letter with
    /// no section of its own onto the nearest one that exists.
    private func scrub(to title: String,
                       availableLetters: [String],
                       proxy: ScrollViewProxy) {
        guard let anchor = SubredditIndexResolver.anchor(
            for: title, availableLetters: availableLetters) else { return }
        withAnimation(.linear(duration: 0.05)) {
            proxy.scrollTo(anchor, anchor: .top)
        }
        Haptics.selection()
    }

    /// One of the four reorderable "Subreddit Sections" tokens
    /// (`SubredditSectionsSettings.SectionToken`). Only where a section renders
    /// changes, never what is inside it.
    @ViewBuilder
    private func sectionView(for token: SubredditSectionsSettings.SectionToken) -> some View {
        switch token {
        case .favorites:
            if !favoriteSubreddits.isEmpty {
                Section(header: ApolloSubredditSectionHeader("Favorites")) {
                    ForEach(favoriteSubreddits) { subreddit in
                        favoriteRow(subreddit)
                    }
                    // Stock Apollo Edit mode: deleting a Favorites row
                    // unfavorites it (the subscription stays).
                    .onDelete { offsets in
                        for index in offsets where favoriteSubreddits.indices.contains(index) {
                            FavoriteSubredditsStore.setFavorite(favoriteSubreddits[index].displayName, isFavorite: false)
                        }
                        favorites = FavoriteSubredditsStore.load()
                    }
                }
                // The ★ glyph's anchor.
                .id(SubredditIndexTitle.favorites)
            }
        case .multireddits:
            // Apollo's table section layout: 0 = feed shortcuts, 1 = FAVORITES, 2 =
            // MULTIREDDITS, 3 = MODERATOR, 4+ = A-Z/#. Multireddits are a distinct section
            // below Favorites and above Moderator by default; a user reorder
            // (`SubredditSectionsSettingsScreen`) can move it.
            if !filteredMultireddits.isEmpty {
                Section(header: ApolloSubredditSectionHeader("Multireddits")) {
                    ForEach(filteredMultireddits) { multi in
                        // Inline expansion: Apollo's `ExpandedMultireddits` default is keyed by multi
                        // name, which is why the per-account store keys on name rather than path.
                        HStack(spacing: 0) {
                            Button {
                                // In Edit mode a multireddit row opens its rename/description editor instead of
                                // the feed (Reborn #1267).
                                if editMode?.wrappedValue.isEditing == true {
                                    editingMultireddit = EditingMultireddit(path: multi.path)
                                } else {
                                    onSelect(.multireddit(path: multi.path, name: multi.displayName))
                                }
                            } label: {
                                iconRow(multi.displayName, subtitle: multiredditSubtitle(multi), systemImage: "square.stack", color: .purple,
                                        customIcon: multiredditCustomIcon(multi.path))
                            }
                            .accessibilityIdentifier("subreddits.multireddit.\(multi.displayName)")
                            // The expand control is a trailing column, not something that trails the text, so
                            // every row lines up regardless of subtitle length. It has the star column's
                            // width, so the two share one trailing gutter. Height is left to the row, since a
                            // fixed height would inflate it (see `SubredditRowMetrics.starHitWidth`).
                            if !multi.subreddits.isEmpty {
                                Spacer(minLength: 0)
                                Button {
                                    toggleMultiredditExpansion(multi)
                                } label: {
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .rotationEffect(.degrees(expandedMultireddits.contains(multi.name) ? 90 : 0))
                                        .frame(width: SubredditRowMetrics.starHitWidth)
                                        .frame(maxHeight: .infinity)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(expandedMultireddits.contains(multi.name) ? "Collapse" : "Expand")
                                .accessibilityIdentifier("subreddits.multireddit.expand.\(multi.displayName)")
                            }
                        }
                        // Inline expansion rows: member subreddits appear indented under their
                        // multireddit, each opening its own feed.
                        if expandedMultireddits.contains(multi.name) {
                            ForEach(multi.subreddits, id: \.name) { member in
                                Button {
                                    onSelect(.subreddit(member.name))
                                } label: {
                                    HStack(spacing: 8) {
                                        Spacer().frame(width: 20)
                                        SubredditIconView(subreddit: member.name, repository: repository, size: 20)
                                        Text(member.name)
                                            .font(.subheadline)
                                        Spacer(minLength: 0)
                                    }
                                }
                                .accessibilityIdentifier("subreddits.multireddit.member.\(member.name)")
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                // The ○ glyph's anchor.
                .id(SubredditIndexTitle.multireddits)
            }
        case .moderator:
            if !filteredModeratedSubreddits.isEmpty {
                Section(header: ApolloSubredditSectionHeader("Moderator")) {
                    ForEach(filteredModeratedSubreddits) { subreddit in
                        let hidden = HiddenModeratorSubredditsStore.isHidden(
                            subreddit.displayName, in: hiddenModeratedSubreddits
                        )
                        favoriteRow(subreddit)
                            // Edit-mode presentation: a hidden row reappears faded with a green plus, so it
                            // can be unhidden inline.
                            .opacity(hidden ? 0.5 : 1)
                            .swipeActions(edge: .trailing) {
                                Button {
                                    HiddenModeratorSubredditsStore.toggle(subreddit.displayName)
                                    hiddenModeratedSubreddits = HiddenModeratorSubredditsStore.load()
                                } label: {
                                    Label(hidden ? "Unhide" : "Hide",
                                          systemImage: hidden ? "plus.circle" : "eye.slash")
                                }
                                .tint(hidden ? .green : .gray)
                            }
                            .accessibilityIdentifier("subreddits.moderated.\(subreddit.displayName)")
                    }
                }
                // The ♜ glyph's anchor. A chess rook reads as a
                // moderator's shield at 11pt.
                .id(SubredditIndexTitle.moderator)
            }
        case .following:
            // Reached only when `visibleOrder` includes it, i.e. Separate Followed Users is
            // on (see `followedUserSubreddits`).
            if !followedUserSubreddits.isEmpty {
                Section(header: ApolloSubredditSectionHeader("Following")) {
                    ForEach(followedUserSubreddits) { subreddit in
                        favoriteRow(subreddit)
                    }
                    // Reborn makes this section drag-reorderable, persisted to `FollowedUsersOrder`.
                    // The alphabetized sections are collation-ordered, so their moves pass through.
                    .onMove(perform: moveFollowedUsers)
                }
            }
        }
    }


    /// Removes the rows at once (the table animates them out), then
    /// unsubscribes; a failure puts the row back and says so.
    private func unsubscribe(_ targets: [RedditSubreddit]) async {
        let names = Set(targets.map(\.name))
        let before = subscriptions
        withAnimation { subscriptions.removeAll { names.contains($0.name) } }
        for subreddit in targets {
            do {
                try await repository.subscribe(subredditFullname: subreddit.name, subscribe: false)
            } catch {
                subscriptions = before
                errorMessage = "Unable to unsubscribe"
                return
            }
        }
    }

    private func toggleFavorite(_ name: String) {
        let isFavorite = favorites.contains(name.lowercased())
        FavoriteSubredditsStore.setFavorite(name, isFavorite: !isFavorite)
        favorites = FavoriteSubredditsStore.load()
        Haptics.selection()
    }

    @ViewBuilder
    private func favoriteRow(_ subreddit: RedditSubreddit) -> some View {
        HStack(spacing: 0) {
            // The navigating part of the row is its own Button, ending before the star. The
            // star is a sibling, not a child, so neither control swallows the other's taps. A
            // row Button with the star nested inside lets the row win the star's taps; a
            // plain HStack with `.onTapGesture` for navigation never fires the row tap.
            Button {
                onSelect(.subreddit(subreddit.displayName))
            } label: {
                // 28pt icon, name at 17pt, 58pt row pitch.
                HStack(spacing: 14.4) {
                    // Per-subreddit icon on the LEFT of every row,
                    // gated by the "Show Subreddit Icons" setting.
                    if appearanceSettings.showSubredditIconsInSubredditList {
                        SubredditIconView(
                            subreddit: subreddit.displayName,
                            repository: repository,
                            size: SubredditRowMetrics.iconDiameter)
                    }
                    // A favorite the account does not follow is known only by its lowercase name;
                    // Apollo shows it in its display case ("ApolloApp").
                    Text(SubredditCapitalization.display(subreddit.displayName))
                        .apolloFont(size: 17)
                        .foregroundStyle(Color.apolloPrimaryText(colorScheme: colorScheme, themeColors: apolloTheme))
                    Spacer(minLength: 0)
                }
                // Fills the row up to the star, so tapping the empty
                // middle navigates too - the `Spacer()` contributes no
                // hit-testable area on its own.
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("subreddits.row.\(subreddit.displayName)")

            // Rows show icon + name + star, no subscriber count.
            Button {
                if FavoriteSubredditsStore.confirmChanges {
                    pendingFavoriteToggle = subreddit.displayName
                } else {
                    toggleFavorite(subreddit.displayName)
                }
            } label: {
                Image(systemName: favorites.contains(subreddit.displayName.lowercased())
                      ? "star.fill" : "star")
                    // Filled stars are solid blue, the app tint, not the iOS "bookmarked" yellow.
                    .foregroundStyle(favorites.contains(subreddit.displayName.lowercased())
                                     ? .blue : .secondary)
                    // Sized by width only: Apollo's star hit area is a fixed 60pt width with the
                    // height taken from the cell. `maxHeight: .infinity` makes it span the full row
                    // without inflating it.
                    .frame(width: SubredditRowMetrics.starHitWidth)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("subreddits.favoriteToggle.\(subreddit.displayName)")
        }
        .apolloSubredditRowSeparator(modern: sectionsSettings.usesModernDividers)
    }

    /// Reborn multireddit-row subtitle logic; see
    /// `RedditMultireddit.subtitle(hideDescriptions:fallback:)`. `ExpandedMultireddits`
    /// is keyed by multireddit name.
    private func toggleMultiredditExpansion(_ multi: RedditMultireddit) {
        if expandedMultireddits.contains(multi.name) {
            expandedMultireddits.remove(multi.name)
        } else {
            expandedMultireddits.insert(multi.name)
        }
        ExpandedMultiredditsStore.save(expandedMultireddits)
    }

    /// "+" options, matching Apollo's add sheet. Deliberately without icons: there is
    /// no reference for icons on this sheet.
    private var addSheetRows: [ApolloActionSheetRow] {
        [
            ApolloActionSheetRow("Add Subscription", accessibilityIdentifier: "subreddits.addSubscription") {
                showingAddSubreddit = true
            },
            ApolloActionSheetRow("Create Multireddit", accessibilityIdentifier: "subreddits.createMultireddit") {
                showingCreateMultireddit = true
            },
        ]
    }

    private func multiredditSubtitle(_ multi: RedditMultireddit) -> String? {
        multi.subtitle(hideDescriptions: sectionsSettings.hideMultiredditDescriptions, fallback: "A group of subreddits")
    }

    /// A user-chosen multireddit icon (Reborn #799/#837), drawn in place of the stock
    /// badge.
    private func multiredditCustomIcon(_ path: String) -> Image? {
        #if canImport(UIKit)
        _ = customArt.revision
        return customArt.image(for: multiredditIconKey(path: path), kind: .icon).map { Image(uiImage: $0) }
        #else
        return nil
        #endif
    }

    private func iconRow(_ title: String, subtitle: String? = nil, systemImage: String, color: Color,
                         orb: String? = nil, customIcon: Image? = nil) -> some View {
        let style = generalSettings.subredditFeedIconStyle
        // Icon 28pt, title 17pt at x 60.7, subtitle 13pt in the tertiary text colour, 60pt
        // row pitch.
        return HStack(spacing: 13) {
            Group {
                if let customIcon {
                    customIcon.resizable().scaledToFill().clipShape(Circle())
                } else if style == .classic, let orb {
                    // Apollo's own badge artwork in the stock style.
                    StockIcon(orb, size: CGSize(width: 28, height: 28))
                } else {
                    iconBadge(systemImage: systemImage, color: color, style: style)
                }
            }
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .apolloFont(size: 17)
                    .foregroundStyle(Color.apolloPrimaryText(colorScheme: colorScheme, themeColors: apolloTheme))
                // "Hide Feed Descriptions" clears the feed rows' subtitles.
                if let subtitle, !generalSettings.hideFeedDescriptions {
                    Text(subtitle)
                        .apolloFont(size: 13)
                        .foregroundStyle(Color.apolloTertiaryText(colorScheme: colorScheme, themeColors: apolloTheme))
                }
            }
            // An `HStack` is only as wide as its content, so a
            // `Button` wrapping this row is too, leaving the rest of
            // the row inert unless something claims the remaining
            // width. The `Spacer` claims it and `contentShape` makes
            // that claimed area hit-testable, since a `Spacer` draws
            // nothing and is not hit-tested on its own.
            Spacer(minLength: 0)
        }
        // Row height is left to SwiftUI. A `minHeight` here does not
        // REPLACE the list's own row insets, it adds to them, and
        // zeroing them via `.listRowInsets` does not take effect from
        // inside the row's label (these rows are `Button` labels, and
        // the modifier has to be applied to the row itself).
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func iconBadge(systemImage: String, color: Color, style: FeedIconStyle) -> some View {
        switch style {
        case .classic:
            ZStack {
                Circle().fill(color)
                Image(systemName: systemImage)
                    .apolloFont(size: 14, weight: .semibold)
                    .foregroundStyle(.white)
            }
        case .circle:
            ZStack {
                Circle().stroke(color, lineWidth: 2)
                Image(systemName: systemImage)
                    .apolloFont(size: 14, weight: .semibold)
                    .foregroundStyle(color)
            }
        case .tinted:
            Image(systemName: systemImage)
                .apolloFont(size: 18, weight: .semibold)
                .foregroundStyle(color)
        case .softTile:
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.18))
                Image(systemName: systemImage)
                    .apolloFont(size: 14, weight: .semibold)
                    .foregroundStyle(color)
            }
        case .solidTile:
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(color)
                Image(systemName: systemImage)
                    .apolloFont(size: 14, weight: .semibold)
                    .foregroundStyle(.white)
            }
        }
    }

    /// Full-width list rows, the default `.rows` layout.
    @ViewBuilder
    private var feedShortcutRows: some View {
        Button {
            onSelect(.home)
        } label: {
            iconRow("Home", subtitle: "Posts from subscriptions", systemImage: "house.fill", color: Color(red: 0.93, green: 0.16, blue: 0.4),
                    orb: "orb-home")
        }
        .accessibilityIdentifier("subreddits.home")
        .apolloSubredditRowSeparator(modern: sectionsSettings.usesModernDividers)
        .apolloSubredditRowMetrics()
        if !generalSettings.hidePopularInSubredditList {
            Button {
                onSelect(.popular)
            } label: {
                // Trending-line-chart glyph, not a flame.
                iconRow("Popular Posts", subtitle: "Most popular posts across Reddit", systemImage: "chart.line.uptrend.xyaxis", color: .blue,
                        orb: "orb-popular")
            }
            .accessibilityIdentifier("subreddits.popular")
        .apolloSubredditRowSeparator(modern: sectionsSettings.usesModernDividers)
        .apolloSubredditRowMetrics()
        }
        if !generalSettings.hideAllInSubredditList {
            Button {
                onSelect(.all)
            } label: {
                // Tray/inbox-with-up-arrow glyph.
                iconRow("All Posts", subtitle: "Posts across all subreddits", systemImage: "tray.and.arrow.up.fill", color: .green,
                        orb: "orb-all")
            }
            .accessibilityIdentifier("subreddits.all")
        .apolloSubredditRowSeparator(modern: sectionsSettings.usesModernDividers)
        .apolloSubredditRowMetrics()
        }
        if !generalSettings.hideModeratorInSubredditList {
            Button {
                onSelect(.moderator)
            } label: {
                iconRow("Moderator Posts", subtitle: "Posts from moderated subreddits", systemImage: "star.fill", color: .gray,
                        orb: "orb-moderator")
            }
            .accessibilityIdentifier("subreddits.moderator")
        .apolloSubredditRowSeparator(modern: sectionsSettings.usesModernDividers)
        .apolloSubredditRowMetrics()
        }
    }

    /// Compact equal-width horizontal strip for `.sideBySide` / `.grid` / `.iconDock`,
    /// with separators between items.
    @ViewBuilder
    /// Reborn's three shortcut layouts: Grid stacks a 46pt icon over its title in a
    /// 104pt row; Side-by-Side puts a 32pt icon beside the title in a 68pt row; Icon
    /// Dock shows only 34pt icons in a 64pt row with wider insets. Grid and
    /// Side-by-Side separate items with hairlines; Side-by-Side falls back to Rows at
    /// accessibility text sizes.
    private var feedShortcutStrip: some View {
        let all: [(SubredditsRootDestination, String, String, Color, String, Bool)] = [
            (.home, "Home", "house.fill", Color(red: 0.93, green: 0.16, blue: 0.4), "orb-home", true),
            (.popular, "Popular", "chart.line.uptrend.xyaxis", .blue, "orb-popular", !generalSettings.hidePopularInSubredditList),
            (.all, "All", "tray.and.arrow.up.fill", .green, "orb-all", !generalSettings.hideAllInSubredditList),
            (.moderator, "Moderator", "star.fill", .gray, "orb-moderator", !generalSettings.hideModeratorInSubredditList)
        ]
        let items = all.filter(\.5)
        let layout = generalSettings.subredditFeedLayout
        let style = generalSettings.subredditFeedIconStyle
        let sideBySide = layout == .sideBySide
        let iconDock = layout == .iconDock
        let iconSize: CGFloat = {
            switch layout {
            case .grid: return style == .tinted ? 40 : 46
            case .iconDock: return 34
            default:
                if style == .tinted { return items.count == 4 ? 28 : 30 }
                return items.count == 4 ? 30 : 32
            }
        }()
        let spacing: CGFloat = sideBySide ? (items.count == 4 ? 3.5 : 7) : (iconDock ? 0 : 4)
        let height: CGFloat = iconDock ? 64 : (sideBySide ? 68 : 104)
        let inset: CGFloat = iconDock ? 28 : 14
        if sideBySide {
            return AnyView(feedShortcutSideBySide(items: items.map { ($0.0, $0.1, $0.2, $0.3, $0.4) },
                                                  iconSize: iconSize, spacing: spacing, style: style))
        }
        return AnyView(HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let (destination, title, systemImage, color, orb, _) = item
                Button {
                    onSelect(destination)
                } label: {
                    let icon = Group {
                        if style == .classic {
                            StockIcon(orb, size: CGSize(width: iconSize, height: iconSize))
                        } else {
                            iconBadge(systemImage: systemImage, color: color, style: style)
                        }
                    }
                    .frame(width: iconSize, height: iconSize)
                    let label = Text(title)
                        .font(.body)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Group {
                        if iconDock {
                            icon
                        } else if sideBySide {
                            HStack(spacing: spacing) { icon; label }
                        } else {
                            VStack(spacing: spacing) { icon; label }
                        }
                    }
                    .padding(.horizontal, sideBySide ? 6 : 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(RoundedRectangle(cornerRadius: sideBySide ? 12 : 16))
                }
                .accessibilityLabel(title)
                .accessibilityIdentifier("subreddits.\(shortcutAccessibilitySuffix(for: destination))")
                .overlay(alignment: .trailing) {
                    if !iconDock, index < items.count - 1 {
                        Rectangle()
                            .fill(Color.apolloSeparator(colorScheme: colorScheme))
                            .frame(width: 1 / 3)
                            .padding(.vertical, sideBySide ? 14 : 22)
                            .offset(x: 1 / 6)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, inset)
        .padding(.vertical, 8)
        .frame(height: height)
        .listRowInsets(EdgeInsets()))
    }

    /// Side-by-Side with three or more items is Reborn's flexible layout:
    /// each item takes its content's width, the leftover space is shared
    /// between the gaps, and each hairline sits in the middle of its gap.
    private func feedShortcutSideBySide(items: [(SubredditsRootDestination, String, String, Color, String)],
                                        iconSize: CGFloat, spacing: CGFloat, style: FeedIconStyle) -> some View {
        let fontSize: CGFloat = items.count == 4 ? 16 : 17
        return HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let (destination, title, systemImage, color, orb) = item
                if index > 0 {
                    Spacer(minLength: 4)
                    Rectangle()
                        .fill(Color.apolloSeparator(colorScheme: colorScheme))
                        .frame(width: 1 / 3)
                        .padding(.vertical, 14)
                    Spacer(minLength: 4)
                }
                Button {
                    onSelect(destination)
                } label: {
                    HStack(spacing: spacing) {
                        Group {
                            if style == .classic {
                                StockIcon(orb, size: CGSize(width: iconSize, height: iconSize))
                            } else {
                                iconBadge(systemImage: systemImage, color: color, style: style)
                            }
                        }
                        .frame(width: iconSize, height: iconSize)
                        Text(title)
                            .font(.system(size: ScaledSystemFont.scaled(fontSize, style: .body, for: dynamicTypeSize)))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel(title)
                .accessibilityIdentifier("subreddits.\(shortcutAccessibilitySuffix(for: destination))")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(height: 68)
        .listRowInsets(EdgeInsets())
    }

    private func shortcutAccessibilitySuffix(for destination: SubredditsRootDestination) -> String {
        switch destination {
        case .home: return "home"
        case .popular: return "popular"
        case .all: return "all"
        case .moderator: return "moderator"
        default: return "unknown"
        }
    }

    /// Compact, user-visible description of a fetch failure: enough to
    /// identify the cause without dumping a Swift error dump.
    static func describe(_ error: Error) -> String {
        if let apiError = error as? RedditAPIError {
            switch apiError {
            case .httpError(let status, let body):
                let snippet = body.prefix(60).replacingOccurrences(of: "\n", with: " ")
                return "HTTP \(status) \(snippet)"
            case .notAuthenticated: return "not authenticated"
            case .sessionExpired: return "session expired"
            case .decodingFailed(let detail): return "decode failed: \(detail.prefix(60))"
            }
        }
        if let urlError = error as? URLError {
            return "network \(urlError.code.rawValue)"
        }
        if error is DecodingError {
            return "decode failed"
        }
        return "\(error)"
    }

    /// One retry after a short pause, else nil.
    private static func retrying<T>(_ fetch: () async throws -> T) async -> T? {
        if let value = try? await fetch() { return value }
        try? await Task.sleep(for: .milliseconds(600))
        return try? await fetch()
    }

    private func createMultireddit(named name: String) async {
        do {
            let username = try await repository.fetchIdentity().name
            try await repository.createMultireddit(name: name, username: username)
            await load()
        } catch {
            ApolloToast.showError("Couldn't Create Multireddit", detail: UserFacingError.text(for: error))
        }
    }

    private func load() async {
        // Clears a failure from a previous attempt.
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            subscriptions = try await repository.fetchSubscribedSubreddits()
            // A failed fetch keeps what is already shown (cached or earlier) rather than
            // blanking the section, and does not overwrite the cache with an empty result.
            if let fetched = await Self.retrying({ try await repository.fetchMultireddits() }) {
                multireddits = fetched
            }
            if let fetched = await Self.retrying({ try await repository.fetchModeratedSubreddits() }) {
                moderatedSubreddits = fetched
            }
            // Confirmed by the network, so the next launch can draw
            // this immediately.
            isShowingCachedLists = false
            await SubredditIconCache.shared.seed(from: subscriptions + moderatedSubreddits)
            if let username = FavoriteSubredditsAccountContext.currentUsernameProvider() {
                SubredditListCache.save(.init(
                    subscriptions: subscriptions,
                    multireddits: multireddits,
                    moderated: moderatedSubreddits,
                    accountUsername: username
                ))
            }
        } catch {
            // Carry the real failure rather than a bare sentence, so the cause is
            // diagnosable.
            errorMessage = "Couldn't load subscriptions. \(Self.describe(error))"
        }
    }
}

/// What the user tapped in `SubredditsRootScreen`; the caller (the Posts tab)
/// resolves it into the right pushed `FeedScreen`.
public enum SubredditsRootDestination: Hashable {
    case home
    case popular
    case all
    case moderator
    case subreddit(String)
    /// Apollo renders the user's multireddits inline in the first section, after the
    /// four pseudo-feeds, with the subtitle "A group of subreddits".
    case multireddit(path: String, name: String)
}

#if canImport(UIKit)
/// Opens the list scrolled just past its first row (the filter field),
/// once, the way Apollo tucks "Filter Subreddits" under the nav bar at
/// rest. Pulling down reveals it.
private struct FirstRowTucker: UIViewRepresentable {
    final class Probe: UIView {
        private var tucked = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            tuck(attempt: 0)
        }

        private func tuck(attempt: Int) {
            guard !tucked, window != nil, attempt < 20 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, !self.tucked else { return }
                guard let list = self.list(),
                      list.numberOfSections > 1,
                      list.numberOfItems(inSection: 0) > 0,
                      let row = list.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)) else {
                    self.tuck(attempt: attempt + 1)
                    return
                }
                let rest = -list.adjustedContentInset.top
                // Only from the untouched rest position.
                guard abs(list.contentOffset.y - rest) < 1 else { self.tucked = true; return }
                self.tucked = true
                list.setContentOffset(CGPoint(x: 0, y: rest + row.frame.maxY), animated: false)
            }
        }

        private func list() -> UICollectionView? {
            var view: UIView? = superview
            while let current = view {
                if let found = UIKitTree.firstDescendant(of: UICollectionView.self, in: current, where: { $0.bounds.height > 200 }) {
                    return found
                }
                view = current.superview
            }
            return nil
        }
    }

    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ uiView: Probe, context: Context) {}
}
#else
private struct FirstRowTucker: View { var body: some View { EmptyView() } }
#endif

extension View {
    /// Modern Subreddit Dividers (with List Enhancements) draws no row
    /// hairlines; off, the list keeps the stock single-line separators,
    /// as Reborn switches the table's separator style.
    func apolloSubredditRowSeparator(modern: Bool) -> some View {
        listRowSeparator(modern ? .hidden : .visible)
    }
}
