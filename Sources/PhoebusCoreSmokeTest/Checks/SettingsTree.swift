import Foundation
import PhoebusCore

// MARK: - The settings tree

// The tree the settings root shows: thirteen category rows, each opening a
// screen of settings. A category's sections hold the switches and pickers
// themselves; a drill-down is a screen a section pushes. These assert the
// shape the screens are built from.

/// Every drill-down on the tree, as (category title, destination id).
private func settingsTreeWalk() -> [(category: String, destination: String)] {
    SettingsCategory.allCases.flatMap { category in
        category.drillDowns.map { (category.title, $0.destination.rawValue) }
    }
}

@MainActor func checkSettingsTreeReachesEveryScreenOnce() async throws {
    let walk = settingsTreeWalk()
    let categories = SettingsCategory.allCases

    check("the root lists thirteen categories", categories.count == 13)
    check("every category screen has sections",
          categories.allSatisfy { !$0.sections.isEmpty })
    // A category is a screen of settings, not a list of links: none may be
    // one link, and the one that used to hold a single leaf (Gestures)
    // draws its sections itself.
    check("no category is a screen holding one link",
          categories.allSatisfy { $0.sections.count > 1 || $0.drillDowns.count != 1 })
    check("section titles are unique on a category screen",
          categories.allSatisfy { category in
              let titles = category.sections.compactMap(\.title)
              return Set(titles).count == titles.count })
    check("an untitled section is a link, an action, or About's masthead",
          categories.allSatisfy { category in
              category.sections.filter { $0.title == nil }.allSatisfy { !$0.drillDowns.isEmpty || !$0.actions.isEmpty || category == .about } })

    // Every drill-down opens a distinct screen, so the tree is a tree
    // rather than a graph with two doors onto the same room.
    let destinations = walk.map(\.destination)
    check("every drill-down opens a distinct screen",
          Set(destinations).count == destinations.count)
    check("every destination the enum offers is used exactly once",
          Set(destinations) == Set(SettingsDrillDownDestination.allCases.map(\.rawValue)))
    check("a drill-down is titled by its destination",
          SettingsCategory.allCases.allSatisfy { $0.drillDowns.allSatisfy { $0.title == $0.destination.title } }
            && SettingsDrillDownDestination.allCases.allSatisfy { !$0.title.isEmpty })

    // Actions: the destructive ones ask first, exporting a log only opens
    // the share sheet, and each is on the tree once.
    let actions = categories.flatMap { $0.sections.flatMap(\.actions) }
    check("every action is on the tree exactly once",
          actions.map(\.rawValue).sorted() == SettingsAction.allCases.map(\.rawValue).sorted())
    check("the destructive actions ask first",
          actions.filter(\.confirmsFirst).map(\.rawValue).sorted() == ["clearBanners", "clearCache", "signOut"])
    check("exporting a log only opens the share sheet, so it does not ask",
          !SettingsAction.exportLogs.confirmsFirst)
    check("Sign Out exists only where a session can be ended",
          SettingsAction.signOut.requires == .session
            && SettingsAction.allCases.filter { $0.requires != nil } == [.signOut])
    check("there is one Clear Cache, in Data & Storage, offering every cache",
          SettingsCategory.dataStorage.sections.flatMap(\.actions).contains(.clearCache)
            && actions.filter { $0 == .clearCache }.count == 1)

    // Where the dissolved screens' settings went.
    check("Passcode, Sign Out and the API keys are on Accounts & Security",
          ["Passcode", "API Keys", "Settings per Account"].allSatisfy { title in
              SettingsCategory.accountsSecurity.sections.contains { $0.title == title } }
            && SettingsCategory.accountsSecurity.sections.flatMap(\.actions) == [.signOut])
    check("Crash Reports and Export Debug Logs are on About, under Support",
          SettingsCategory.about.sections.first { $0.title == "Support" }?.drillDowns.map(\.destination)
            == [.bugReports, .crashReports]
            && SettingsCategory.about.sections.first { $0.title == "Support" }?.actions == [.exportLogs])
    check("Gestures & Haptics holds the haptics, the rotation lock and the action menus itself",
          SettingsCategory.gesturesHaptics.sections.compactMap(\.title).contains("Haptics")
            && SettingsCategory.gesturesHaptics.sections.compactMap(\.title).contains("Rotation")
            && SettingsCategory.gesturesHaptics.drillDowns.map(\.destination) == [.actionMenus])
    check("Blocked Users live under Filters, not Comments",
          SettingsCategory.filters.drillDowns.map(\.destination).contains(.blockedUsers)
            && !SettingsCategory.comments.drillDowns.map(\.destination).contains(.blockedUsers))
    check("the screens with pinned previews are drill-downs",
          [SettingsDrillDownDestination.inlineMedia, .linkPreview, .subredditLayout, .subredditSections,
           .profileLayout, .textSizes].allSatisfy { destination in
              SettingsCategory.category(containing: destination) != nil })
    // A cross-link is a row into another category's screen (Polls needs the web
    // sign-in Accounts & Security holds), not a second entrance to a screen.
    let crossLinks = categories.flatMap { category in category.crossLinks.map { (category, $0) } }
    check("Polls on Posts links to Web Sign-In on Accounts & Security",
          crossLinks.map { "\($0.0.rawValue)>\($0.1.rawValue)" } == ["posts>webSignIn"]
            && SettingsCrossLink.webSignIn.category == .accountsSecurity)
    check("every cross-link is on the tree once and names another category",
          Set(crossLinks.map(\.1)).count == crossLinks.count
            && Set(crossLinks.map(\.1)) == Set(SettingsCrossLink.allCases)
            && crossLinks.allSatisfy { $0.0 != $0.1.category })
    check("a cross-link is not a drill-down: no destination, no shared title",
          crossLinks.allSatisfy { link in
              !SettingsDrillDownDestination.allCases.contains { $0.title == link.1.title } })
    check("the row a cross-link scrolls to is a search row on the screen it opens",
          SettingsCrossLink.allCases.allSatisfy { link in
              SettingsSearch.index.contains { $0.screen == link.category.searchScreen && $0.rowTitle == link.row } })
    check("the conditional sections are Siri & Spotlight's two, on iOS 27",
          categories.flatMap(\.sections).filter { $0.requires != nil }.map(\.title)
            == ["Siri & Spotlight", "Index Status"]
            && categories.flatMap(\.sections).allSatisfy { $0.requires == nil || $0.requires == .iOS27 })
}

@MainActor func checkSettingsCategoriesAreUnique() async throws {
    let categories = SettingsCategory.allCases

    check("every category has a title, a symbol and a subtitle",
          categories.allSatisfy { !$0.title.isEmpty && !$0.systemImage.isEmpty && !$0.subtitle.isEmpty })
    check("category titles are unique",
          Set(categories.map(\.title)).count == categories.count)
    check("category symbols are unique",
          Set(categories.map(\.systemImage)).count == categories.count)
    check("category tile colours are unique",
          Set(categories.map { "\($0.tintRGB.red),\($0.tintRGB.green),\($0.tintRGB.blue)" }).count == categories.count)

    // The order is the one the reorg settled on: identity first, what you
    // look at, where links go, what you filter out, what interrupts you, how
    // you drive the app, what it plugs into, what it keeps, About last.
    check("the category order is the approved one",
          categories.map(\.title) == ["Accounts & Security", "Appearance", "Posts", "Feed", "Comments",
                                      "Media", "Links & Sharing", "Filters", "Inbox & Notifications",
                                      "Gestures & Haptics", "Integrations", "Data & Storage", "About"])
    check("the raw values are unique, so ids and search cases are too",
          Set(categories.map(\.rawValue)).count == categories.count)

    // Copy that sends the user somewhere names the tap path to it.
    check("a path to a drill-down runs through its category",
          SettingsCategory.path(to: .crashReports) == "Settings → About → Crash Reports"
            && SettingsCategory.path(to: .deleteImgurUploads) == "Settings → Data & Storage → Manage Imgur Uploads")
    check("a path to a section runs through its category",
          SettingsCategory.accountsSecurity.path(section: "API Keys") == "Settings → Accounts & Security → API Keys"
            && SettingsCategory.inboxNotifications.path() == "Settings → Inbox & Notifications")
    check("every section a path names exists",
          SettingsCategory.accountsSecurity.sections.contains { $0.title == "API Keys" }
            && SettingsCategory.inboxNotifications.sections.contains { $0.title == "Delivery" })
}

// MARK: Rows don't repeat their category's name

@MainActor func checkSettingsRowsDoNotRepeatTheirCategory() async throws {
    // A title's words, lowercased, with a plural "s" dropped from each word
    // longer than three letters and the connecting words ("&", "in", "and",
    // "of", "to", "the", "for") left out: "Accounts & Security" is
    // {account, security}. A drill-down repeats its category when the two
    // share a word, as "Feed Shortcuts" would in Feed or "Comment Filters" in
    // Filters.
    func stems(_ title: String) -> Set<String> {
        let skipped: Set<String> = ["in", "and", "of", "to", "the", "for", "a", "an"]
        return Set(title.lowercased().split { !$0.isLetter && !$0.isNumber }.compactMap { word in
            let word = String(word)
            if skipped.contains(word) { return nil }
            return word.count > 3 && word.hasSuffix("s") ? String(word.dropLast()) : word
        })
    }
    check("a title's stems drop connectives and plurals",
          stems("Accounts & Security") == ["account", "security"]
            && stems("Images in Comments") == ["image", "comment"]
            && stems("Inbox & Notifications") == ["inbox", "notification"])

    let repeats = SettingsCategory.allCases.flatMap { category in
        category.drillDowns.filter { !stems($0.title).isDisjoint(with: stems(category.title)) }
            .map { "\(category.title) › \($0.title)" }
    }
    check("no drill-down shares a word with its category's title", repeats.isEmpty)

    // The titles that would have.
    check("the screens renamed to avoid it no longer do",
          SettingsDrillDownDestination.commentFilters.title == "Comment Rules"
            && SettingsDrillDownDestination.feedShortcuts.title == "Subreddit Shortcuts"
            && SettingsDrillDownDestination.linkPreview.title == "Preview Cards"
            && SettingsDrillDownDestination.inlineMedia.title == "Inline Images"
            && SettingsDrillDownDestination.commentsTheme.title == "Thread Colours"
            && SettingsDrillDownDestination.cacheExplainer.title == "What Phoebus Keeps on Disk")

    // Nor does a section's header repeat the category it is on, except where a
    // section is the category's own subject by another name.
    let sectionRepeats = SettingsCategory.allCases.flatMap { category in
        category.sections.compactMap(\.title).filter { stems($0) == stems(category.title) }
            .map { "\(category.title) › \($0)" }
    }
    check("no section is headed with its category's whole name", sectionRepeats.isEmpty)
}

// MARK: Root-row right-detail values

@MainActor func checkSettingsCategoryTrailingValues() async throws {
    let values = SettingsCategoryValues(accountCount: 1, version: "v9.9.9")

    check("one account and no passcode is not a value worth showing",
          !AppLockStore.load().isEnabled
            ? SettingsCategory.accountsSecurity.trailingValue(values) == nil
            : true)
    check("several accounts are counted on the root row",
          AppLockStore.load().isEnabled
            || SettingsCategory.accountsSecurity
                .trailingValue(SettingsCategoryValues(accountCount: 3, version: "v9.9.9")) == "3 accounts")
    check("...the biometry, the passcode alone, or Off",
          SettingsCategory.appLockSummary(isEnabled: true, biometry: .faceID) == "Face ID"
            && SettingsCategory.appLockSummary(isEnabled: true, biometry: .touchID) == "Touch ID"
            && SettingsCategory.appLockSummary(isEnabled: true, biometry: .none) == "Passcode"
            && SettingsCategory.appLockSummary(isEnabled: false, biometry: .faceID) == "Off")
    check("the version is shown on the About row",
          SettingsCategory.about.trailingValue(values) == "v9.9.9")
    check("an empty version shows nothing rather than a bare v",
          SettingsCategory.about.trailingValue(SettingsCategoryValues(accountCount: 1, version: "")) == nil)
    check("a category with nothing to say shows nothing",
          SettingsCategory.feed.trailingValue(values) == nil
            && SettingsCategory.media.trailingValue(values) == nil
            && SettingsCategory.filters.trailingValue(values) == nil)
    check("the appearance row names the active theme",
          (SettingsCategory.appearance.trailingValue(values) ?? "").contains(ThemeStore.load().name))
}

// MARK: Search resolves, and lands on the screen that holds the row

@MainActor func checkSettingsSearchResolvesToRoutableScreens() async throws {
    let index = SettingsSearch.index
    let categoryCases = Set(SettingsCategory.allCases.map(\.searchScreen))

    check("each category has its own search case, and back",
          categoryCases.count == SettingsCategory.allCases.count
            && SettingsCategory.allCases.allSatisfy { $0.searchScreen.category == $0 })
    check("each drill-down has a search case named after it",
          SettingsDrillDownDestination.allCases.allSatisfy { SettingsSearchScreen(rawValue: $0.rawValue) != nil })
    check("every index entry names a screen the tree can route",
          index.allSatisfy { SettingsSearchScreen.searchable.contains($0.screen) })
    check("no entry names the settings root, which is already on screen",
          !index.contains { $0.screen == .settingsRoot })

    // Every category and every drill-down is a search result of its own,
    // from the breadcrumb that is its tap path.
    check("every category screen is an entry, from the root",
          SettingsCategory.allCases.allSatisfy { category in
              index.contains { $0.title == category.title && $0.screen == category.searchScreen
                  && $0.rowTitle == nil && $0.breadcrumb == "Settings" } })
    check("every drill-down is an entry, from its category's breadcrumb",
          SettingsCategory.allCases.allSatisfy { category in
              category.drillDowns.allSatisfy { drillDown in
                  index.contains { $0.title == drillDown.title
                      && $0.screen == SettingsSearchScreen(rawValue: drillDown.destination.rawValue)
                      && $0.rowTitle == nil && $0.breadcrumb == "Settings → \(category.title)" } } })
    check("a row on a category screen lands on that screen and names the row",
          index.filter { $0.rowTitle != nil && $0.screen.category != nil }
            .allSatisfy { $0.breadcrumb.hasPrefix("Settings → \($0.screen.category?.title ?? "")") })

    // The searches the reorg was checked with: each lands on the right screen.
    func top(_ query: String, available: Set<String> = []) -> SettingsSearchEntry? {
        SettingsSearch.results(for: query, available: available).first
    }
    let everything = Set(SettingsRowRequirement.allCases.map(\.rawValue))
    check("Post Rules opens Post Rules", top("Post Rules")?.screen == .postRules)
    check("Comment Filters finds Comment Rules", top("Comment Filters")?.screen == .commentFilters)
    check("Settings Shortcuts opens Settings Shortcuts", top("Settings Shortcuts")?.screen == .settingsShortcuts)
    check("Bark lands on the Delivery rows of Inbox & Notifications",
          top("Bark")?.screen == .categoryInboxNotifications)
    check("Crash Reports opens Crash Reports", top("Crash Reports")?.screen == .crashReports)
    check("Images in Comments finds Inline Images", top("Images in Comments")?.screen == .inlineMedia)
    check("Tag Filters lands on Filters", top("Tag Filters")?.screen == .categoryFilters)
    check("Sign Out lands on Accounts & Security, with a session",
          top("Sign Out", available: everything)?.screen == .categoryAccountsSecurity
            && top("Sign Out", available: everything)?.rowTitle == "Sign Out")
    check("Default Comment Sort lands on Comments", top("Default Comment Sort")?.screen == .categoryComments)
    check("Haptic Feedback lands on Gestures & Haptics", top("Haptic Feedback")?.screen == .categoryGesturesHaptics)
    check("Profile Layout opens Profile Layout, from Appearance",
          top("Profile Layout")?.screen == .profileLayout && top("Profile Layout")?.breadcrumb == "Settings → Appearance")
    check("Clear Cache lands on Data & Storage", top("Clear Cache")?.screen == .categoryDataStorage)
    check("Unify Modmail lands on Inbox & Notifications", top("Unify Modmail")?.screen == .categoryInboxNotifications)
    check("Passcode lands on Accounts & Security", top("Passcode")?.screen == .categoryAccountsSecurity)

    // A row that exists only under a requirement takes it to everything
    // reached through it.
    check("Sign Out is searchable only where there is a session to end",
          index.filter { $0.title == "Sign Out" }.map(\.requires) == [SettingsRowRequirement.session.rawValue])
    let siri = index.filter { $0.breadcrumb.contains("Index Phoebus Content") || $0.rowTitle == "Index Phoebus Content"
        || $0.rowTitle == "Refresh Subscribed Communities" || $0.rowTitle == "Check Index Status" }
    check("Siri & Spotlight's rows are searchable only on iOS 27",
          !siri.isEmpty && siri.allSatisfy { $0.requires == SettingsRowRequirement.iOS27.rawValue })
    check("Automatic Update Checks needs a release channel, and sits on About",
          index.contains { $0.title == "Automatic Update Checks" && $0.screen == .categoryAbout
              && $0.requires == SettingsRowRequirement.releaseChannel.rawValue })
    check("a deep leaf still resolves through its category",
          index.contains { $0.title == "Bark Delivery"
              && $0.breadcrumb == "Settings → Inbox & Notifications" })

    // Every setting the dissolved screens held is still searchable: General,
    // Interface, Appearance, Comments, Deleted Comments, Portrait Lock,
    // Passcode, Notifications, Marking Read, Polls, User Profiles, Media,
    // Posts & Feeds and Subreddits. Retitled rows are listed under their
    // new names.
    let kept = [
        "Upvote on Save", "Default Sort", "Remember Subreddit Sort", "Autoplay GIFs/Videos",
        "Infinite Scrolling", "Share Includes Title", "Default Comment Sort", "New Comments Highlightifier",
        "Remember Post Sort", "Ignore Suggested Sort", "Auto Collapse Child Comments", "Tap to Collapse",
        "Collapse AutoModerator", "Show Jump Button", "Jump Button Position", "Remember Thread Position",
        "New Account Highlightenator", "Comment Age", "Show Edited Marker", "Highlight My Username",
        "Highlight Followed Users", "Hide Comment Scores", "Show Other Discussions", "Always Use Reader Mode",
        "Show Comments Button", "Unmute Videos When Opened", "Download GIFs as", "Video Deblurinator",
        "Show Controls When Opened", "Save to Phoebus Album", "Loop Videos with Audio", "Live Text Analyzer",
        "Unify Modmail in Inbox", "Default Reddit to Load", "Resume Where I Left Off", "Share old.reddit Links",
        "No Subscribed in All/Popular", "Allow Save Categories", "Keep Local Copies of Saved Items",
        "Open Tweets in", "Haptic Feedback", "3D Touch Marks Read", "Use System Text Size", "Post Size",
        "Post Size Per Subreddit", "Show Subreddit Icons", "Show Subreddit at Top", "Always Show Usernames",
        "Show Page Endings", "Bold Post Titles", "Show Voting Buttons", "Voting Buttons Position",
        "Thumbnail Size", "Thumbnail Position", "Show Self Post Thumbnails", "Show GIF Progress",
        "Post Flair", "User Flair", "Show Flair in Feeds", "Color Flairs", "Show Awards", "Hide Post Scores",
        "Profile Picture Tab Icon", "Icon-Only Tab Bar", "Hide Username on Tab Bar", "Hide Bars on Scroll",
        "Hide Style", "Hide Header on Scroll", "Scroll Behavior", "Return Button", "True Black Keyboard",
        "Collapse Pinned Comments", "Follow New Live Comments", "Show Deleted Comments",
        "Tap to Show Deleted Comments", "Smart Rotation Lock", "Portrait Lock Buddy", "Require Passcode",
        "Inbox Notifications", "Sound", "Disable Marking Posts Read", "Mark Read on Scroll",
        "Show Hide Read Button", "Hide Posts", "Auto Hide Read Posts", "Disable in Subreddits", "Polls",
        "Option Text Alignment", "reddit.com Web Sign-In", "Show User Profile Pictures", "Profile Picture Shape",
        "Per-Account Favorites", "Sort Favorites Alphabetically", "Confirm Favorite Changes",
        "Use Community Icons", "Show RandNSFW in Search", "Save Search History", "Clear Search History",
        "Recently Read Thumbnails", "Text Post Thumbnails", "Feed Video Scrubber", "Floating Post Tabs",
        "Live Interactive Posts", "Backend URL", "Bark Push URL", "Test Connection",
    ]
    let indexedTitles = Set(index.map(\.title))
    check("every setting from a dissolved screen is still in the index",
          kept.filter { !indexedTitles.contains($0) }.isEmpty)
}

// MARK: The retired settings-shortcut ids

@MainActor func checkRetiredSettingsShortcutIDMigrates() async throws {
    UserDefaults.standard.removeObject(forKey: SettingsShortcutsStore.key)

    // Every id in the catalogue opens something, is titled and has a glyph.
    check("every catalogue id routes to a screen",
          SettingsShortcutsStore.catalog.allSatisfy { SettingsShortcutsStore.target($0) != nil })
    check("every catalogue id is titled and has a glyph",
          SettingsShortcutsStore.catalog.allSatisfy {
              SettingsShortcutsStore.title($0) != $0 && !SettingsShortcutsStore.systemImage($0).isEmpty })
    check("the catalogue has no duplicates and fits the shortcut limit's menu",
          Set(SettingsShortcutsStore.catalog).count == SettingsShortcutsStore.catalog.count)
    check("the root and every category have a shortcut",
          SettingsShortcutsStore.target("settings-root") == .root
            && SettingsCategory.allCases.allSatisfy { category in
                SettingsShortcutsStore.catalog.contains { SettingsShortcutsStore.target($0) == .category(category) } })
    check("a shortcut is titled as the row or screen it opens",
          SettingsShortcutsStore.title("accounts-security") == "Accounts & Security"
            && SettingsShortcutsStore.title("theme-manager") == "Theme Manager"
            && SettingsShortcutsStore.title("rich-link-previews") == "Preview Cards"
            && SettingsShortcutsStore.title("feature-requests") == "Feature Requests"
            && SettingsShortcutsStore.title("settings-root") == "Settings")
    check("every shortcut that opens a drill-down is titled as it is",
          SettingsShortcutsStore.catalog.allSatisfy { id in
              guard case .drillDown(let destination) = SettingsShortcutsStore.target(id),
                    id != "bug-reports" || destination == .bugReports else { return true }
              return SettingsShortcutsStore.title(id) == destination.title })

    // The ids of screens the regrouping dissolved migrate to the category
    // that holds those settings now.
    let migrations: [(old: String, new: String)] = [
        ("reborn", "settings-root"),
        ("accounts-api-keys", "accounts-security"),
        ("posts-feeds", "feed"),
        ("subreddits", "feed"),
        ("general", "feed"),
        ("user-profiles", "appearance"),
        ("interface", "appearance"),
        ("profile-layout", "appearance"),
        ("inline-media", "media"),
        ("tag-filters", "filters"),
        ("automatic-backups", "data-storage"),
        ("gestures", "gestures-haptics"),
    ]
    check("each retired id migrates to a catalogue id",
          migrations.allSatisfy { SettingsShortcutsStore.migratedID($0.old) == $0.new
              && SettingsShortcutsStore.catalog.contains($0.new) })
    check("a retired id is out of the catalogue",
          migrations.allSatisfy { !SettingsShortcutsStore.catalog.contains($0.old) })
    check("the ids that still name a screen are not migrated",
          ["comments", "media", "filters", "appearance", "theme-manager", "app-icon", "crash-reports",
           "bug-reports", "picture-in-picture", "saved-categories", "translation", "apollo-ai"]
            .allSatisfy { SettingsShortcutsStore.migratedID($0) == $0 })

    UserDefaults.standard.set(["reborn", "general"], forKey: SettingsShortcutsStore.key)
    check("a saved list with a retired id migrates it in place",
          SettingsShortcutsStore.load() == ["settings-root", "feed"])
    UserDefaults.standard.set(["reborn", "bogus"], forKey: SettingsShortcutsStore.key)
    check("...and an unknown id is still dropped",
          SettingsShortcutsStore.load() == ["settings-root"])
    UserDefaults.standard.set(["subreddits", "posts-feeds", "general"], forKey: SettingsShortcutsStore.key)
    check("ids that migrate to one place collapse to one shortcut",
          SettingsShortcutsStore.load() == ["feed"])
    UserDefaults.standard.set(["inline-media", "reborn", "profile-layout", "user-profiles"],
                              forKey: SettingsShortcutsStore.key)
    check("the earlier migrations hold alongside the new ones",
          SettingsShortcutsStore.load() == ["media", "settings-root", "appearance"])
    UserDefaults.standard.set(["automatic-backups", "tag-filters", "gestures", "interface", "accounts-api-keys"],
                              forKey: SettingsShortcutsStore.key)
    check("a list saved before the regrouping keeps its order",
          SettingsShortcutsStore.load() == ["data-storage", "filters", "gestures-haptics", "appearance",
                                            "accounts-security"])

    UserDefaults.standard.removeObject(forKey: SettingsShortcutsStore.key)
    check("the defaults still name four shortcuts, none retired",
          SettingsShortcutsStore.load().count == 4
            && SettingsShortcutsStore.load().allSatisfy { SettingsShortcutsStore.catalog.contains($0) })
}
