# Conventions

## Code and comments

- **Comments are short.** They say *which Apollo / Apollo Reborn
  feature this is* and *why*, where that isn't obvious. Keep:
  - the feature name and its settings key, e.g.
    `// Reborn "Hide Header on Scroll" (HideTopBarOnScroll).`
  - Reborn issue numbers for behaviour that matches an upstream fix
    (`#1153`)
  - non-obvious UIKit/SwiftUI workarounds, private-API levers and their
    gates, ordering or concurrency rules, in one to three lines
  - measured constants as one trailing note (`// 52pt stock row`)
- **Keep out of source:** file/line citations into other projects,
  screenshot filenames and pixel arithmetic, and fix history ("tried X
  first", earlier attempts). Put that kind of context in the commit
  message.
- **Do not invent constants when a real one exists.** When you must add
  something Apollo never had, say so in one line.
- **Pure logic goes in `PhoebusCore`** so it is smoke-testable. UI types
  are thin shells.
- **Settings: `@Setting` in views, `update` for writes.** No `@State`
  copies of stored settings, no whole-value saves from the UI. See
  [components.md](components.md), "How settings work".
- Use Apollo's `UserDefaults` keys verbatim where a setting exists in
  Apollo, so backups import.
- Add `.accessibilityIdentifier("area.thing")` to new interactive
  controls, and `.accessibilityLabel` to icon-only buttons.
- No leftover `NSLog` debugging. Grep for `APOLLO_` before committing.
- Swift 6 language mode. Main-actor isolation errors sometimes need
  workarounds like setting a delegate in `init()`; see
  `ApolloSwipeRecognizerDelegate`.

## Minimum iOS: 17

The deployment target is iOS 17 (`Package.swift` sets `.iOS("17.0")`),
so the compiler rejects any newer API used without a guard. iOS gives
an app the iOS 26 design only when its binary records the iOS 26 SDK,
and the Linux toolchain records the deployment target there instead,
so `Package.swift` also passes the linker `-platform_version <platform>
17.0 26.0`. The platform name comes from `PHOEBUS_LINK_PLATFORM`
(`ios` by default, `ios-simulator` from `scripts/build-for-simulator.sh`).

- Any API newer than iOS 17 goes behind `#available` or a helper in
  `Shared/Utilities/Compatibility.swift` (the `*IfAvailable` shims live there
  and nowhere else).
- `Package.swift` links with `-weak_framework SwiftUICore` (plus
  `-client_name SwiftUI`, which the SDK's allowable-clients list
  requires) and `-flat_namespace`. SwiftUICore only exists on iOS 18+:
  without the weak link the app fails to launch on iOS 17, and without
  the flat namespace, symbols from the iOS 26 SDK files under SwiftUICore
  (Layout defaults, HStack/VStack witnesses) are not found in iOS 17's
  SwiftUI and the first custom `Layout` crashes.
- iOS 17 SwiftUI pitfall: reading `@Environment(\.dismiss)` in a large
  screen's body re-renders every feed row forever (100% CPU). Read
  `dismiss` in a small leaf view instead.

## Smoke assertions

- One `check("human-readable name", condition)` per fact.
- Checks call code and assert on the result. They never read source
  files as text, because that pins wording instead of behaviour. If
  logic worth testing lives in `PhoebusUI`, move it into `PhoebusCore` so
  it can be called; SwiftUI layout is checked by running the app.
- Test fixtures (`Tests/Fixtures`, `SafariExtension/Tests`) and shipped
  assets may be read.
- When an assertion fails because behaviour legitimately changed,
  update it with a one-line reason. Never delete a failing assertion to
  make the suite pass.
- Add an assertion for any constant you change.

## Commits

- Imperative subject of at most 72 characters, optionally prefixed with
  the area ("Gallery viewer: ..."), then a blank line and a short body
  when the change needs explaining.
- Describe the feature or behaviour, not the debugging history.
- Keep a version bump (`Config/Phoebus/Info.plist`) in its own commit
  (`Bump version to X.Y.Z/N`).
- Stage explicit paths rather than `git add -A`.
