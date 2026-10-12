#!/usr/bin/env python3
"""Generate SettingsSearchIndexData.swift by crawling the settings screen
sources, so the index cannot drift from the screens.

Emits, for every screen reachable from the Settings root:
  - an entry for the screen itself (rowTitle nil), and
  - an entry per Toggle/Picker/labelled row it contains.

Breadcrumbs come from a BFS over the NavigationLink graph, so they are
the real tap path rather than a hand-maintained list.

A screen is found by its `struct` declaration anywhere under the UI
directory, and its title is the `.navigationTitle(...)` of that struct
(the outermost one, so a sheet's own title is not taken). Rows are read
from the whole file the screen is declared in, in source order, so
screens declared next to the screen (pushed detail views) contribute
their rows too. Comments are ignored, and so are rows whose title is an
interpolated string, since it has no fixed text to search for.

A row can be adjusted with a `// search:` comment on its line or on the
line above:
  // search: skip              leave the row out of the index
  // search: requires <tag>    the row exists only while <tag> is available
                               (SettingsSearch.results(available:))
  // search: item "<Title>"    also index <Title> as a choice inside the
                               row (a menu item), landing on the row

Rows built in a loop (titles that aren't literals) are listed on a comment
line of their own, after the screen's other rows:
  // search: rows "<Title>", "<Title>"

Usage: gen-settings-search-index.py [--check] <PhoebusUI dir> <output.swift>

--check writes nothing and exits 1 if <output.swift> differs from what
would be generated.
"""

import difflib
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
    "DeletedCommentsSettingsScreen": "deletedComments",
    "ExternalBrowserSettingsScreen": "externalBrowser",
    "OpenInAppSettingsScreen": "openInApp",
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
    "TextSizesAndFontsScreen": "textSizes",
    "UserProfilesSettingsScreen": "userProfiles",
    "SiriSpotlightSettingsScreen": "siriSpotlight",
}

STRING = r'"((?:[^"\\]|\\.)*)"'
# In the order rows are emitted: all matches of the first pattern, then the
# second, and so on, each in source order. The committed index has always
# had this shape, so it is kept for stable diffs.
ROW_RES = [re.compile(p) for p in [
    r'Toggle\(\s*' + STRING,
    # Also matches ApolloSettingsPicker(.
    r'Picker\(\s*' + STRING,
    r'SettingsIconRow\(title:\s*' + STRING,
    r'LabeledContent\(\s*' + STRING,
    # A NavigationLink whose label is a plain title string (the patterns
    # above all match controls).
    r'NavigationLink\(\s*' + STRING,
    # An explicit search target, `.apolloSearchRow("Title")` (with or
    # without `lastBeforeFooter:`), also the scroll-and-flash anchor
    # Settings Search lands on. Rows declared that way (buttons, text
    # fields, composed labels) match no pattern above.
    r'\.apolloSearchRow\(\s*' + STRING,
    r'SettingsSearchRowModifier\(title:\s*' + STRING,
]]
DIRECTIVE_RE = re.compile(r'//\s*search:\s*(.*?)\s*$')
# A destination is either `SomeScreen(...)` or `SomeScreen { ... }`
# (trailing closure); screens that take only a trailing-closure handler
# have no paren.
LINK_RE = re.compile(r'\b([A-Za-z]+Screen)\s*[({]')
NAV_TITLE_RE = re.compile(r'\.navigationTitle\(')


def swift_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def unescape(s):
    return s.replace('\\"', '"').replace("\\\\", "\\")


def blank(text, start, end):
    """Replace everything but newlines in text[start:end] with spaces."""
    return text[:start] + re.sub(r"[^\n]", " ", text[start:end]) + text[end:]


def strip_source(src):
    """(code, masked): `code` is the source with comments blanked;
    `masked` also has string contents blanked, so braces can be matched.
    Positions are preserved in both."""
    code = masked = src
    i, n = 0, len(src)
    while i < n:
        if src.startswith("//", i):
            j = src.find("\n", i)
            j = n if j < 0 else j
            code, masked = blank(code, i, j), blank(masked, i, j)
            i = j
        elif src.startswith("/*", i):
            j = src.find("*/", i + 2)
            j = n if j < 0 else j + 2
            code, masked = blank(code, i, j), blank(masked, i, j)
            i = j
        elif src.startswith('"""', i):
            j = src.find('"""', i + 3)
            j = n if j < 0 else j + 3
            masked = blank(masked, i + 3, j - 3)
            i = j
        elif src[i] == '"':
            j = i + 1
            while j < n and src[j] != '"' and src[j] != "\n":
                j += 2 if src[j] == "\\" else 1
            masked = blank(masked, i + 1, j)
            i = j + 1
        else:
            i += 1
    return code, masked


def matching_brace(masked, open_at):
    depth = 0
    for i in range(open_at, len(masked)):
        if masked[i] == "{":
            depth += 1
        elif masked[i] == "}":
            depth -= 1
            if depth == 0:
                return i
    raise ValueError("unbalanced braces")


def call_argument(code, open_paren):
    """The text between the parentheses opening at `open_paren`."""
    depth = 0
    i = open_paren
    while i < len(code):
        c = code[i]
        if c == '"':
            m = re.compile(STRING).match(code, i)
            i = m.end()
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return code[open_paren + 1:i]
        i += 1
    raise ValueError("unbalanced parentheses")


def literal_strings(text):
    return [unescape(m.group(1)) for m in re.finditer(STRING, text)]


class Screen:
    """A settings screen: the struct, the file it is declared in, and its title."""

    def __init__(self, name, path, src):
        self.name = name
        self.path = path
        self.src = src
        self.code, masked = strip_source(src)
        decl = re.search(r'\bstruct\s+' + name + r'\b[^{]*\{', masked)
        start = decl.end() - 1
        end = matching_brace(masked, start)
        self.title = self._title(masked, start, end)

    def _title(self, masked, start, end):
        # The outermost navigationTitle: a sheet's own title sits deeper
        # in the braces than the screen's.
        best = None
        for m in NAV_TITLE_RE.finditer(masked, start, end):
            depth = masked.count("{", start, m.start()) - masked.count("}", start, m.start())
            if best is None or depth < best[0]:
                best = (depth, m.end() - 1)
        if best is None:
            raise SystemExit(f"{self.name}: no .navigationTitle in the struct")
        arg = call_argument(self.code, best[1]).strip()
        # A plain literal, a ternary (its last string is the default), or
        # the name of a computed property whose first `return` is the title.
        if re.fullmatch(r'[A-Za-z_]\w*', arg):
            prop = re.search(r'\bvar\s+' + arg + r'\s*:\s*String\s*\{', masked[start:end])
            if prop:
                body_start = start + prop.end() - 1
                body = self.code[body_start:matching_brace(masked, body_start)]
                strings = re.findall(r'\breturn\s+' + STRING, body)
                if strings:
                    return unescape(strings[0])
        else:
            strings = literal_strings(arg)
            if strings and "\\(" not in strings[-1]:
                return strings[-1]
        raise SystemExit(f"{self.name}: cannot resolve the navigationTitle ({arg})")

    def rows(self):
        """[(title, requires, [items])], in ROW_RES order."""
        lines = self.src.split("\n")
        line_starts = [0]
        for line in lines:
            line_starts.append(line_starts[-1] + len(line) + 1)

        def directives(offset):
            n = max(i for i, s in enumerate(line_starts[:-1]) if s <= offset)
            found = []
            m = DIRECTIVE_RE.search(lines[n])
            if m:
                found.append(m.group(1))
            if n > 0 and lines[n - 1].lstrip().startswith("//"):
                m = DIRECTIVE_RE.search(lines[n - 1])
                if m:
                    found.append(m.group(1))
            return found

        # A row is usually declared by a control (`Toggle("Title")`) and
        # tagged by a later `.apolloSearchRow("Title")`, so directives from
        # every occurrence of a title apply to the row.
        found = {}
        for m in (m for regex in ROW_RES for m in regex.finditer(self.code)):
            raw = m.group(1)
            if "\\(" in raw:
                continue
            found.setdefault(unescape(raw), []).extend(directives(m.start()))
        rows = []
        for title, found_directives in found.items():
            requires, items, skip = None, [], False
            for d in found_directives:
                if d == "skip":
                    skip = True
                elif d.startswith("requires "):
                    requires = d[len("requires "):].strip()
                elif d.startswith("item "):
                    items += [i for i in literal_strings(d[len("item "):]) if i not in items]
                else:
                    raise SystemExit(f"{self.path}: unknown search directive: {d}")
            if not skip:
                rows.append((title, requires, items))
        for line in lines:
            m = DIRECTIVE_RE.search(line)
            if m and line.lstrip().startswith("//") and m.group(1).startswith("rows "):
                rows += [(t, None, []) for t in literal_strings(m.group(1)[len("rows "):])
                         if t not in found]
        return rows


def load_screens(ui_dir):
    sources = {}
    for root, _, names in sorted(os.walk(ui_dir)):
        for f in sorted(names):
            if f.endswith(".swift"):
                path = os.path.join(root, f)
                sources[path] = open(path).read()
    screens = {}
    for name in SCREEN_CASES:
        pattern = re.compile(r'\bstruct\s+' + name + r'\b')
        found = [p for p, s in sources.items() if pattern.search(strip_source(s)[1])]
        if len(found) != 1:
            raise SystemExit(f"{name}: expected one declaration under {ui_dir}, found {len(found)}")
        screens[name] = Screen(name, found[0], sources[found[0]])
    return screens


def generate(ui_dir):
    files = load_screens(ui_dir)
    titles = {name: screen.title for name, screen in files.items()}

    # BFS from the root over NavigationLink destinations.
    crumbs = {"SettingsScreen": []}
    order = []
    queue = deque(["SettingsScreen"])
    while queue:
        name = queue.popleft()
        if name in order:
            continue
        order.append(name)
        for child in dict.fromkeys(LINK_RE.findall(files[name].code)):
            if child in files and child not in crumbs and child != name:
                crumbs[child] = crumbs[name] + [titles[name]]
                queue.append(child)

    entries = []
    seen = set()

    def add(title, crumb, case, row, requires=None):
        key = (title, crumb)
        if key in seen:
            return
        seen.add(key)
        entries.append((title, crumb, case, row, requires))

    # Pass 1: the screens themselves.
    #
    # Before the rows: a screen and the parent row that opens it share a
    # title ("Translation"), and the screen entry is the better result
    # because it pushes, where the row entry only scrolls and flashes.
    for name in order:
        if name != "SettingsScreen":
            add(titles[name], " → ".join(crumbs[name]) or "Settings", SCREEN_CASES[name], None)

    # Pass 2: the rows on each screen.
    for name in order:
        case = SCREEN_CASES[name]
        own_crumb = (" → ".join(crumbs[name] + [titles[name]])
                     if name != "SettingsScreen" else "Settings")
        for row, requires, items in files[name].rows():
            add(row, own_crumb, case, row, requires)
            for item in items:
                add(item, f"{own_crumb} → {row}", case, row, requires)

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
    for title, crumb, case, row, requires in entries:
        row_arg = f", rowTitle: {swift_str(row)}" if row else ""
        requires_arg = f", requires: {swift_str(requires)}" if requires else ""
        lines.append(
            f"        SettingsSearchEntry(title: {swift_str(title)}, "
            f"breadcrumb: {swift_str(crumb)}, screen: .{case}{row_arg}{requires_arg}),"
        )
    lines += ["    ]", "}", ""]
    return "\n".join(lines), len(entries)


def main(argv):
    check = "--check" in argv
    args = [a for a in argv if a != "--check"]
    if len(args) != 2:
        raise SystemExit(__doc__)
    ui_dir, out_path = args
    text, count = generate(ui_dir)
    if check:
        current = open(out_path).read() if os.path.exists(out_path) else ""
        if current == text:
            print(f"{out_path} is up to date ({count} entries)")
            return 0
        diff = difflib.unified_diff(current.splitlines(), text.splitlines(),
                                    "committed", "generated", lineterm="", n=0)
        print("\n".join(list(diff)[:40]))
        print(f"{out_path} is stale; regenerate it with:\n"
              f"  python3 {sys.argv[0]} {ui_dir} {out_path}", file=sys.stderr)
        return 1
    open(out_path, "w").write(text)
    print(f"{count} entries -> {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
