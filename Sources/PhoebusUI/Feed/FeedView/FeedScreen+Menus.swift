import SwiftUI
import PhoebusCore

/// The feed's menus: the post hold/••• menu, sort and timeframe sheets, and the subreddit, multireddit and overflow rows.
extension FeedScreen {
    /// A post's hold and ••• menu; see `PostActionMenuContent`. Kept out of
    /// the row's inline `.contextMenu` so the row's body stays within the
    /// type-checker's budget.
    @ViewBuilder
    func postContextMenu(for post: RedditPost) -> some View {
        PostActionMenuContent(post: post, repository: repository, signedInUsername: signedInUsername,
                              isModerator: isModerator) { action in
            performPostMenuAction(action, on: post)
        }
    }

    func performPostMenuAction(_ action: PostMenuAction, on post: RedditPost) {
        switch action {
        case .save:
            Task { await handleSwipeAction(.save, on: post) }
        case .hide:
            Task { await handleSwipeAction(.hide, on: post) }
        case .copyLink:
            PasteboardHelper.copy(url: post.shareURL())
        case .saveAllMedia:
            SaveAllMediaJob.shared.start(post.galleryImageURLs.map { .image($0) })
        case .crosspost:
            crosspostTarget = post
        case .remindMe:
            remindTarget = post
        case .toggleMute:
            MutedThreadsStore.setMuted(post.name, muted: !MutedThreadsStore.isMuted(post.name))
        case .filterSubreddit:
            var filters = ContentFilterStore.load()
            filters.append(ContentFilter(kind: .subreddit, value: post.subreddit))
            ContentFilterStore.save(filters)
            posts.removeAll { $0.subreddit.caseInsensitiveCompare(post.subreddit) == .orderedSame }
        case .insights:
            insightsTargetPost = post
        case .setFlair:
            flairTargetPost = post
        case .downloadVideo(let videoURL):
            Task {
                downloadTitle = "Download Video"
                do {
                    // The downloadable rendition, not
                    // the playable one: the muxer needs
                    // the progressive `DASH_*.mp4` to
                    // pair with `DASH_audio.mp4`.
                    try await VideoDownloadService.downloadAndSave(
                        videoURL: PostMediaKind.downloadableVideoURL(for: post) ?? videoURL)
                    downloadMessage = "Saved to your photo library."
                } catch {
                    downloadMessage = error.localizedDescription
                }
            }
        case .saveGIF(let gifURL, let asVideo):
            Task { await saveGIF(gifURL, asVideo: asVideo) }
        case .saveGIFInFormat(let gifURL):
            Task {
                do {
                    downloadTitle = "Save GIF"
                    try await GIFSaveService.save(gifURL: gifURL, format: generalSettings.gifSaveFormat, useApolloAlbum: generalSettings.saveToApolloAlbum)
                    downloadMessage = "Saved to your photo library."
                } catch {
                    downloadMessage = error.localizedDescription
                }
            }
        case .subscribe:
            Task {
                try? await repository.subscribe(subredditName: post.subreddit, subscribe: true)
                // Keeps `SubscribedSubredditsCache` (`excludeSubscribedFromAllPopular`)
                // from filtering r/all and r/popular with a stale membership set.
                await SubscribedSubredditsCache.shared.invalidate()
            }
        case .unsubscribe:
            Task {
                try? await repository.subscribe(subredditName: post.subreddit, subscribe: false)
                await SubscribedSubredditsCache.shared.invalidate()
            }
        case .follow:
            Task { try? await repository.followUser(username: post.author) }
        case .block:
            Task { try? await repository.blockUser(username: post.author) }
        case .copyUsername:
            PasteboardHelper.copy(post.author)
        case .tagUser:
            tagTarget = UserTagTarget(username: post.author)
        case .report:
            reportTarget = post
        case .moderator(let action):
            performModeratorAction(action, on: post)
        }
    }

    private func performModeratorAction(_ action: PostModeratorAction, on post: RedditPost) {
        switch action {
        case .approve:
            Task { try? await repository.approve(fullname: post.name) }
        case .remove:
            Task {
                _ = try? await repository.remove(fullname: post.name, isSpam: false)
                posts.removeAll { $0.id == post.id }
            }
        case .spam:
            Task {
                _ = try? await repository.remove(fullname: post.name, isSpam: true)
                posts.removeAll { $0.id == post.id }
            }
        case .distinguish:
            let isDistinguished = post.distinguished == "moderator"
            Task {
                _ = try? await repository.distinguish(fullname: post.name, asMod: !isDistinguished)
                updatePost(post.id) { $0.distinguished = isDistinguished ? nil : "moderator" }
            }
        case .sticky:
            Task {
                _ = try? await repository.setSticky(fullname: post.name, sticky: !post.stickied)
                updatePost(post.id) { $0.stickied = !post.stickied }
            }
        case .lock:
            Task {
                let newLocked = !(post.locked ?? false)
                _ = try? await repository.setLocked(fullname: post.name, locked: newLocked)
                updatePost(post.id) { $0.locked = newLocked }
            }
        case .notes:
            break
        }
    }

    var availableSorts: [String] {
        (subreddit.isEmpty && multiredditPath == nil) ? Self.sorts : Self.subredditSorts
    }

    /// Sort sheet rows: per-row icon, checkmark on the active sort,
    /// chevron on Top (time-period sub-sheet).
    var sortSheetRows: [ApolloActionSheetRow] {
        availableSorts.map { s in
            ApolloActionSheetRow(
                s.capitalized,
                icon: Self.iconName(forSort: s),
                trailing: s == sort ? .checkmark : (s == "top" || s == "controversial" ? .chevron : .none),
                // The chevron's follow-up sheet, expressed as a nested menu for the
                // compact path, as Reborn does.
                submenu: (s == "top" || s == "controversial") ? timeframeSheetRows(for: s) : [],
                accessibilityIdentifier: "feed.sortSheet.\(s)"
            ) {
                sort = s
                if s == "top" || s == "controversial" {
                    showingTimeframeSheet = true
                } else {
                    // Records this pick so the next time this
                    // subreddit is opened, `initialSortAndTimeframe`
                    // restores it instead of reverting to the global default.
                    PostSortMemoryStore.recordSortChange(subreddit: subreddit, sort: s, timeframe: nil)
                    Task { await load() }
                }
            }
        }
    }

    var timeframeSheetRows: [ApolloActionSheetRow] {
        timeframeSheetRows(for: sort)
    }

    /// Time-period rows for `appliedSort`. Takes the sort explicitly
    /// because the compact path builds these as a nested menu before
    /// `sort` is set; reading `self.sort` there would record the
    /// previous sort.
    func timeframeSheetRows(for appliedSort: String) -> [ApolloActionSheetRow] {
        Self.timeframes.map { option in
            ApolloActionSheetRow(
                option.label,
                icon: Self.iconName(forTimeframe: option.value),
                trailing: option.value == topTimeframe ? .checkmark : .none,
                accessibilityIdentifier: "feed.timeframeSheet.\(option.value)"
            ) {
                sort = appliedSort
                topTimeframe = option.value
                PostSortMemoryStore.recordSortChange(subreddit: subreddit, sort: appliedSort, timeframe: option.value)
                Task { await load() }
            }
        }
    }

    var feedOverflowState: FeedOverflowState {
        FeedOverflowState(
            subreddit: subreddit,
            multiredditPath: multiredditPath,
            isSubscribed: currentlySubscribedToHeaderSubreddit(),
            isFavorite: FavoriteSubredditsStore.isFavorite(subreddit),
            isCompact: effectivePostDisplayStyle == .compact,
            canLeaveQuarantine: subredditInfo?.quarantine == true && isSignedIn,
            isModerator: isModerator,
            canCopyMultireddit: multiredditPath.map {
                MultiredditCopy.canCopy(path: $0, signedInUsername: FavoriteSubredditsAccountContext.currentUsernameProvider())
            } ?? false)
    }

    var composerIconRow: [ApolloComposerAction] {
        FeedOverflowMenu.composerRow(feedOverflowState) { performFeedOverflowAction($0) }
    }

    var overflowRows: [ApolloActionSheetRow] {
        FeedOverflowMenu.rows(feedOverflowState) { performFeedOverflowAction($0) }
    }

    func performFeedOverflowAction(_ action: FeedOverflowAction) {
        switch action {
        case .compose(let kind):
            composeKind = kind
            showingCompose = true
        case .galleryView:
            showingGallerySheet = true
        case .toggleSubscribe:
            Task {
                await toggleHeaderSubscribe()
                await SubscribedSubredditsCache.shared.invalidate()
            }
        case .toggleFavorite:
            FavoriteSubredditsStore.toggle(subreddit)
        case .hideRead:
            hideReadPosts()
        case .sidebar:
            showingSidebarSheet = true
        case .rules:
            showingRulesSheet = true
        case .filterSubreddit:
            var filters = ContentFilterStore.load()
            filters.append(ContentFilter(kind: .subreddit, value: subreddit))
            ContentFilterStore.save(filters)
        case .addToMultireddit:
            showingAddToMultireddit = true
        case .toggleCompact:
            let newStyle: PostDisplayStyle = effectivePostDisplayStyle == .compact ? .large : .compact
            // Post Size Per Subreddit: only this subreddit changes.
            if PostSizeMemoryStore.recordSizeChange(subreddit: subreddit, style: newStyle) {
                localPostSize = newStyle
            } else {
                $generalSettings.postDisplayStyle.wrappedValue = newStyle
            }
        case .setUserFlair:
            showingUserFlair = true
        case .viewModerators:
            showingModeratorsSheet = true
        case .share:
            sharingFeedURL = feedShareURL
        case .subredditNotifications:
            showingSubredditNotifications = true
        case .leaveQuarantine:
            Task { await leaveQuarantine() }
        case .modQueue:
            showingModQueueSheet = true
        case .copyMultireddit:
            showingCopyMultireddit = true
        case .editMultireddit:
            if let multiredditPath { editingMultireddit = EditingMultireddit(path: multiredditPath) }
        }
    }

    /// Per-sort icons: the named `option-sort-*` glyphs (see `StockIcon`),
    /// shown on the nav-bar sort button and its menu.
    var sortIconName: String {
        Self.iconName(forSort: sort)
    }

    static func iconName(forSort sort: String) -> String {
        switch sort {
        case "best", "hot", "new", "top", "rising", "controversial": return "option-sort-\(sort)"
        // Anything not enumerated above falls through to the shared table of
        // Apollo's sort icons, so a new sort gets its icon instead of the
        // generic arrow.
        default: return ApolloMenuIcon.symbol("option-sort-\(sort)", fallback: "arrow.up.arrow.down")
        }
    }

    /// Per-window icons for the Top/Controversial time period. Apollo ships
    /// a distinct asset for every window; these map to the closest SF
    /// Symbol. "six-months" is absent since Reddit's `t` parameter has no
    /// 6-month value.
    static func iconName(forTimeframe value: String) -> String {
        switch value {
        case "hour": return "clock"
        case "day": return "sun.max"
        case "week": return "calendar"
        case "month": return "calendar.badge.clock"
        case "year": return "calendar.circle"
        case "all": return "infinity"
        default: return "clock"
        }
    }
}
