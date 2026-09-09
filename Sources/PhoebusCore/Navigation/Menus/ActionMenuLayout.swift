import Foundation

/// Reborn "Action Menus" (#1131, Interface → Menus): per-menu order and
/// hidden set for Apollo's ••• menus. Contexts, item ids, titles and each
/// menu's default order are Reborn's, and storage uses Reborn's shape
/// under the same key (`ActionMenuLayouts`: `{context: {order, hidden}}`),
/// so a Reborn backup imports as is.
///
/// A menu with no stored entry is left exactly as the app builds it.
/// Catalogue items added later append after a saved order, visible. A
/// locked item (the feed's Submit Post) always heads the menu and is
/// never hidden.
public enum ActionMenuContext: String, CaseIterable, Sendable, Identifiable {
    case feed
    case post
    case postDetail = "post-detail"
    case comment
    case moderatorSubreddit = "moderator-subreddit"
    case moderatorPost = "moderator-post"
    case moderatorComment = "moderator-comment"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .feed: return "Feed"
        case .post: return "Post"
        case .postDetail: return "Post (Comments)"
        case .comment: return "Comment"
        case .moderatorSubreddit: return "Moderator (Subreddit)"
        case .moderatorPost: return "Moderator (Post)"
        case .moderatorComment: return "Moderator (Comment)"
        }
    }

    public var detail: String {
        switch self {
        case .feed: return "The ••• button at the top of a subreddit or feed."
        case .post: return "The ••• button on a post in a feed."
        case .postDetail: return "The ••• button at the top of a post's comments."
        case .comment: return "The ••• button on a comment."
        case .moderatorSubreddit: return "The moderator shield at the top of a subreddit you moderate."
        case .moderatorPost: return "The moderator shield on a post, the Moderator row in a post’s ••• menus, and the shield at the top of its comments."
        case .moderatorComment: return "The moderator shield on a comment, and the Moderator row in its ••• menu."
        }
    }

    public var isModerator: Bool {
        switch self {
        case .moderatorSubreddit, .moderatorPost, .moderatorComment: return true
        default: return false
        }
    }

    /// The ••• menus, then the moderator menus, as Reborn lists them.
    public static var menus: [ActionMenuContext] { [.feed, .post, .postDetail, .comment] }
    public static var moderatorMenus: [ActionMenuContext] { [.moderatorSubreddit, .moderatorPost, .moderatorComment] }
}

public struct ActionMenuItem: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    /// SF Symbol for the editor and preview.
    public let symbol: String
    /// Rows the menu shows as a matter of course; the rest only appear
    /// sometimes (your own post's Edit/Delete, a feature that is off).
    public let usuallyShown: Bool
    /// Always first and never hidden.
    public let locked: Bool

    init(_ id: String, _ title: String, _ symbol: String, usual: Bool = true, locked: Bool = false) {
        self.id = id; self.title = title; self.symbol = symbol
        self.usuallyShown = usual; self.locked = locked
    }

    func sometimes() -> ActionMenuItem { ActionMenuItem(id, title, symbol, usual: false, locked: locked) }
    func lockedItem() -> ActionMenuItem { ActionMenuItem(id, title, symbol, usual: usuallyShown, locked: true) }
}

public enum ActionMenuCatalog {
    // Native rows (Reborn item ids).
    static let upvote = ActionMenuItem("upvote", "Upvote", "arrow.up")
    static let downvote = ActionMenuItem("downvote", "Downvote", "arrow.down")
    static let save = ActionMenuItem("save", "Save", "bookmark")
    static let reply = ActionMenuItem("reply", "Reply", "arrowshape.turn.up.left")
    static let author = ActionMenuItem("author", "Author", "person.circle")
    static let subreddit = ActionMenuItem("subreddit", "Subreddit", "house")
    static let hide = ActionMenuItem("hide", "Hide", "eye.slash")
    static let hideAbove = ActionMenuItem("hide-above", "Hide Posts Above", "eye.slash.circle")
    static let share = ActionMenuItem("share", "Share", "square.and.arrow.up")
    static let shareImage = ActionMenuItem("share-image", "Share as Image", "photo.badge.plus")
    static let crosspost = ActionMenuItem("crosspost", "Crosspost", "arrowshape.turn.up.right")
    static let award = ActionMenuItem("award", "Give Award", "medal")
    static let report = ActionMenuItem("report", "Report", "flag")
    static let translate = ActionMenuItem("translate", "Translate", "character.bubble")
    static let edit = ActionMenuItem("edit", "Edit", "pencil")
    static let delete = ActionMenuItem("delete", "Delete", "trash")
    static let nsfw = ActionMenuItem("nsfw", "Mark NSFW", "exclamationmark.triangle")
    static let spoiler = ActionMenuItem("spoiler", "Mark Spoiler", "eye.trianglebadge.exclamationmark")
    static let selectText = ActionMenuItem("select-text", "Select Text", "selection.pin.in.out")
    static let moderator = ActionMenuItem("moderator", "Moderator", "shield")
    static let filterSubreddit = ActionMenuItem("filter-subreddit", "Filter Subreddit", "line.3.horizontal.decrease.circle")
    static let collapseTop = ActionMenuItem("collapse-top", "Collapse to Top", "arrow.up.to.line")
    static let viewReplies = ActionMenuItem("view-replies", "View All Replies", "text.bubble")
    static let parent = ActionMenuItem("parent-comment", "Parent Comment", "arrow.turn.left.up")
    static let find = ActionMenuItem("find", "Find in Comments", "magnifyingglass")
    static let liveActivity = ActionMenuItem("live-activity", "Live Activity", "clock.badge")
    static let collapseChildren = ActionMenuItem("collapse-children", "Collapse Child Comments", "chevron.up.2")
    static let submit = ActionMenuItem("submit", "Submit Post", "square.and.pencil")
    static let subscribe = ActionMenuItem("subscribe", "Subscribe", "plus.circle")
    static let favorite = ActionMenuItem("favorite", "Favorite", "star")
    static let hideRead = ActionMenuItem("hide-read", "Hide Read Posts", "eye.slash")
    static let sidebar = ActionMenuItem("sidebar", "Sidebar", "sidebar.right")
    static let rules = ActionMenuItem("rules", "Subreddit Rules", "list.number")
    static let multireddit = ActionMenuItem("multireddit", "Add to Multireddit", "rectangle.stack.badge.plus")
    static let postSize = ActionMenuItem("post-size", "Compact Posts", "rectangle.compress.vertical")
    static let userFlair = ActionMenuItem("user-flair", "Set User Flair", "tag")
    static let moderators = ActionMenuItem("moderators", "View Moderators", "person.2")
    static let notifications = ActionMenuItem("notifications", "Subreddit Notifications", "bell")
    static let postFlair = ActionMenuItem("post-flair", "Set Post Flair", "tag")
    static let excludeSubscriptions = ActionMenuItem("exclude-subscriptions", "Exclude Subscriptions", "nosign")
    static let muteNotifications = ActionMenuItem("mute-notifications", "Mute Notifications", "bell.slash")
    // Reborn's own rows, stored as `spec.<identifier>`.
    static let floatingTabs = ActionMenuItem("spec.FloatingTabs", "Keep in Floating Tab", "pin.circle")
    static let deletedComments = ActionMenuItem("spec.DeletedComments", "Show Deleted Comments", "eye")
    static let galleryView = ActionMenuItem("spec.GalleryView", "Gallery View", "square.grid.2x2")
    // Moderator rows.
    static let modApprove = ActionMenuItem("mod-approve", "Approve", "checkmark.shield")
    static let modRemove = ActionMenuItem("mod-remove", "Remove", "xmark.shield")
    static let modSpam = ActionMenuItem("mod-spam", "Mark Spam", "exclamationmark.shield")
    static let modOC = ActionMenuItem("mod-oc", "Mark OC", "c.circle")
    static let modSticky = ActionMenuItem("mod-sticky", "Sticky", "pin")
    static let modLock = ActionMenuItem("mod-lock", "Lock", "lock")
    static let modIgnore = ActionMenuItem("mod-ignore-reports", "Ignore Reports", "flag.slash")
    static let modViewReports = ActionMenuItem("mod-view-reports", "View Reports", "flag")
    static let modDistinguish = ActionMenuItem("mod-distinguish", "Distinguish", "shield.lefthalf.filled")
    static let modSuggested = ActionMenuItem("mod-suggested-sort", "Set Suggested Sort", "arrow.up.arrow.down")
    static let modContest = ActionMenuItem("mod-contest-mode", "Enable Contest Mode", "trophy")
    static let modBanUser = ActionMenuItem("mod-ban-user", "Ban User", "hand.raised")
    static let modNuke = ActionMenuItem("mod-nuke", "Comment Nuke", "flame")
    static let modCompliment = ActionMenuItem("mod-compliment", "Get Compliment", "hand.thumbsup")
    static let modMail = ActionMenuItem("mod-mail", "Mod Mail", "envelope")
    static let modQueue = ActionMenuItem("mod-queue", "Mod Queue", "tray.full")
    static let modLog = ActionMenuItem("mod-log", "Mod Log", "list.bullet.rectangle")
    static let modReports = ActionMenuItem("mod-reports", "Reports", "flag")
    static let modSpamQueue = ActionMenuItem("mod-spam-queue", "Spam", "exclamationmark.shield")
    static let modUnmoderated = ActionMenuItem("mod-unmoderated", "Unmoderated", "eye.slash")
    static let modEdited = ActionMenuItem("mod-edited", "Edited", "pencil")
    static let modAllComments = ActionMenuItem("mod-all-comments", "All Comments", "text.bubble")
    static let modTraffic = ActionMenuItem("mod-traffic", "Traffic Stats", "chart.bar")
    static let modBanUsers = ActionMenuItem("mod-ban-users", "Ban Users", "hand.raised")
    static let modMuteUsers = ActionMenuItem("mod-mute-users", "Mute Users", "speaker.slash")
    static let modEditFlair = ActionMenuItem("mod-edit-flair", "Edit Flair", "tag")
    static let modRemovalReasons = ActionMenuItem("mod-removal-reasons", "Removal Reason", "text.badge.xmark")
    static let modRules = ActionMenuItem("mod-rules", "Rules", "list.number")
    static let modAutoMod = ActionMenuItem("mod-automoderator", "AutoModerator", "gearshape.2")
    static let modApproved = ActionMenuItem("mod-approved-submitters", "Approved Submitters", "person.badge.shield.checkmark")
    static let modModerators = ActionMenuItem("mod-moderators", "Moderators", "shield")

    /// Each menu's items in Apollo's own default order: usual rows, then
    /// rows it only adds sometimes.
    public static func items(for context: ActionMenuContext) -> [ActionMenuItem] {
        switch context {
        case .feed:
            return [submit.lockedItem(), galleryView, subscribe, favorite, hideRead, sidebar, rules,
                    filterSubreddit, multireddit, postSize, userFlair, moderators, share, notifications,
                    excludeSubscriptions.sometimes()]
        case .post:
            return [moderator.sometimes(), upvote, downvote, save, reply, author, subreddit, hide, hideAbove,
                    share, shareImage, crosspost, award, report, floatingTabs.sometimes()]
                + [translate, filterSubreddit, edit, delete, nsfw, spoiler, postFlair, muteNotifications].map { $0.sometimes() }
        case .postDetail:
            return [moderator.sometimes(), upvote, downvote, save, reply, author, subreddit, collapseChildren, selectText, share,
                    shareImage, crosspost, find, award, report, liveActivity,
                    deletedComments.sometimes(), floatingTabs.sometimes()]
                + [translate, edit, delete, nsfw, spoiler, postFlair, muteNotifications].map { $0.sometimes() }
        case .comment:
            return [moderator.sometimes(), upvote, downvote, save, reply, author, selectText, share,
                    shareImage, collapseTop, award, report]
                + [viewReplies, parent, translate, edit, delete, muteNotifications].map { $0.sometimes() }
        case .moderatorSubreddit:
            return [modMail, modQueue, modLog, modReports, modSpamQueue, modUnmoderated, modEdited,
                    modAllComments, modTraffic, modBanUsers, modMuteUsers, modEditFlair, modRemovalReasons,
                    modRules, modAutoMod, modApproved, modModerators, report, modCompliment]
        case .moderatorPost:
            return [modApprove, modRemove, modSpam, nsfw, spoiler, modOC, postFlair, modSticky, modLock,
                    modIgnore, modBanUser, modCompliment]
                + [modDistinguish, modViewReports, modSuggested, modContest].map { $0.sometimes() }
        case .moderatorComment:
            return [modApprove, modRemove, modSpam, modIgnore, modLock, modNuke, modBanUser, modCompliment]
                + [modDistinguish, modSticky, modViewReports].map { $0.sometimes() }
        }
    }

    public static func item(_ id: String, in context: ActionMenuContext) -> ActionMenuItem? {
        items(for: context).first { $0.id == id }
    }
}

/// The saved layouts, `UserDefaults` key `ActionMenuLayouts`.
public enum ActionMenuLayoutStore {
    public static let key = "ActionMenuLayouts"
    static let orderKey = "order"
    static let hiddenKey = "hidden"

    nonisolated(unsafe) public static var defaults: UserDefaults = .standard

    static func layouts() -> [String: [String: [String]]] {
        guard let raw = defaults.dictionary(forKey: key) else { return [:] }
        var result: [String: [String: [String]]] = [:]
        for (context, value) in raw {
            guard let layout = value as? [String: Any] else { continue }
            var parsed: [String: [String]] = [:]
            for field in [orderKey, hiddenKey] {
                if let list = layout[field] as? [Any] {
                    var seen: [String] = []
                    for case let id as String in list where !seen.contains(id) { seen.append(id) }
                    parsed[field] = seen
                }
            }
            result[context] = parsed
        }
        return result
    }

    static func write(_ layouts: [String: [String: [String]]]) {
        let cleaned = layouts.filter { !($0.value[orderKey] ?? []).isEmpty || !($0.value[hiddenKey] ?? []).isEmpty }
        if cleaned.isEmpty { defaults.removeObject(forKey: key) } else { defaults.set(cleaned, forKey: key) }
        NotificationCenter.default.post(name: .apolloActionMenuLayoutsChanged, object: nil)
    }

    static func stored(_ context: ActionMenuContext, _ field: String) -> [String] {
        layouts()[context.rawValue]?[field] ?? []
    }

    /// Saved order restricted to the catalogue, new catalogue items
    /// appended, locked items first.
    public static func resolvedOrder(_ context: ActionMenuContext) -> [String] {
        let catalog = ActionMenuCatalog.items(for: context)
        let catalogIDs = catalog.map(\.id)
        var order = stored(context, orderKey).filter { catalogIDs.contains($0) }
        for id in catalogIDs where !order.contains(id) { order.append(id) }
        let locked = catalog.filter(\.locked).map(\.id)
        return locked + order.filter { !locked.contains($0) }
    }

    public static func hiddenIDs(_ context: ActionMenuContext) -> Set<String> {
        Set(stored(context, hiddenKey).filter {
            guard let item = ActionMenuCatalog.item($0, in: context) else { return false }
            return !item.locked
        })
    }

    public static func hasCustomOrder(_ context: ActionMenuContext) -> Bool {
        !stored(context, orderKey).isEmpty
    }

    public static func isCustomized(_ context: ActionMenuContext) -> Bool {
        hasCustomOrder(context) || !hiddenIDs(context).isEmpty
    }

    public static func setOrder(_ order: [String], for context: ActionMenuContext) {
        var all = layouts()
        var layout = all[context.rawValue] ?? [:]
        layout[orderKey] = order
        all[context.rawValue] = layout
        write(all)
    }

    public static func setHidden(_ hidden: Bool, itemID: String, for context: ActionMenuContext) {
        guard let item = ActionMenuCatalog.item(itemID, in: context), !item.locked else { return }
        var all = layouts()
        var layout = all[context.rawValue] ?? [:]
        var set = layout[hiddenKey] ?? []
        set.removeAll { $0 == itemID }
        if hidden { set.append(itemID) }
        layout[hiddenKey] = set
        all[context.rawValue] = layout
        write(all)
    }

    public static func reset(_ context: ActionMenuContext) {
        var all = layouts()
        all[context.rawValue] = nil
        write(all)
    }

    public static func resetAll() { write([:]) }

    /// Row subtitle in the menu list ("Default", "Custom order · 2 hidden").
    public static func summary(_ context: ActionMenuContext) -> String {
        let order = hasCustomOrder(context)
        let hidden = hiddenIDs(context).count
        if !order && hidden == 0 { return "Default" }
        var parts: [String] = []
        if order { parts.append("Custom order") }
        if hidden > 0 { parts.append("\(hidden) hidden") }
        return parts.joined(separator: " · ")
    }

    /// The Interface row's subtitle ("Default" or "Customized: Feed, Comment").
    public static func interfaceSummary() -> String {
        let customized = ActionMenuContext.allCases.filter(isCustomized).map(\.title)
        return customized.isEmpty ? "Default" : "Customized: " + customized.joined(separator: ", ")
    }

    /// Applies the layout to the entries a menu offers right now, given
    /// in the app's own order. Hidden items drop out. With a custom order,
    /// catalogued entries sort by their rank; an entry the catalogue does
    /// not know (this app's extra rows, such as Copy Link) stays attached
    /// to the catalogued entry before it, so it moves with its neighbour
    /// instead of sinking to the bottom.
    public static func arrange(_ ids: [String], for context: ActionMenuContext) -> [String] {
        guard isCustomized(context) else { return ids }
        let hidden = hiddenIDs(context)
        let catalogIDs = Set(ActionMenuCatalog.items(for: context).map(\.id))
        // Group each catalogued id with the unknown ids that follow it.
        var groups: [(anchor: String?, members: [String])] = []
        for id in ids {
            if catalogIDs.contains(id) || groups.isEmpty {
                groups.append((catalogIDs.contains(id) ? id : nil, [id]))
            } else {
                groups[groups.count - 1].members.append(id)
            }
        }
        if hasCustomOrder(context) {
            let rank = Dictionary(uniqueKeysWithValues: resolvedOrder(context).enumerated().map { ($1, $0) })
            groups = groups.enumerated().sorted { lhs, rhs in
                let l = lhs.element.anchor.flatMap { rank[$0] } ?? -1
                let r = rhs.element.anchor.flatMap { rank[$0] } ?? -1
                return l == r ? lhs.offset < rhs.offset : l < r
            }.map(\.element)
        }
        return groups.flatMap { group -> [String] in
            guard let anchor = group.anchor, hidden.contains(anchor) else { return group.members }
            // The anchor is hidden; its attached extras stay.
            return Array(group.members.dropFirst())
        }
    }
}

public extension Notification.Name {
    /// An Action Menus layout changed.
    static let apolloActionMenuLayoutsChanged = Notification.Name("ApolloActionMenuLayoutsChangedNotification")
}
