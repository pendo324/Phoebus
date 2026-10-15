#!/usr/bin/env python3
"""Generate SettingsSearchIndexData.swift by crawling the settings screen
sources, so the index cannot drift from the screens.

Emits, for every screen reachable from the Settings root:
  - an entry for the screen itself (rowTitle nil), and
  - an entry per Toggle/Picker/labelled row it contains.

Breadcrumbs come from a BFS over the tree, so they are the real tap path
rather than a hand-maintained list.

The tree comes from PhoebusCore's `SettingsCategory`: the root links each
category, `SettingsCategoryScreen` (PhoebusUI) names the screen struct each
category opens, and a category's `sections` list the drill-downs it pushes,
which `SettingsDrillDownLeaf` routes to a screen struct each. Every other
link is found by the NavigationLink graph (a screen struct named in a
screen's source). A category screen draws its own switches and pickers, so
its rows are indexed on it, and searching one lands on the category and
flashes the row.

The generator also checks what it reads against Core: a category's screen
must push exactly the drill-downs its `sections` list, its section headers
(`Text("...").apolloSectionHeader()`) must be the titles Core lists, and a
drill-down's row title must be the pushed screen's navigation title. A
mismatch stops it, so the tree Core describes is the tree the screens draw.

A screen is found by its `struct` declaration anywhere under the UI
directory, and its title is the `.navigationTitle(...)` of that struct
(the outermost one, so a sheet's own title is not taken). Rows are read
from the file the screen is declared in, in source order, without the
bodies of other registered screens declared beside it, so a pushed detail
view that is not a registered screen contributes its rows to the screen
that pushes it. A screen also takes the rows of the section groups it
draws: structs named `...Section` or `...Sections` that its source
mentions, wherever they are declared. Comments are ignored, and so are rows
whose title is an interpolated string, since it has no fixed text to
search for.

A row can be adjusted with a `// search:` comment on its line or on the
line above, several directives separated by `;`:
  // search: skip              leave the row out of the index
  // search: requires <tag>    the row exists only while <tag> is available
                               (SettingsSearch.results(available:))
  // search: item "<Title>"    also index <Title> as a choice inside the
                               row (a menu item), landing on the row

Rows built in a loop (titles that aren't literals) are listed on a comment
line of their own, after the screen's other rows:
  // search: rows "<Title>", "<Title>"

Usage: gen-settings-search-index.py [--check] <PhoebusUI dir> <output.swift>

PhoebusCore is the directory next to <PhoebusUI dir>.

--check writes nothing and exits 1 if <output.swift> differs from what
would be generated.
"""

import difflib
import os
import re
import sys
from collections import deque

# Screen struct -> SettingsSearchScreen case, for the screens that are not
# read from Core: the root, and screens reached only through another
# screen's links. The category screens and their drill-downs come from Core
# and `SettingsDrillDownLeaf`.
SCREEN_CASES = {
    "SettingsScreen": "settingsRoot",
    "ThemeGalleryScreen": "themeGallery",
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


def core_constant(owner_name, member):
    """The string literal `static let member = "..."` in `enum owner_name`, or None."""
    for src in CORE_SOURCES.values():
        code, masked = strip_source(src)
        owner = re.search(r'\benum\s+' + owner_name + r'\b[^{]*\{', masked)
        if owner:
            body = code[owner.end():matching_brace(masked, owner.end() - 1)]
            value = re.search(r'\bstatic\s+let\s+' + member + r'\s*=\s*' + STRING, body)
            if value:
                return unescape(value.group(1))
    return None


def split_directives(text):
    """The directives in one `// search:` comment, split on `;` outside quotes."""
    parts, current, quoted = [], "", False
    for c in text:
        if c == '"':
            quoted = not quoted
        if c == ";" and not quoted:
            parts.append(current.strip())
            current = ""
        else:
            current += c
    parts.append(current.strip())
    return [p for p in parts if p]


def declaration_regions(code, masked, name):
    """(start, end) of the struct `name` and of every `extension name` in the file."""
    regions = []
    for pattern in (r'\bstruct\s+' + name + r'\b[^{]*\{', r'\bextension\s+' + name + r'\b[^{]*\{'):
        for m in re.finditer(pattern, masked):
            start = m.end() - 1
            regions.append((m.start(), matching_brace(masked, start) + 1))
    return regions


class Screen:
    """A settings screen: the struct, the file it is declared in, and its title.

    `chunks` are the (source, code) pairs its rows are read from: its own
    file and the files of the section groups it draws, each without the
    bodies of the other registered screens declared beside them."""

    def __init__(self, name, path, src, registered, groups=(), titled=True):
        self.name = name
        self.path = path
        self.src = src
        self.code, masked = strip_source(src)
        decl = re.search(r'\bstruct\s+' + name + r'\b[^{]*\{', masked)
        start = decl.end() - 1
        end = matching_brace(masked, start)
        self.title = self._title(masked, start, end) if titled else None
        self.chunks = [self._without_others(src, registered - {name})]
        # What the screen itself draws: its struct and its section groups'
        # structs, not the detail screens declared beside them.
        self.owned_code = self._struct_code(src, name)
        for group_name, group_src in groups:
            self.chunks.append(self._without_others(group_src, registered - {name}))
            self.owned_code += "\n" + self._struct_code(group_src, group_name)

    @staticmethod
    def _struct_code(src, name):
        code, masked = strip_source(src)
        return "\n".join(code[a:b] for a, b in declaration_regions(code, masked, name))

    @staticmethod
    def _without_others(src, others):
        code, masked = strip_source(src)
        for other in others:
            if re.search(r'\bstruct\s+' + other + r'\b', masked):
                for start, end in declaration_regions(code, masked, other):
                    code = blank(code, start, end)
                    masked = blank(masked, start, end)
                    src = blank(src, start, end)
        return src, code

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
        # A constant Core owns, shared with its smoke checks: `Type.member`.
        constant = re.fullmatch(r'([A-Z]\w*)\.(\w+)', arg)
        if constant:
            value = core_constant(constant.group(1), constant.group(2))
            if value is not None:
                return value
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
        # A row is usually declared by a control (`Toggle("Title")`) and
        # tagged by a later `.apolloSearchRow("Title")`, so directives from
        # every occurrence of a title apply to the row.
        found = {}
        loop_rows = []
        for src, code in self.chunks:
            lines = src.split("\n")
            line_starts = [0]
            for line in lines:
                line_starts.append(line_starts[-1] + len(line) + 1)

            def directives(offset):
                n = max(i for i, s in enumerate(line_starts[:-1]) if s <= offset)
                found_here = []
                m = DIRECTIVE_RE.search(lines[n])
                if m:
                    found_here += split_directives(m.group(1))
                if n > 0 and lines[n - 1].lstrip().startswith("//"):
                    m = DIRECTIVE_RE.search(lines[n - 1])
                    if m:
                        found_here += split_directives(m.group(1))
                return found_here

            for m in (m for regex in ROW_RES for m in regex.finditer(code)):
                raw = m.group(1)
                if "\\(" in raw:
                    continue
                found.setdefault(unescape(raw), []).extend(directives(m.start()))
            for line in lines:
                m = DIRECTIVE_RE.search(line)
                if m and line.lstrip().startswith("//") and m.group(1).startswith("rows "):
                    loop_rows += literal_strings(m.group(1)[len("rows "):])
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
        rows += [(t, None, []) for t in loop_rows if t not in found]
        return rows


def read_sources(directory):
    sources = {}
    for root, _, names in sorted(os.walk(directory)):
        for f in sorted(names):
            if f.endswith(".swift"):
                path = os.path.join(root, f)
                sources[path] = open(path).read()
    return sources


def declaring_file(sources, name):
    """The one file declaring `struct name`, or None."""
    pattern = re.compile(r'\bstruct\s+' + name + r'\b')
    found = [p for p, text in sources.items() if pattern.search(strip_source(text)[1])]
    if len(found) > 1:
        raise SystemExit(f"{name}: declared in more than one file: {', '.join(found)}")
    return found[0] if found else None


def declaration_body(sources, pattern, what):
    """(code, start, end) of the one `{...}` body opened by `pattern`."""
    regex = re.compile(pattern)
    for src in sources.values():
        code, masked = strip_source(src)
        m = regex.search(masked)
        if m:
            start = m.end() - 1
            return code, start, matching_brace(masked, start)
    raise SystemExit(f"cannot find {what}")


class Category:
    """A `SettingsCategory` case: its title and what its screen holds, read from Core."""

    def __init__(self, raw, title, sections):
        self.raw = raw
        self.title = title
        # [(title or None, requires or None, [drill-down destination], [cross-link])]
        self.sections = sections
        self.name = f"category:{raw}"
        self.case = "category" + raw[0].upper() + raw[1:]

    @property
    def drill_downs(self):
        return [d for _, _, drills, _ in self.sections for d in drills]

    @property
    def cross_links(self):
        return [c for _, _, _, links in self.sections for c in links]

    @property
    def header_titles(self):
        return {title for title, _, _, _ in self.sections if title}


def load_categories(core_dir):
    """The categories in root order, with their titles and sections."""
    sources = read_sources(core_dir)
    code, start, end = declaration_body(sources, r'\benum\s+SettingsCategory\b[^{]*\{', "enum SettingsCategory")
    masked = strip_source(code)[1]
    body = code[start:end]
    first_member = re.search(r'\b(?:public\s+)?(?:var|func|static)\b', body).start()
    order = re.findall(r'\bcase\s+(\w+)', body[:first_member])

    def switch_body(var):
        m = re.search(r'\bvar\s+' + var + r'\s*:[^{]*\{', body)
        if not m:
            raise SystemExit(f"SettingsCategory has no `{var}`")
        open_at = start + m.end() - 1
        return code[open_at:matching_brace(masked, open_at)]

    titles = dict(re.findall(r'case\s+\.(\w+):\s*return\s+' + STRING, switch_body("title")))
    sections, current = {}, None
    sections_code = switch_body("sections")
    for m in re.finditer(r'case\s+\.(\w+)\s*:|\.init\(|SettingsCategorySection\(', sections_code):
        if m.group(1):
            current = m.group(1)
            sections[current] = []
            continue
        args = call_argument(sections_code, m.end() - 1)
        first = args.split(",", 1)[0].strip()
        title = None if first == "nil" else unescape(re.fullmatch(STRING, first).group(1)) \
            if re.fullmatch(STRING, first) else "<dynamic>"
        requires = re.search(r'requires:\s*\.(\w+)', args)
        drills = re.search(r'drillDowns:\s*\[([^\]]*)\]', args)
        links = re.search(r'crossLinks:\s*\[([^\]]*)\]', args)
        sections[current].append((
            title, requires and requires.group(1),
            re.findall(r'\.(\w+)', drills.group(1)) if drills else [],
            re.findall(r'\.(\w+)', links.group(1)) if links else []))
    return [Category(raw, unescape(titles[raw]), [x for x in sections[raw] if x[0] != "<dynamic>"]) for raw in order]


def switch_map(sources, struct, what):
    """Case name -> screen struct, from `case .x: SomeScreen(...)` in `struct`'s body."""
    code, start, end = declaration_body(sources, r'\bstruct\s+' + struct + r'\b[^{]*\{', what)
    return dict(re.findall(r'case\s+\.(\w+):\s*([A-Za-z]+Screen)\b', code[start:end]))


def drill_down_titles(core_dir):
    """Destination case -> the row title Core gives it."""
    sources = read_sources(core_dir)
    code, start, end = declaration_body(
        sources, r'\benum\s+SettingsDrillDownDestination\b[^{]*\{', "enum SettingsDrillDownDestination")
    body = code[start:end]
    m = re.search(r'\bvar\s+title\s*:[^{]*\{', body)
    title_body = body[m.end() - 1:]
    titles = {case: unescape(t) for case, t in re.findall(r'case\s+\.(\w+):\s*return\s+' + STRING, title_body)}
    for case, owner, member in re.findall(r'case\s+\.(\w+):\s*return\s+([A-Z]\w*)\.(\w+)\b', title_body):
        value = core_constant(owner, member)
        if value is not None:
            titles[case] = value
    return titles


CORE_SOURCES = {}

def cross_link_targets(core_dir):
    """Cross-link case -> (category raw value, row title), from Core's `SettingsCrossLink`."""
    sources = read_sources(core_dir)
    code, start, end = declaration_body(sources, r'\benum\s+SettingsCrossLink\b[^{]*\{', "enum SettingsCrossLink")
    body = code[start:end]
    categories = dict(re.findall(r'case\s+\.(\w+):\s*return\s+\.(\w+)', body))
    rows = dict(re.findall(r'case\s+\.(\w+):\s*return\s+' + STRING, body))
    # `title` returns literals too; the row switch is the one whose values are categories' rows,
    # told apart by being the last `return "..."` switch.
    row_switch = body[body.index('var row'):]
    rows = {c: unescape(t) for c, t in re.findall(r'case\s+\.(\w+):\s*return\s+' + STRING, row_switch)}
    return {c: (categories[c], rows[c]) for c in rows}


SECTION_GROUP_RE = re.compile(r'\b([A-Z]\w*Sections?)\s*\(')
HEADER_RE = re.compile(r'Text\(\s*' + STRING + r'\s*\)\s*\.apolloSectionHeader\(')
CROSS_LINK_USE_RE = re.compile(r'SettingsCrossLinkRow\(\s*link:\s*\.(\w+)')
DRILL_DOWN_USE_RE = re.compile(r'SettingsDrillDown(?:Row|Leaf)\(\s*(?:destination:\s*)?\.(\w+)')


def generate(ui_dir):
    ui_sources = read_sources(ui_dir)
    core_dir = os.path.join(os.path.dirname(os.path.normpath(ui_dir)), "PhoebusCore")
    CORE_SOURCES.update(read_sources(core_dir))
    categories = load_categories(core_dir)
    leaves = switch_map(ui_sources, "SettingsDrillDownLeaf", "struct SettingsDrillDownLeaf")
    category_screens = switch_map(ui_sources, "SettingsCategoryScreen", "struct SettingsCategoryScreen")
    drill_titles = drill_down_titles(core_dir)

    # Every registered screen: struct -> SettingsSearchScreen case.
    cases = dict(SCREEN_CASES)
    for category in categories:
        cases[category_screens[category.raw]] = category.case
    for destination, struct in leaves.items():
        cases[struct] = destination
    registered = set(cases)

    def declare(name, titled=True):
        path = declaring_file(ui_sources, name)
        if not path:
            raise SystemExit(f"{name}: expected one declaration under {ui_dir}, found none")
        # The section groups it draws, wherever they are declared.
        groups, seen, queue = [], {name}, [Screen._struct_code(ui_sources[path], name)]
        while queue:
            code = queue.pop()
            for group in dict.fromkeys(SECTION_GROUP_RE.findall(code)):
                group_path = declaring_file(ui_sources, group)
                if group_path and group not in seen and group not in registered:
                    seen.add(group)
                    groups.append((group, ui_sources[group_path]))
                    queue.append(Screen._struct_code(ui_sources[group_path], group))
        # A section group declared beside a screen that does not draw it would
        # have its rows indexed on the wrong screen.
        code, masked = strip_source(ui_sources[path])
        drawn = {n for n, _ in groups}
        for beside in re.findall(r'\bstruct\s+(\w+Sections?)\b', masked):
            if beside not in drawn:
                raise SystemExit(f"{beside} is declared beside {name} but {name} does not draw it; "
                                 f"move it to a file of its own")
        return Screen(name, path, ui_sources[path], registered, groups, titled)

    screens = {}
    category_of = {}
    for category in categories:
        struct = category_screens[category.raw]
        screens[struct] = declare(struct, titled=False)
        category_of[struct] = category
    for struct in set(leaves.values()) | set(SCREEN_CASES):
        screens[struct] = declare(struct)

    titles = {}
    for struct, screen in screens.items():
        titles[struct] = category_of[struct].title if struct in category_of else screen.title

    # Core's tree against the screens that draw it.
    for category in categories:
        struct = category_screens[category.raw]
        screen = screens[struct]
        used = DRILL_DOWN_USE_RE.findall(screen.owned_code)
        if sorted(used) != sorted(category.drill_downs):
            raise SystemExit(f"{struct} pushes {sorted(used)} but SettingsCategory.{category.raw} lists "
                             f"{sorted(category.drill_downs)}")
        links = CROSS_LINK_USE_RE.findall(screen.owned_code)
        if sorted(links) != sorted(category.cross_links):
            raise SystemExit(f"{struct} links {sorted(links)} but SettingsCategory.{category.raw} lists "
                             f"{sorted(category.cross_links)}")
        headers = {unescape(h) for h in HEADER_RE.findall(screen.owned_code)}
        core_headers = category.header_titles
        if headers != core_headers:
            raise SystemExit(f"{struct}: section headers {sorted(headers - core_headers)} are not in "
                             f"SettingsCategory.{category.raw}; {sorted(core_headers - headers)} are not drawn")
    # A cross-link opens a category screen at a row that is on it.
    for link, (raw, row) in cross_link_targets(core_dir).items():
        target = next((c for c in categories if c.raw == raw), None)
        if target is None or row not in [r for r, _, _ in screens[category_screens[raw]].rows()]:
            raise SystemExit(f"SettingsCrossLink.{link} opens {raw} at \"{row}\", which is not a row on it")
    for destination, struct in leaves.items():
        if screens[struct].title != drill_titles[destination]:
            raise SystemExit(f"{struct} is titled \"{screens[struct].title}\" but "
                             f"SettingsDrillDownDestination.{destination} says \"{drill_titles[destination]}\"")

    # Edges: a category screen links its Core drill-downs; every other
    # screen links the registered screens its source names.
    links = {}
    for struct, screen in screens.items():
        if struct in category_of:
            links[struct] = [(leaves[d], None) for d in category_of[struct].drill_downs]
        else:
            named = [c for c in dict.fromkeys(LINK_RE.findall(screen.owned_code))
                     if c in screens and c != struct]
            links[struct] = [(c, None) for c in named]
    links["SettingsScreen"] = [(category_screens[c.raw], None) for c in categories]

    # BFS from the root. A screen reached through a row with a
    # requirement has it too.
    crumbs = {"SettingsScreen": []}
    requirement = {"SettingsScreen": None}
    order = []
    queue = deque(["SettingsScreen"])
    while queue:
        name = queue.popleft()
        if name in order:
            continue
        order.append(name)
        for child, requires in links[name]:
            if child not in crumbs:
                crumbs[child] = crumbs[name] + [titles[name]]
                requirement[child] = requires or requirement[name]
                queue.append(child)
    unreached = set(screens) - set(order)
    if unreached:
        raise SystemExit(f"not reachable from the root: {', '.join(sorted(unreached))}")

    entries = []
    seen = set()

    def add(title, crumb, case, row, requires=None):
        key = (title, crumb)
        if key in seen:
            return
        seen.add(key)
        entries.append((title, crumb, case, row, requires))

    # Pass 1: the screens themselves, except the root.
    #
    # Before the rows: a screen and the parent row that opens it share a
    # title ("Translation"), and the screen entry is the better result
    # because it pushes, where the row entry only scrolls and flashes.
    for name in order:
        if name != "SettingsScreen":
            add(titles[name], " → ".join(crumbs[name]) or "Settings", cases[name], None, requirement[name])

    # Pass 2: the rows on each screen.
    for name in order:
        case = cases[name]
        own_crumb = (" → ".join(crumbs[name] + [titles[name]])
                     if name != "SettingsScreen" else "Settings")
        for row, requires, items in screens[name].rows():
            requires = requires or requirement[name]
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
