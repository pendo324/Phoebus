#!/usr/bin/env python3
"""Enforce Apollo's segmented-control rule across the UI tree.

Apollo and Apollo Reborn only use segmented controls with two or three
options (e.g. Light / Dark, Posts / Comments, Uniques / Views,
Text / Link / Media). Choices with more options are value rows that open
a picker. A segmented control with four or more options doesn't fit the
design, so this check fails on one.

Usage:  python3 scripts/generate/check-segmented-controls.py
Exit 1 if any segmented control exceeds the maximum.
"""
import re
import sys
import pathlib

# Apollo's real maximum. postTypeSegmentedControl is Text/Link/Media.
REAL_MAX_OPTIONS = 3

# Enum case counts for the enums that drive our segmented controls.
# Resolved from source so the check reflects what actually renders,
# not a hand-maintained number.
def enum_case_count(root: pathlib.Path, name: str):
    for path in root.rglob("*.swift"):
        text = path.read_text(encoding="utf8", errors="ignore")
        match = re.search(
            r"enum\s+" + re.escape(name) + r"\b[^{]*\{(.*?)\n\}",
            text,
            re.S,
        )
        if not match:
            continue
        body = match.group(1)
        # Stop at the first nested decl so we only count the enum's own cases.
        body = body.split("\n    func ")[0].split("\n    var ")[0]
        cases = re.findall(r"^\s*case\s+([A-Za-z_][\w, =\"]*)", body, re.M)
        total = 0
        for entry in cases:
            total += len([c for c in entry.split(",") if c.strip()])
        if total:
            return total
    return None


def main() -> int:
    root = pathlib.Path(__file__).resolve().parent.parent.parent / "Sources"
    if not root.exists():
        print(f"no Sources directory at {root}")
        return 1

    failures = []
    found = 0
    for path in sorted(root.rglob("*.swift")):
        text = path.read_text(encoding="utf8", errors="ignore")
        # Scan BACKWARDS from each `.pickerStyle(.segmented)` to its
        # nearest preceding `Picker(`. A forward scan with a bounded
        # window silently swallows an intervening picker: the window
        # opened at picker A can run past picker B and reach B's
        # `.segmented`, so B gets attributed to A and is never checked.
        for style in re.finditer(r"pickerStyle\(\.segmented\)", text):
            # Match ANY `Picker(` form, not just one with a literal
            # title: `Picker(selection:)` and helper-built pickers exist
            # too, and a guard must not silently skip a form it does not
            # recognise.
            opener = None
            for candidate in re.finditer(r'Picker\(\s*(?:"([^"]*)")?', text[: style.start()]):
                opener = candidate
            if opener is None:
                continue
            found += 1
            block = text[opener.start() : style.end()]
            title = opener.group(1) or "<non-literal title>"
            tags = len(re.findall(r"\.tag\(", block))
            options = tags
            source = "literal tags"
            for_each = re.search(r"ForEach\(\[?([A-Za-z_]\w*)", block)
            if for_each and tags <= 1:
                name = for_each.group(1)
                count = enum_case_count(root, name)
                if count:
                    options, source = count, f"enum {name}"
                    # A `.filter { ... }` on the ForEach means some cases are
                    # conditionally hidden, so the enum's case count
                    # overstates what renders (compose hides "Poll" unless
                    # Reborn's Polls feature is on). Report the conditional
                    # so it is reviewed.
                    hidden = len(re.findall(r"\$0\s*!=\s*\.(\w+)", block))
                    if hidden:
                        options -= hidden
                        source += f", {hidden} conditionally hidden"
            # A ForEach over a FUNCTION CALL or a stored collection
            # (`ForEach(actions(for: screen))`) has no enum to count, so
            # the option count is unknown. Unknown must not read as fine.
            if options <= 1 and for_each:
                failures.append(
                    f"{path.relative_to(root)}: Picker(\"{title}\") is "
                    f"segmented over `{for_each.group(1)}`, whose option "
                    f"count could not be resolved. Confirm it has at most "
                    f"{REAL_MAX_OPTIONS} options or use a menu."
                )
                continue

            if options > REAL_MAX_OPTIONS:
                failures.append(
                    f"{path.relative_to(root)}: Picker(\"{title}\") has "
                    f"{options} options ({source}); Apollo's real maximum is "
                    f"{REAL_MAX_OPTIONS}. Use a menu or a value row."
                )

    print(f"checked {found} segmented control(s)")
    for failure in failures:
        print(f"  FAIL {failure}")
    if failures:
        return 1
    print("all within Apollo's real segmented-control shape")
    return 0


if __name__ == "__main__":
    sys.exit(main())
