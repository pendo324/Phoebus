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
| `Sources/PhoebusUI/Navigation/PageSwipes/PageSwipeNavigation.swift` | **Back and forward page swipes**: `PageSwipeController`, `PageSwipeInstaller`, `PageSwipeAnimator`, `PageSwipeInteraction`. |
| `Sources/PhoebusUI/Navigation/PageSwipes/ForwardNavigation.swift` | `ForwardNavigationStore` (the forward stack), `apolloForwardSwipe()`, `apolloTracksForwardNavigation()`. |
| `Sources/PhoebusUI/Navigation/PageSwipes/InteractiveSwipeNavigationModifier.swift` | `apolloInteractiveSwipeNavigation()` for the root stacks, and `UINavigationController.apolloDisableSystemPopGestures()`. |
| `Sources/PhoebusUI/Settings/Rows/SettingsNavigation.swift` | Path-driven navigation for the Settings tab: `SettingsNavigationModel`, `SettingsRoute`, `SettingsLink`, `settingsDestination(isPresented:)`. |
| `Sources/PhoebusUI/Shared/UIKit/ScrollGestureExclusivity.swift` | `ScrollGestureExclusivity` (is a scroll view scrolling under this touch?) and `ScrollLock` (switches scroll pans off while a swipe owns the touch). |
| `Sources/PhoebusUI/Navigation/RowSwipes/SwipeActionsModifier.swift` | **Row swipe** (upvote/downvote/save/reply/hide on post and comment rows): `ApolloSwipePanRecognizer`, `ApolloSwipeRecognizerDelegate`, `AncestorAttachingView`, `SwipeGestureArbiter`, `ProgressiveSwipeRowModifier` (the revealed panel). |
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
