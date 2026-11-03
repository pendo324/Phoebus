# Gestures

Phoebus aims for gesture-level parity with Apollo: page swipes, row
swipes, hold-and-drag scrubbing and the arbitration between them. This
area has the most moving parts in the app, so read this before touching
any of the files below.

## Files

| File | Owns |
|---|---|
| `Sources/PhoebusCore/Navigation/Gestures/PushPopGesturePolicy.swift` | Every threshold: `leftInset=70`, `rightInset=40`, `horizontalDominance=1.65`, `rowSwipeMinimumDistance=10`, `bottomSystemGestureInset=24`, `completionVelocity=100`, `completionFraction=0.5`, `scrollCommitDistance=10`, `scrollStartedDistance=4`. Pure functions `shouldBeginBack/Forward`, `rowSwipeShouldBegin`, `navigationClaimsTouch`, `navigationClaimsRowTouch`, `startedInBottomSystemGestureZone`, `shouldComplete`, `transitionProgress`, `verticallyCommitted`. Smoke-tested. |
| `Sources/PhoebusCore/Navigation/Gestures/NavigationGestureSettings.swift` | User toggles: `pushPopSwipeGesturesEnabled`, `disableRightSwipeGestureActions`, `disableLeftSwipeGestureActions`, `longSwipeTriggerPoint`. These are the Gestures settings screen's keys. |
| `Sources/PhoebusCore/Navigation/Swipes/SwipeCommitPolicy.swift` | Row-swipe thresholds: short action at 60pt, long action at `60 + 120 * fraction`. Pure, smoke-tested. |
| `Sources/PhoebusCore/Navigation/Swipes/SwipeRowPolicy.swift` | Which side a row drag belongs to, whether that side is on (Disable Left/Right Swipes, both slots None), and which action releasing it performs. The row asks it while revealing and on release. Pure, smoke-tested. |
| `Sources/PhoebusUI/Navigation/PageSwipes/PageSwipeNavigation.swift` | **Back and forward page swipes**: `PageSwipeController`, `PageSwipeInstaller`, `PageSwipeAnimator`, `PageSwipeInteraction`. |
| `Sources/PhoebusUI/Navigation/PageSwipes/UnsavedChangesGuard.swift` | `apolloConfirmsDiscard`: a screen's unsaved-changes flag, which holds a back page swipe and asks instead. |
| `Sources/PhoebusUI/Navigation/PageSwipes/ForwardNavigation.swift` | `ForwardNavigationStore` (the forward stack), `apolloForwardSwipe()`, `apolloTracksForwardNavigation()`. |
| `Sources/PhoebusUI/Navigation/PageSwipes/InteractiveSwipeNavigationModifier.swift` | `apolloInteractiveSwipeNavigation()` for the root stacks, and `UINavigationController.apolloDisableSystemPopGestures()`. |
| `Sources/PhoebusUI/Settings/Rows/SettingsNavigation.swift` | Path-driven navigation for the Settings tab: `SettingsNavigationModel`, `SettingsRoute`, `SettingsLink`, `settingsDestination(isPresented:)`. |
| `Sources/PhoebusUI/Shared/UIKit/ScrollGestureExclusivity.swift` | `ScrollGestureExclusivity` (is a scroll view scrolling under this touch?) and `ScrollLock` (switches scroll pans off while a swipe owns the touch). |
| `Sources/PhoebusUI/Navigation/TabBar/ScrollToTopRestore.swift` | **Status-bar tap**: `ScrollToTopDelegateProxy` (top, then back to where you were), `ScrollReturnStore` (the Return Button). |
| `Sources/PhoebusUI/Navigation/RowSwipes/SwipeActionsModifier.swift` | **Row swipe** (upvote/downvote/save/reply/hide on post and comment rows): `ApolloSwipePanRecognizer`, `ApolloSwipeRecognizerDelegate`, `AncestorAttachingView`, `SwipeGestureArbiter`, `ProgressiveSwipeRowModifier` (the revealed panel). |
| `Sources/PhoebusUI/Settings/Previews/GesturesPreview.swift` | The Gestures & Haptics preview: a sample row in `apolloConfinedSwipeActions` (below). Core `SwipePreviewPolicy` holds its strip, release label and segments. |
| `Sources/PhoebusUI/Shared/UIKit/AncestorGestureHost.swift` | Hosts a recognizer on an ancestor view; used by the two scrub gestures below. |
| `Sources/PhoebusUI/Feed/Gallery/GalleryImageViewerScreen.swift` | `GalleryVerticalSwipeCatcher`: swipe-to-dismiss and hold-and-drag video scrub in the gallery pager. |
| `Sources/PhoebusUI/Media/Video/MutedVideoPlayerView.swift` | `VideoScrubGestureCatcher`: hold-and-drag scrub in the fullscreen video player. |
| `Sources/PhoebusUI/Navigation/Orientation/QuickSwitchGesture.swift` | Long-press near the top of the screen to toggle the theme. |
| `Sources/PhoebusUI/Posts/PostDetail/DoubleTapUpvoteModifier.swift` | Double-tap media to upvote. |

## Page swipes (back and forward)

Apollo does not rely on UIKit's pop gesture; it has its own pan, gated
by:

```
back:    velocity.x > 0 && startX <= 70 && |vx/vy| >= 1.65
forward: velocity.x < 0 && startX >= width-40 && |vx/vy| >= 1.65
finish:  |translation| >= width/2  OR  |velocity| >= 100 pt/s
```

With "swipe anywhere" enabled (`disableLeftSwipeGestureActions` makes a
leftward swipe go back from anywhere, `disableRightSwipeGestureActions`
the same for forward) the start-zone test is skipped.

Phoebus implements this as a real interactive transition of the
`UINavigationController` under each `NavigationStack`
(`Navigation/PageSwipes/PageSwipeNavigation.swift`, `PageSwipeController`):

- One `UIPanGestureRecognizer` per navigation controller, installed by
  `.apolloForwardSwipe()` / `.apolloInteractiveSwipeNavigation()`
  (`PageSwipeInstaller`). `gestureRecognizerShouldBegin` applies
  `PushPopGesturePolicy`, the row-swipe arbiter, scroll exclusivity and
  slider checks, and picks the innermost stack under the finger.
  `cancelsTouchesInView` keeps a row or link under the finger from
  firing.
- Back calls `popViewController(animated: true)`. Forward calls
  `ForwardNavigationStore.goForward()`, whose SwiftUI binding/path
  restore pushes with animation. For the length of the swipe the
  controller stands in as the navigation controller's delegate
  (forwarding everything else to SwiftUI's) and returns
  `PageSwipeAnimator` (Apollo's slide: a full-width top page with a
  shadow, with 0.3 parallax underneath) and a
  `UIPercentDrivenInteractiveTransition` that buffers progress until
  UIKit starts the transition (asynchronously, for forward).
- Both screens are live views throughout and the navigation bar animates
  with UIKit. A cancelled forward push is reconciled by SwiftUI itself:
  the binding returns to nil, so the forward entry is re-recorded.
- A finger that rests for more than 0.1s before lifting ends with zero
  velocity, since the recognizer keeps reporting its last movement's.
- The drag must travel at least 40pt in its own direction to complete.
- The Reborn tab-bar swipe drives the same controller
  (`PageSwipeController.forVisibleStack`).
- UIKit's own pop recognizers stay disabled. iOS 26 added
  `interactiveContentPopGestureRecognizer`, which recognizes on the
  whole content area; leaving it enabled would contest every rightward
  row swipe, so `apolloDisableSystemPopGestures()` turns off both it and
  the classic edge recognizer.

### Over a horizontal scroller

A horizontal scroll view under the finger is "scrolling" the moment its pan
begins, which makes the page swipe refuse. The feed gallery
(`FeedGalleryPanYield`, `FeedGalleryPanPolicy`) and the Community Highlights
carousel (`CommunityHighlightsPanYield`, `CommunityHighlightsPanPolicy`) refuse
the pan themselves when a page swipe would take it, so the page follows the
finger: the carousel at its first card for Back and at its last for Forward,
with the same start-zone and angle rules as above. Anywhere in between it
scrolls, so one swipe returns to the first card and the next goes Back. The
gallery's scroll view is a `TabView`'s and can't be subclassed, so a gate
recognizer does it; the carousel's `DirectionalLockScrollView` overrides
`gestureRecognizerShouldBegin` instead.

### Unsaved changes

The page swipe pops the navigation controller itself, so a SwiftUI
dismiss confirmation never sees it. A screen with edits a pop would lose
marks itself with `.apolloConfirmsDiscard(isDirty:onAttempt:)`
(`PageSwipes/UnsavedChangesGuard.swift`), which puts a hidden
`UnsavedChangesProbe` view in the screen. When a back swipe begins,
`PageSwipeController` looks for a dirty probe under the top screen. If
there is one the page does not move, and a swipe that would have
completed (same distance and velocity test) calls the probe's
`onAttempt` on release, which shows the screen's own discard
confirmation. A swipe too short to complete does nothing. The tab bar's
swipe goes through the same `begin(back:)`. Forward swipes ignore the
probe. A second form, `.apolloConfirmsDiscard(isDirty:message:onDiscard:)`,
brings the standard "Discard Changes?" dialog, whose Discard runs
`onDiscard` and leaves the screen.

UIKit's own pop recognizers are disabled (above), so there is no
second path. The navigation bar's back button and a tab switch are not
guarded; a screen that wants the back button guarded replaces it with a
Cancel button that asks, as Edit Profile does. Sheets are not covered either: a
sheet that holds edits needs `interactiveDismissDisabled` and its own
confirmation.

### Settings tab

Plain `NavigationLink { dest }` pushes are invisible to the page swipes.
The Settings `NavigationStack` is therefore bound to
`SettingsNavigationModel.path` (`Settings/Rows/SettingsNavigation.swift`):
`SettingsLink` (a drop-in for `NavigationLink`) appends a
`SettingsRoute`, `settingsDestination(isPresented:)` replaces
`navigationDestination(isPresented:)`, and the single
`navigationDestination(for: SettingsRoute.self)` adds the swipes and
re-injects the model on every pushed screen. **New settings pushes must
use `SettingsLink`**.

A back-swipe drag whose start point lands on a toggle row can be taken
by the toggle; start on a plain row or header when testing.

## Row swipes

`ApolloSwipePanRecognizer` is a raw `UIGestureRecognizer` subclass that
tracks one touch itself. A `UIPanGestureRecognizer` asks
`gestureRecognizerShouldBegin` only once, so an ambiguous touch whose
horizontal intent shows up later never gets a second chance; this
recognizer re-evaluates on every sample instead.

`AncestorAttachingView` attaches it to the
`_UICollectionViewListCellContentView` ancestor, found by class name
while walking up to 12 hops (different screens wrap a row in different
numbers of views, so a fixed hop count misses some). It sets
`cancelsTouchesInView = false` and
`delaysTouchesBegan/Ended = false`, and recognizes simultaneously with
everything.

Per `touchesMoved` sample while `.possible`:

1. Track cumulative translation `t` and a two-point velocity `v`.
2. If `|t.y| >= 24` (`verticalDisqualifyDistance`), the touch is
   permanently disqualified: it is a scroll.
3. If an enclosing scroll view is scrolling under the finger
   (`ScrollGestureExclusivity.isAnyEnclosingScrollViewScrolling`), fail
   outright so the recognizer can never revive within that touch.
4. Otherwise `computeShouldBegin(t, v)` requires:
   - `|t.x| >= 10`
   - `PushPopGesturePolicy.rowSwipeShouldBegin` (translation or velocity
     decisively horizontal at 1.65)
   - the touch did not start in the bottom 24pt system-gesture strip
   - `!navigationClaimsRowTouch(...)`: directional, so a leftward drag in
     the left 70pt is not a back swipe and the row keeps it. It asks
     with velocity *and* translation (a slow edge drag has about zero
     two-point velocity), and only for a navigation that can actually
     happen (a screen to go back to, a forward entry to re-push), so the
     right 40pt is not a dead zone when there is no forward entry.
5. On pass, `state = .began`, `SwipeGestureArbiter.rowSwipeActive` is set,
   every enclosing scroll view is locked, and the SwiftUI side reveals
   the panel with the long-swipe and commit thresholds.

`.cancelled` still commits if the drag went far enough, because other
recognizers can cancel this one after a real swipe.

### Arbitration with page swipes and scrolling

- **Row vs page.** `SwipeGestureArbiter.rowSwipeActive` is set when a
  row swipe begins and cleared in `reset()`; the page swipe refuses to
  begin while it is set. The row swipe refuses to begin while a page
  swipe is active (`PageSwipeController.isActive`).
- **Scroll first.** A row swipe fails the moment any enclosing
  `UIScrollView` is scrolling (its pan began and content moved at least
  `scrollStartedDistance`, 4pt, along an axis it can scroll). The axis
  test matters: a vertical-only `List`'s pan can begin on a horizontal
  drag without scrolling anything. Page swipes are likewise refused once
  a touch is `verticallyCommitted` (at least 10pt down and not 1.65x
  horizontal) or a scroll view under it is scrolling.
- **Swipe first.** When a row swipe begins it disables the pan
  recognizers of every enclosing scroll view (`ScrollLock`), released in
  `reset()`. A page swipe locks every scroll view in the navigation
  controller's view for its duration. `ScrollLock` toggles
  `panGestureRecognizer.isEnabled`, not `isScrollEnabled`, because
  SwiftUI owns the latter on `List` and reasserts it on view updates.

### A row swipe outside a list

A row swipe normally attaches to its list cell. A row with no cell (the
Gestures & Haptics preview card, which is pinned outside the list) uses
`apolloConfinedSwipeActions`, which attaches the same recognizer to the
topmost ancestor below the window, as `AncestorGestureHost` does, and
confines it to the row:

- `ApolloSwipeRecognizerDelegate.gestureRecognizer(_:shouldReceive:)`
  refuses a touch that starts outside the row's window frame, so the page
  swipes and everything else outside the card are untouched.
- Scroll exclusivity and `ScrollLock` look up scroll views from the row, not
  from the far ancestor. An unpinned card sits in the settings list, so a
  vertical drag that starts on it scrolls the list and the row swipe fails
  (`isAnyEnclosingScrollViewScrolling`); a pinned card is outside any scroll
  view, so a vertical drag on it does nothing, as on the other pinned
  previews.
- The page-swipe arbitration is the recognizer's own and unchanged: the
  start-zone test (`navigationClaimsRowTouch`), `PageSwipeController.isActive`
  and `SwipeGestureArbiter.rowSwipeActive`. A drag starting in the left 70pt
  of the card is a back swipe, not a row swipe.
- The revealed panel is bounded by the row (`confined`), not the screen's
  edges.

### Row swipe visuals

| Property | Value |
|---|---|
| Short action | Live at 60pt (`SwipeCommitPolicy.shortThreshold`) |
| Long action colour swap | `60 + 120 * fraction` pt (Normal, 0.5, is 120; Early/Late move it to 96/144) |
| Tracking | 1:1, no damping |
| Icon | Centre 30pt inside the moving edge (`iconInset`), parks 30pt from the screen edge at 60pt |
| Icon fade | Opacity = width / 60 |
| Icon pop | Brief ~1.25x on each threshold crossing (`phaseAnimator` on `iconPop`) |
| Colours | Upvote FF5F00, Downvote 4D53DE, Collapse 0076F7, Reply 1FABFF (`ProgressiveSwipeRowModifier.color(for:)`) |
| Panel height | The full list cell, separator to separator (`cellFrame`, captured through `onBeganInCell` at swipe begin) |
| Panel origin | Pinned to the screen edge via a `GeometryReader`, not inside the list's inset |
| Snap-back | Spring with `dampingFraction: 1.0` (no overshoot) |
| First frame | The panel grows from 0: the recognizer re-bases translation at begin |

## Hold-and-drag scrub (gallery and fullscreen video)

Both use the `AncestorGestureHost` pattern: a `UIViewRepresentable`
whose view's `hitTest` returns `nil`, and which in `didMoveToWindow`
reparents its `UILongPressGestureRecognizer` onto the topmost ancestor
below the window. UIKit only offers a touch to a recognizer on the hit
view or one of its ancestors, which is why a hit-testable overlay used
as the recognizer's own view never fires. On `.began` the catcher
disables every descendant `UIScrollView` (so the pager does not page
while scrubbing), restores them on terminal states, and has a 3s
watchdog (`scrubWatchdogGeneration`) in case a terminal state never
arrives. The video player additionally keeps a `regionView` (the
placeholder, not `recognizer.view`, since reparenting changes it) to
gate the left two thirds when Hold for Speed is active.

**Copy this pattern for any new full-surface gesture** rather than
inventing a parallel mechanism.

## Hold menus on media

Media inside a post or comment (`.mediaHoldMenu`, `MediaHoldMenuView.swift`)
uses a plain SwiftUI `.contextMenu` and no recognizer of its own, applied
after `apolloMediaPager` so it wraps the tap targets that open the viewer.
It nests inside the comment row's or post body's own `.contextMenu`; the
deeper one answers a hold on the media. A hold is not a row swipe (that
needs 10pt of horizontal travel, and a context-menu press fails after about
10pt of movement) and the Feed Video Scrubber strip, which takes a touch at
distance 0, keeps a hold on its bottom 28pt. Feed rows are untouched: their
media never gets this menu and a hold there is the row's ••• menu. The
fullscreen viewer keeps `PressAnchoredImageMenu`.

## Status-bar tap

The feed, `PostDetailScreen` and `CommentTreeScreen` lists take the
status-bar tap through `restoresPositionOnSecondScrollToTop()`:
`ScrollToTopDelegateProxy` declines UIKit's own scroll, parks the
offset, scrolls to 1pt below the top (so UIKit keeps calling it), and
a second tap scrolls back to the parked offset. See the type's doc
comment for why.

The two comment screens pass `shortensLongScrolls: true`: from more than
a screen and a half away, `UIScrollView.apolloScroll(to:)` first jumps
without animation to one screen short of the target, lays out, and
animates the rest. An animated scroll makes the `List` build and size a
cell for every row it passes, which stalls a long thread for several
hundred milliseconds. Feeds keep the plain animated scroll: their image
rows resize after the jump and the scroll lands short of the top.

## Tuning constants

| Constant | Value | Where | Effect |
|---|---|---|---|
| `verticalDisqualifyDistance` | 24 | `ApolloSwipePanRecognizer` | Lower means a row swipe gives up sooner on scrolls |
| `minimumHorizontalDistance` | 10 (from `rowSwipeMinimumDistance`) | Policy | Row swipe start travel |
| `bottomSystemGestureInset` | 24 | Policy | Dead strip at the bottom for row swipes |
| `leftInset` / `rightInset` | 70 / 40 | Policy | Page-swipe start zones. Match Apollo; do not tune. |
| `horizontalDominance` | 1.65 | Policy | Shared angle gate. Matches Apollo; do not tune. |
| `scrollCommitDistance` / `scrollStartedDistance` | 10 / 4 | Policy | When a touch counts as a vertical scroll |
| `minimumTravel` | 40 | `PageSwipeController` | Page swipe minimum before completing |

Add a smoke assertion for any constant you change.
