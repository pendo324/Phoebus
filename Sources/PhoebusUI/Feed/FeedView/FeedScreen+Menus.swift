import SwiftUI
import PhoebusCore

/// The feed's menus: the post hold/••• menu, sort and timeframe sheets, and the subreddit, multireddit and overflow rows.
extension FeedScreen {
    var availableSorts: [String] {
        (subreddit.isEmpty && multiredditPath == nil) ? Self.sorts : Self.subredditSorts
    }

    /// Sort sheet rows: per-row icon, checkmark on the active sort,
    /// chevron on Top (time-period sub-sheet).
    var sortSheetRows: [ApolloActionSheetRow] {
        availableSorts.map { s in
            ApolloActionSheetRow(
                s.capitalized,
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

    /// The subreddit "•••" menu, in Apollo's order. "Set User Flair" is a
    /// gap: no flair-selection endpoint is wired in `RedditRepository`.
    var subredditActionRows: [ApolloActionSheetRow] {
        var rows: [ApolloActionSheetRow] = []

        // Gallery View, alone in the leading section; the composer icon row
        // sits above it.
        rows.append(ApolloActionSheetRow("Gallery View", icon: "square.grid.2x2", accessibilityIdentifier: "feed.overflow.galleryView") {
            showingGallerySheet = true
        })

        if !subreddit.isEmpty {
            // Subscribe/Unsubscribe: the row states the action, not
            // the state. Reuses the header's own subscription state
            // (`currentlySubscribedToHeaderSubreddit`) rather than a
            // second source of truth.
            let subscribed = currentlySubscribedToHeaderSubreddit()
            rows.append(ApolloActionSheetRow(subscribed ? "Unsubscribe" : "Subscribe",
                                             icon: subscribed ? "heart.slash" : "heart",
                                             startsSection: true,
                                             accessibilityIdentifier: "feed.overflow.subscribeToggle") {
                Task {
                    await toggleHeaderSubscribe()
                    await SubscribedSubredditsCache.shared.invalidate()
                }
            })
            rows.append(ApolloActionSheetRow(FavoriteSubredditsStore.isFavorite(subreddit) ? "Unfavorite" : "Favorite",
                                             icon: FavoriteSubredditsStore.isFavorite(subreddit) ? "star.slash" : "star",
                                             accessibilityIdentifier: "feed.overflow.favoriteToggle") {
                FavoriteSubredditsStore.toggle(subreddit)
            })
        }

        // Apollo's native "Hide Read Posts" action (Reborn Action Menus
        // id `hide-read`), the same as the floating button.
        rows.append(ApolloActionSheetRow("Hide Read Posts", icon: "option-hide-read",
                                         accessibilityIdentifier: "feed.overflow.hideReadToggle") {
            hideReadPosts()
        })

        if !subreddit.isEmpty {
            rows.append(ApolloActionSheetRow("Sidebar", icon: "sidebar.right", accessibilityIdentifier: "feed.overflow.sidebar") {
                showingSidebarSheet = true
            })
            rows.append(ApolloActionSheetRow("Subreddit Rules", icon: "list.bullet.rectangle", accessibilityIdentifier: "feed.overflow.rules") {
                showingRulesSheet = true
            })
            rows.append(ApolloActionSheetRow("Filter Subreddit", icon: "circle.slash", accessibilityIdentifier: "feed.overflow.filterSubreddit") {
                var filters = ContentFilterStore.load()
                filters.append(ContentFilter(kind: .subreddit, value: subreddit))
                ContentFilterStore.save(filters)
            })
        }

        rows.append(ApolloActionSheetRow(effectivePostDisplayStyle == .compact ? "Large Thumbnails" : "Compact Posts",
                                         icon: "rectangle.grid.1x2",
                                         accessibilityIdentifier: "feed.overflow.compactToggle") {
            let newStyle: PostDisplayStyle = effectivePostDisplayStyle == .compact ? .large : .compact
            // Post Size Per Subreddit: only this subreddit changes.
            if PostSizeMemoryStore.recordSizeChange(subreddit: subreddit, style: newStyle) {
                localPostSize = newStyle
            } else {
                $generalSettings.postDisplayStyle.wrappedValue = newStyle
            }
        })

        if !subreddit.isEmpty {
            rows.append(ApolloActionSheetRow("Set User Flair", icon: "tag", accessibilityIdentifier: "feed.overflow.setUserFlair") {
                showingUserFlair = true
            })
            // The sidebar screen already renders a moderator list; this links
            // straight to it.
            rows.append(ApolloActionSheetRow("View Moderators", icon: "person.2.badge.gearshape", accessibilityIdentifier: "feed.overflow.viewModerators") {
                showingModeratorsSheet = true
            })
        }
        if !subreddit.isEmpty {
            // Apollo's per-subreddit post notifications (Reddit's
            // `/api/subreddit_notifications`).
            rows.append(ApolloActionSheetRow("Subreddit Notifications", icon: "bell", accessibilityIdentifier: "feed.overflow.subredditNotifications") {
                showingSubredditNotifications = true
            })
        }

        // Moderator-only. Not in Apollo's stock menu, but this app implements
        // Mod Queue and hiding a working screen would be worse than appending
        // one row a moderator expects.
        if isModerator {
            rows.append(ApolloActionSheetRow("Mod Queue", icon: "shield", accessibilityIdentifier: "feed.overflow.modQueue") {
                showingModQueueSheet = true
            })
        }
        return rows
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
