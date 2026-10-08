#!/usr/bin/env python3
"""Generate SettingsSearchIndexData.swift by crawling the settings screen
sources, so the index cannot drift from the screens.

Emits, for every screen reachable from the Settings root:
  - an entry for the screen itself (rowTitle nil), and
  - an entry per Toggle/Picker/labelled row it contains.

Breadcrumbs come from a BFS over the NavigationLink graph, so they are
the real tap path rather than a hand-maintained list.

Usage: gen-settings-search-index.py <PhoebusUI dir> <output.swift>
"""

import os
import re
import sys
from collections import deque

# Screen file -> SettingsSearchScreen case. The root's own links are
# what seed the crawl.
SCREEN_CASES = {
    "SettingsScreen": "settingsRoot",
    "GeneralSettingsScreen": "general",
    "GestureSettingsScreen": "gestures",
    "FiltersSettingsScreen": "filters",
    "MarkReadSettingsScreen": "markRead",
    "AppIconSettingsScreen": "appIcon",
    "AppearanceSettingsScreen": "appearance",
    "ThemeSettingsScreen": "theme",
    "NotificationsSettingsScreen": "notifications",
    "SecuritySettingsScreen": "security",
    "PortraitLockSettingsScreen": "portraitLock",
    "ApolloRebornHubScreen": "apolloReborn",
    "SavedCategoriesSettingsScreen": "savedCategories",
    "TranslationSettingsScreen": "translation",
    "TagFiltersSettingsScreen": "tagFilters",
    "BackupRestoreSettingsScreen": "backupRestore",
    "CommentsSettingsScreen": "comments",
    "CommentsThemeSettingsScreen": "commentsTheme",
    "CustomAPISettingsScreen": "customAPI",
    "CustomSubredditSourceSettingsScreen": "customSubredditSource",
    "DeletedCommentsSettingsScreen": "deletedComments",
    "ExternalBrowserSettingsScreen": "externalBrowser",
    "OpenInAppSettingsScreen": "openInApp",
    "LinkCompanionScreen": "linkCompanion",
    "ThemeGalleryScreen": "themeGallery",
    "InfoRowSettingsScreen": "infoRow",
    "InlineMediaSettingsScreen": "inlineMedia",
    "InterfaceSettingsScreen": "interfaceSettings",
    "ActionMenusSettingsScreen": "actionMenus",
    "LinkPreviewSettingsScreen": "linkPreview",
    "MediaSettingsScreen": "media",
    "NotificationBackendSettingsScreen": "notificationBackend",
    "PictureInPictureSettingsScreen": "pictureInPicture",
    "PollsSettingsScreen": "polls",
    "PostFiltersSettingsScreen": "postFilters",
    "PostsFeedsSettingsScreen": "postsFeeds",
    "ProfileLayoutSettingsScreen": "profileLayout",
    "SubredditLayoutSettingsScreen": "subredditLayout",
    "SubredditSectionsSettingsScreen": "subredditSections",
    "SubredditsSettingsScreen": "subreddits",
    "ApolloAISettingsScreen": "apolloAI",
    "WallpapersSettingsScreen": "wallpapers",
    "AutomaticBackupSettingsScreen": "automaticBackup",
    "AccountsAPIKeysScreen": "accountsAPIKeys",
    "ClearTweakCachesScreen": "clearTweakCaches",
    "SiriSpotlightSettingsScreen": "siriSpotlight",
}

# Screen titles as the user sees them, taken from each file's
# navigationTitle.
TITLE_RE = re.compile(r'\.navigationTitle\("([^"]+)"\)')
ROW_RES = [
    re.compile(r'Toggle\(\s*"([^"]+)"'),
    re.compile(r'Picker\(\s*"([^"]+)"'),
    re.compile(r'SettingsIconRow\(title:\s*"([^"]+)"'),
    re.compile(r'LabeledContent\(\s*"([^"]+)"'),
    # A NavigationLink whose label is a plain title string (the patterns
    # above all match controls).
    re.compile(r'NavigationLink\(\s*"([^"]+)"'),
    # An explicit search target, `.apolloSearchRow("Title")`, also the
    # scroll-and-flash anchor Settings Search lands on. Rows declared that
    # way (buttons, text fields, composed labels) match no pattern above.
    re.compile(r'\.apolloSearchRow\(\s*"([^"]+)"'),
]
# A destination is either `SomeScreen(...)` or `SomeScreen { ... }`
# (trailing closure); screens that take only a trailing-closure handler
# have no paren.
LINK_RE = re.compile(r'\b([A-Za-z]+Screen)\s*[({]')


def swift_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main(ui_dir, out_path):
    # Screens live in feature folders, so they are found by file name.
    paths = {}
    for root, _, names in os.walk(ui_dir):
        for f in names:
            if f.endswith(".swift"):
                paths[f[:-len(".swift")]] = os.path.join(root, f)
    files = {}
    for name in SCREEN_CASES:
        if name in paths:
            files[name] = open(paths[name]).read()

    titles = {}
    for name, src in files.items():
        m = TITLE_RE.search(src)
        titles[name] = m.group(1) if m else name

    # BFS from the root over NavigationLink destinations.
    crumbs = {"SettingsScreen": []}
    order = []
    queue = deque(["SettingsScreen"])
    while queue:
        name = queue.popleft()
        if name in order:
            continue
        order.append(name)
        for child in dict.fromkeys(LINK_RE.findall(files.get(name, ""))):
            if child in files and child not in crumbs and child != name:
                crumbs[child] = crumbs[name] + [titles[name]]
                queue.append(child)

    entries = []
    seen = set()

    # Pass 1: the screens themselves.
    #
    # Before the rows: a screen and the parent row that opens it share a
    # title ("Translation"), and the screen entry is the better result
    # because it pushes, where the row entry only scrolls and flashes.
    for name in order:
        if name == "SettingsScreen":
            continue
        title = titles[name]
        crumb = " → ".join(crumbs[name]) or "Settings"
        key = (title, crumb)
        if key in seen:
            continue
        seen.add(key)
        entries.append((title, crumb, SCREEN_CASES[name], None))

    # Pass 2: the rows on each screen.
    for name in order:
        case = SCREEN_CASES[name]
        own_crumb = (" → ".join(crumbs[name] + [titles[name]])
                     if name != "SettingsScreen" else "Settings")
        rows = []
        for regex in ROW_RES:
            rows += regex.findall(files[name])
        for row in dict.fromkeys(rows):
            key = (row, own_crumb)
            if key in seen:
                continue
            seen.add(key)
            entries.append((row, own_crumb, case, row))

    lines = [
        "// GENERATED by scripts/generate/gen-settings-search-index.py - do not edit by hand.",
        "//",
        "// Crawled from the settings screen sources so the index cannot drift from",
        "// the screens.",
        "",
        "extension SettingsSearch {",
        "    /// Every searchable settings row, in tap order from the root.",
        "    public static let index: [SettingsSearchEntry] = [",
    ]
    for title, crumb, case, row in entries:
        row_arg = f", rowTitle: {swift_str(row)}" if row else ""
        lines.append(
            f"        SettingsSearchEntry(title: {swift_str(title)}, "
            f"breadcrumb: {swift_str(crumb)}, screen: .{case}{row_arg}),"
        )
    lines += ["    ]", "}", ""]
    open(out_path, "w").write("\n".join(lines))
    print(f"{len(entries)} entries -> {out_path}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
