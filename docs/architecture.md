# Architecture

## Targets (`Package.swift`)

| Target | Depends on | Builds on a Linux host? | Contents |
|---|---|---|---|
| `PhoebusCore` | Foundation only | Yes | Models, networking (`RedditAPIClient`, `RedditAuthClient`, `RedditRepository` and the per-service clients), settings stores, theming, pure policy enums. **All testable logic goes here.** |
| `PhoebusUI` | PhoebusCore, AnimatedImage (vendored) and KSCrash's `Recording` product (SwiftPM, pinned by revision) | No (needs SwiftUI/UIKit) | Every screen, component, media view and gesture recognizer. |
| `Phoebus` | PhoebusCore, PhoebusUI | No | `PhoebusApp.swift` (`@main`, `MainTabView`, the five root `NavigationStack`s, deep links) and `AppIntents.swift`. |
| `PhoebusWidget` | PhoebusCore | No | WidgetKit extension: App Intents, a Live Activity, and the calendar, photo, headline, post, feed and shortcuts widgets. Configurable widgets need `Metadata.appintents`, which only a macOS toolchain can generate (see [widgets-and-signing.md](widgets-and-signing.md)). |
| `PhoebusOpenIn` | none | No | Share sheet "Open in Apollo" action extension. |
| `PhoebusSafari` | none | No | Safari web extension handler (`SafariExtension/` holds the JavaScript). |
| `PhoebusCoreSmokeTest` | PhoebusCore | **Yes: this is the test suite** | `main.swift` (harness, shared fixtures, and the calls in order) plus `Checks/<Area>.swift`. |

Rule: if logic can be expressed without UIKit (a threshold, a gate, a
parser, a layout constant), put it in `PhoebusCore` so the smoke suite
can assert it. `PhoebusUI` should be a thin shell over `PhoebusCore`
policies. Example: `PushPopGesturePolicy` (Core) vs
`ApolloSwipePanRecognizer` (UI).

## Directory map

```
Sources/
  PhoebusCore/      Foundation-only logic, grouped by feature; large features have
                    sub-feature folders, e.g. Feed/Listing, Feed/Filters, Media/Video
    API/            Reddit models, the API client and RedditRepository
    Accounts/ Feed/ Posts/ Comments/ Media/ Links/ Inbox/ Subreddits/ Profile/
    Moderation/ Search/ Navigation/ Notifications/ Settings/ Backup/ Theming/
    Icons/ AI/ Translation/ Widgets/ Markdown/ Crash/
    Support/        General utilities: KeychainItem, LockedCache, LossyArray, formatting
    Resources/      RealAchievements.json, SubredditCapitalization.json
  PhoebusUI/        Screens and views, grouped by the same features (Feed/FeedView,
                    Feed/Rows, Posts/PostDetail, Media/Viewer, Settings/General...)
    Shared/         The design system and helpers: Chrome, Style, Layout, UIKit, Utilities
    Navigation/     Page swipes, row swipes, tab bar, navigation bar
    Resources/      BadgeBook/, LiquidGlassIcons/ (rendered at build time), StockIcons/
  Phoebus/          PhoebusApp.swift, AppIntents.swift
  PhoebusWidget/, PhoebusOpenIn/, PhoebusSafari/
  PhoebusCoreSmokeTest/main.swift, Checks/*.swift
Config/            Per-target Info.plist, entitlements and AppIntentsProtocols.json
Icons/             Standard/ and LiquidGlass/ alternate-icon PNGs, listed one by one in xtool.yml
SafariExtension/   Web extension resources and their JavaScript tests
Tests/Fixtures/    JSON fixtures read by the smoke tests
scripts/           build-for-simulator.sh, smoke.sh, xtool-env.sh, generate-icons.sh, code-unchanged.py
scripts/generate/  Python generators and audit helpers, and the icon tooling
Config/Phoebus/Info.plist  Version lives here (CFBundleShortVersionString / CFBundleVersion)
xtool.yml          Bundle id com.pendo324.Phoebus and the resources list
```

## App structure

- `PhoebusApp` shows `LoginScreen` or `MainTabView`.
- `MainTabView` is a native `TabView` with five root `NavigationStack`s
  (Subreddits/Feed, Inbox, Profile, Search, Settings). Each root stack
  gets `.apolloInteractiveSwipeNavigation()` and `.apolloForwardSwipe()`,
  which install the page-swipe pan recognizer (`PageSwipeController`)
  and turn off UIKit's own pop recognizers.
- Screens that push record the covered screen with
  `.apolloTracksForwardNavigation($binding)` so a forward swipe has a
  destination to re-push after a back swipe. Forgetting this on a new
  pushing screen makes the forward swipe silently do nothing there.
- Deep links (`DeepLinkDestination`, `PostLinkLoader`, etc.) live at
  the bottom of `PhoebusApp.swift`.

## Key singletons and stores

| Name | Where | Role |
|---|---|---|
| `AccountStore` / `CredentialStore` | Core/Accounts/Store | Multi-account auth. The keychain is unavailable in the iOS simulator (error -34018), so credentials fall back to container-local files there. |
| `RedditRepository` | Core/API/Repository | The facade screens call. |
| `NavigationGestureSettingsStore` | Core/Navigation/Gestures | `pushPopSwipeGesturesEnabled`, `disableRight/LeftSwipeGestureActions`, `longSwipeTriggerPoint`. Loaded fresh per gesture sample. |
| `PushPopGesturePolicy` | Core/Navigation/Gestures | Every gesture threshold. See [gestures.md](gestures.md). |
| `PageSwipeController` | UI/Navigation/PageSwipes | The back/forward page swipe, driving a real interactive `UINavigationController` transition. |
| `ForwardNavigationStore.shared` | UI/Navigation/PageSwipes | Forward stack (popped destinations to re-push). |
| `FloatingPostTabsManager` | UI/Feed/FloatingTabs | Apollo Reborn's floating post tabs. |
| `SharedFeedCache` | Core/Feed/Listing | App Group cache for widgets. |
| `ChatLive` / `ChatLiveSync` | UI/Inbox/Chat, Core/Inbox/Chat | The one long-poll Matrix sync while the app is open; the badge, Bark, chat list and rooms subscribe. |

## Settings pattern

Each settings group is a `Codable` struct plus a `...Store` enum whose
`storage` is a `SettingsStore` over `UserDefaults` (`Core/Settings/Store`);
the group lives with its feature, for example `Core/Feed/Layout/InfoRowSettings.swift`.
Views read and write through `@Setting` (see
[components.md](components.md), "How settings work"). Apollo's own
`UserDefaults` keys are used verbatim where a setting exists in Apollo,
so `ApolloBackupImport` can ingest real backups. After adding a row,
regenerate the search index with `scripts/generate/gen-settings-search-index.py`.

## Accessibility identifiers

Most interactive elements carry `.accessibilityIdentifier("area.thing")`
(for example `video.holdForSpeedIndicator`), which lets UI automation
find them. Add one to any new control you expect to drive from a test.
