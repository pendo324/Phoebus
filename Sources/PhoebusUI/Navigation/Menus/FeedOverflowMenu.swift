import SwiftUI
import PhoebusCore

/// What a row of a feed's nav-bar ••• menu can do. The feed performs them;
/// the Action Menus preview performs none.
enum FeedOverflowAction {
    case compose(ComposePostScreen.PostType)
    case galleryView, toggleSubscribe, toggleFavorite, hideRead, sidebar, rules, filterSubreddit
    case addToMultireddit, toggleCompact, setUserFlair, viewModerators, share, subredditNotifications
    case leaveQuarantine, modQueue, copyMultireddit, editMultireddit
}

/// What the feed's ••• rows depend on.
struct FeedOverflowState {
    var subreddit: String
    var multiredditPath: String?
    var isSubscribed: Bool
    var isFavorite: Bool
    var isCompact: Bool
    /// An opted-in quarantined subreddit, for a signed-in viewer.
    var canLeaveQuarantine: Bool
    var isModerator: Bool
    /// A multireddit someone else owns can only be copied.
    var canCopyMultireddit: Bool
}

/// The nav-bar ••• menu of a subreddit or multireddit feed: the leading
/// post-type row and the rows, arranged by the Action Menus layout (Reborn
/// #1131, context `feed`).
enum FeedOverflowMenu {
    /// The leading post-type icon row: link+, text+, poll+. Only a
    /// real subreddit gets one; a multireddit or Home has nowhere to
    /// post.
    static func composerRow(_ state: FeedOverflowState, perform: @escaping (FeedOverflowAction) -> Void) -> [ApolloComposerAction] {
        guard !state.subreddit.isEmpty else { return [] }
        return [
            ApolloComposerAction(systemImage: "link.badge.plus", label: "Link Post") { perform(.compose(.link)) },
            ApolloComposerAction(systemImage: "doc.badge.plus", label: "Text Post") { perform(.compose(.text)) },
            ApolloComposerAction(systemImage: "chart.bar.doc.horizontal", label: "Poll") { perform(.compose(.poll)) },
        ]
    }

    /// Whichever menu this feed actually is.
    static func rows(_ state: FeedOverflowState, perform: @escaping (FeedOverflowAction) -> Void) -> [ApolloActionSheetRow] {
        arrange(state.multiredditPath != nil ? multiredditRows(state, perform: perform) : subredditRows(state, perform: perform))
    }

    /// The subreddit "•••" menu, in Apollo's order. "Set User Flair" is a
    /// gap: no flair-selection endpoint is wired in `RedditRepository`.
    private static func subredditRows(_ state: FeedOverflowState, perform: @escaping (FeedOverflowAction) -> Void) -> [ApolloActionSheetRow] {
        var rows: [ApolloActionSheetRow] = []

        // Gallery View, alone in the leading section; the composer icon row
        // sits above it.
        rows.append(ApolloActionSheetRow("Gallery View", icon: "square.grid.2x2", accessibilityIdentifier: "feed.overflow.galleryView") {
            perform(.galleryView)
        })

        if !state.subreddit.isEmpty {
            // Subscribe/Unsubscribe: the row states the action, not
            // the state.
            let subscribed = state.isSubscribed
            rows.append(ApolloActionSheetRow(subscribed ? "Unsubscribe" : "Subscribe",
                                             icon: subscribed ? "heart.slash" : "heart",
                                             startsSection: true,
                                             accessibilityIdentifier: "feed.overflow.subscribeToggle") {
                perform(.toggleSubscribe)
            })
            rows.append(ApolloActionSheetRow(state.isFavorite ? "Unfavorite" : "Favorite",
                                             icon: state.isFavorite ? "star.slash" : "star",
                                             accessibilityIdentifier: "feed.overflow.favoriteToggle") {
                perform(.toggleFavorite)
            })
        }

        // Apollo's native "Hide Read Posts" action (Reborn Action Menus
        // id `hide-read`), the same as the floating button.
        rows.append(ApolloActionSheetRow("Hide Read Posts", icon: "option-hide-read",
                                         accessibilityIdentifier: "feed.overflow.hideReadToggle") {
            perform(.hideRead)
        })

        if !state.subreddit.isEmpty {
            rows.append(ApolloActionSheetRow("Sidebar", icon: "sidebar.right", accessibilityIdentifier: "feed.overflow.sidebar") {
                perform(.sidebar)
            })
            rows.append(ApolloActionSheetRow("Subreddit Rules", icon: "list.bullet.rectangle", accessibilityIdentifier: "feed.overflow.rules") {
                perform(.rules)
            })
            rows.append(ApolloActionSheetRow("Filter Subreddit", icon: "circle.slash", accessibilityIdentifier: "feed.overflow.filterSubreddit") {
                perform(.filterSubreddit)
            })
            // The repository already has the endpoint
            // (`addSubredditToMultireddit`, `PUT /api/multi/<path>/r/<name>`).
            rows.append(ApolloActionSheetRow("Add to Multireddit", icon: "m.circle", accessibilityIdentifier: "feed.overflow.addToMultireddit") {
                perform(.addToMultireddit)
            })
        }

        rows.append(compactRow(state, perform: perform))

        if !state.subreddit.isEmpty {
            rows.append(ApolloActionSheetRow("Set User Flair", icon: "tag", accessibilityIdentifier: "feed.overflow.setUserFlair") {
                perform(.setUserFlair)
            })
            // The sidebar screen already renders a moderator list; this links
            // straight to it.
            rows.append(ApolloActionSheetRow("View Moderators", icon: "person.2.badge.gearshape", accessibilityIdentifier: "feed.overflow.viewModerators") {
                perform(.viewModerators)
            })
        }

        // Share sits second-to-last, not first.
        rows.append(shareRow(perform: perform))

        if !state.subreddit.isEmpty {
            // Apollo's per-subreddit post notifications (Reddit's
            // `/api/subreddit_notifications`).
            rows.append(ApolloActionSheetRow("Subreddit Notifications", icon: "bell", accessibilityIdentifier: "feed.overflow.subredditNotifications") {
                perform(.subredditNotifications)
            })
        }

        // Not in Apollo: undoes "View Anyway". The about data only loads for
        // a quarantined subreddit once opted in, so its flag means opted in.
        if !state.subreddit.isEmpty, state.canLeaveQuarantine {
            rows.append(ApolloActionSheetRow("Leave Quarantine", icon: "eye.slash",
                                             accessibilityIdentifier: "feed.overflow.leaveQuarantine") {
                perform(.leaveQuarantine)
            })
        }

        // Moderator-only. Not in Apollo's stock menu, but this app implements
        // Mod Queue and hiding a working screen would be worse than appending
        // one row a moderator expects.
        if state.isModerator {
            rows.append(ApolloActionSheetRow("Mod Queue", icon: "shield", accessibilityIdentifier: "feed.overflow.modQueue") {
                perform(.modQueue)
            })
        }
        return rows
    }

    /// A multireddit feed's own "•••" rows, kept separate from
    /// `subredditRows` because the two menus differ.
    private static func multiredditRows(_ state: FeedOverflowState, perform: @escaping (FeedOverflowAction) -> Void) -> [ApolloActionSheetRow] {
        var rows: [ApolloActionSheetRow] = []
        rows.append(ApolloActionSheetRow("Gallery View", icon: "square.grid.2x2", accessibilityIdentifier: "feed.overflow.galleryView") {
            perform(.galleryView)
        })
        if state.multiredditPath != nil {
            // Someone else's multireddit can't be edited, only copied (not in
            // Apollo or Reborn; see `MultiredditCopy`).
            if state.canCopyMultireddit {
                rows.append(ApolloActionSheetRow("Copy to My Multireddits", icon: "plus.square.on.square", startsSection: true, accessibilityIdentifier: "feed.overflow.copyMultireddit") {
                    perform(.copyMultireddit)
                })
            } else {
                rows.append(ApolloActionSheetRow("Edit Multireddit", icon: "m.circle", startsSection: true, accessibilityIdentifier: "feed.overflow.editMultireddit") {
                    perform(.editMultireddit)
                })
            }
        }
        rows.append(compactRow(state, perform: perform))
        rows.append(shareRow(perform: perform))
        return rows
    }

    private static func compactRow(_ state: FeedOverflowState, perform: @escaping (FeedOverflowAction) -> Void) -> ApolloActionSheetRow {
        ApolloActionSheetRow(state.isCompact ? "Large Thumbnails" : "Compact Posts",
                             icon: "rectangle.grid.1x2",
                             accessibilityIdentifier: "feed.overflow.compactToggle") {
            perform(.toggleCompact)
        }
    }

    private static func shareRow(perform: @escaping (FeedOverflowAction) -> Void) -> ApolloActionSheetRow {
        ApolloActionSheetRow("Share", icon: "square.and.arrow.up", accessibilityIdentifier: "feed.overflow.share") {
            perform(.share)
        }
    }

    /// Reborn Action Menus (#1131, context `feed`): the nav-bar •••
    /// rows keyed by their accessibility identifiers.
    static let itemIDs: [String: String] = [
        "feed.overflow.galleryView": "spec.GalleryView",
        "feed.overflow.subscribeToggle": "subscribe",
        "feed.overflow.favoriteToggle": "favorite",
        "feed.overflow.hideReadToggle": "hide-read",
        "feed.overflow.sidebar": "sidebar",
        "feed.overflow.rules": "rules",
        "feed.overflow.filterSubreddit": "filter-subreddit",
        "feed.overflow.addToMultireddit": "multireddit",
        "feed.overflow.compactToggle": "post-size",
        "feed.overflow.setUserFlair": "user-flair",
        "feed.overflow.viewModerators": "moderators",
        "feed.overflow.share": "share",
        "feed.overflow.subredditNotifications": "notifications",
    ]

    static func arrange(_ rows: [ApolloActionSheetRow]) -> [ApolloActionSheetRow] {
        guard ActionMenuLayoutStore.isCustomized(.feed) else { return rows }
        let keyed = rows.enumerated().map { index, row in
            (key: row.accessibilityIdentifier.flatMap { itemIDs[$0] } ?? "row.\(index)", row: row)
        }
        let byKey = Dictionary(keyed.map { ($0.key, $0.row) }, uniquingKeysWith: { first, _ in first })
        return ActionMenuLayoutStore.arrange(keyed.map(\.key), for: .feed).compactMap { byKey[$0] }
    }
}
