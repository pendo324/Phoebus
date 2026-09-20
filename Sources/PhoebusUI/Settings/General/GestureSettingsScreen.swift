import SwiftUI
import PhoebusCore

/// Gestures settings: which action each of the four swipe slots (left/
/// right, short/long) performs, per screen, in separate "POSTS"/
/// "COMMENTS"/"INBOX"/"PROFILE POSTS" sections.
public struct GestureSettingsScreen: View {
    @State private var perScreenSettings: [SwipeActionScreen: SwipeActionSettings]
    @Setting(NavigationGestureSettingsStore.storage) private var navGestures

    public init() {
        var loaded: [SwipeActionScreen: SwipeActionSettings] = [:]
        for screen in SwipeActionScreen.allCases {
            loaded[screen] = SwipeActionStore.load(for: screen)
        }
        _perScreenSettings = State(initialValue: loaded)
    }

    public var body: some View {
        List {
            // Each screen gets its own section, listing the four slot titles
            // ("Left Short Swipe", "Left Long Swipe", "Right Short Swipe", "Right
            // Long Swipe") with the bound action as a gray right-detail value.
            // Builds whole sections, not rows: the row geometry lives on
            // `slotPicker` (`.apolloSettingsRowInsets()`).
            ForEach(SwipeActionScreen.allCases, id: \.self) { screen in
                Section {
                    slotPicker(screen: screen, slot: .leftShort)
                    slotPicker(screen: screen, slot: .leftLong)
                    slotPicker(screen: screen, slot: .rightShort)
                    slotPicker(screen: screen, slot: .rightLong)
                } header: {
                    Text(screen.displayName)
                        .apolloSectionHeader()
                }
            }

            // One "Other" section, in order: Disable Left Swipes / Disable Right
            // Swipes / Disable Navigation Gestures, each with its subtitle, then
            // Long Swipe Trigger Point and Restore Default Swipe Actions. No
            // footers.
            Section {
                subtitledToggle("Disable Left Swipes", "Becomes swipe anywhere to go back",
                                isOn: $navGestures.disableLeftSwipeGestureActions)
                subtitledToggle("Disable Right Swipes", "Becomes swipe anywhere to go forward",
                                isOn: $navGestures.disableRightSwipeGestureActions)
                subtitledToggle("Disable Navigation Gestures", "Ability to swipe forward/back pages",
                                isOn: Binding(get: { !navGestures.pushPopSwipeGesturesEnabled },
                                              set: { on in $navGestures.update { $0.pushPopSwipeGesturesEnabled = !on } }))
                ApolloSettingsPicker("Long Swipe Trigger Point", selection: $navGestures.longSwipeTriggerPoint,
                                 options: LongSwipeTriggerPoint.allCases.map { $0 },
                                 display: { $0.title })
                    .apolloSearchRow("Long Swipe Trigger Point")
                    .accessibilityIdentifier("gestures.longSwipeTriggerPoint")
                Button("Restore Default Swipe Actions") {
                    for screen in SwipeActionScreen.allCases {
                        SwipeActionStore.restoreDefaults(for: screen)
                    }
                    reloadAll()
                }
                .foregroundStyle(Color.apolloAccent)
                .apolloSearchRow("Restore Default Swipe Actions")
            } header: {
                Text("Other")
                    .apolloSectionHeader()
            }
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle("Gestures")
    }

    /// One slot row: the slot title with its bound action shown as the
    /// gray right-detail value.
    private func subtitledToggle(_ title: String, _ subtitle: String, isOn: Binding<Bool>) -> some View {
        SettingsDetailToggle(title, detail: subtitle, isOn: isOn)
            .apolloSearchRow(title)
    }

    private func slotPicker(screen: SwipeActionScreen, slot: SwipeSlot) -> some View {
        ApolloSettingsPicker(slot.title,
                             selection: binding(screen: screen, slot: slot),
                             options: actions(for: screen),
                             display: { $0.displayName }) {
            // Rows lead with the slot's own icon (named like `left-short-swipe`).
            HStack(spacing: 10) {
                SwipeSlotIcon(slot: slot)
                Text(slot.title)
            }
        }
        .apolloSettingsRowInsets()
        .accessibilityIdentifier("gestures.\(screen.rawValue).\(slot.rawValue)")
    }

    private func binding(screen: SwipeActionScreen, slot: SwipeSlot) -> Binding<SwipeAction> {
        Binding(
            get: { slot.value(in: perScreenSettings[screen] ?? .default) },
            set: { newValue in
                var updated = perScreenSettings[screen] ?? .default
                slot.set(newValue, in: &updated)
                perScreenSettings[screen] = updated
                SwipeActionStore.storage(for: screen).update { slot.set(newValue, in: &$0) }
            }
        )
    }

    private func reloadAll() {
        var loaded: [SwipeActionScreen: SwipeActionSettings] = [:]
        for screen in SwipeActionScreen.allCases {
            loaded[screen] = SwipeActionStore.load(for: screen)
        }
        perScreenSettings = loaded
    }

    /// Stock's per-screen list, plus a stored choice from elsewhere so
    /// it stays visible.
    private func actions(for screen: SwipeActionScreen) -> [SwipeAction] {
        var list = screen.availableActions
        let stored = SwipeSlot.allCases.map { $0.value(in: perScreenSettings[screen] ?? .default) }
        for action in stored where !list.contains(action) { list.append(action) }
        return list
    }
}
