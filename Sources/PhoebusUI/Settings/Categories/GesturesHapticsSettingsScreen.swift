import SwiftUI
import PhoebusCore

/// Gestures & Haptics: which action each of the four swipe slots (left/
/// right, short/long) performs, per screen, in separate "POSTS"/
/// "COMMENTS"/"INBOX"/"PROFILE POSTS" sections, then the haptics, the
/// rotation lock and the ••• menus. Haptic Feedback is General's, Smart
/// Rotation Lock and Portrait Lock Buddy are Apollo's Portrait Lock screen.
public struct GesturesHapticsSettingsScreen: View {
    @State private var perScreenSettings: [SwipeActionScreen: SwipeActionSettings]
    @Setting(NavigationGestureSettingsStore.storage) private var navGestures
    @Setting(GeneralSettingsStore.storage) private var general
    @Setting(PortraitLockStore.storage) private var portraitLock

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

            Section {
                Toggle("Haptic Feedback", isOn: $general.hapticFeedbackEnabled)
                    .apolloSearchRow("Haptic Feedback")
            } header: {
                Text("Haptics")
                    .apolloSectionHeader()
            }

            rotationSection

            Section {
                SettingsDrillDownRow(destination: .actionMenus)
            } header: {
                Text("Menus")
                    .apolloSectionHeader()
            }
        }
        .apolloSettingsSearchScroll()
        .apolloSettingsListAppearance()
        .navigationTitle(SettingsCategory.gesturesHaptics.title)
        .navigationBarTitleDisplayModeIfAvailable()
    }

    /// Smart Rotation Lock and Portrait Lock Buddy.
    private var rotationSection: some View {
        Group {
            Section {
                Toggle("Smart Rotation Lock", isOn: Binding(
                    get: { portraitLock.isEnabled },
                    set: {
                        $portraitLock.isEnabled.wrappedValue = $0
                    }
                ))
                    // search: item "Portrait Lock"
                    .apolloSearchRow("Smart Rotation Lock", lastBeforeFooter: true)
                    .accessibilityIdentifier("portraitLock.toggle")
            } header: {
                Text("Rotation")
                    .apolloSectionHeader()
            } footer: {
                // Verbatim from Apollo's Settings → General → Smart Rotation Lock.
                Text("Locks Phoebus to portrait (vertical) orientation except for Media Viewer.")
                    .apolloSectionFooter()
            }
            Section {
                Toggle("Portrait Lock Buddy", isOn: Binding(
                    get: { portraitLock.portraitLockBuddy },
                    set: {
                        $portraitLock.portraitLockBuddy.wrappedValue = $0
                    }
                ))
                    .apolloSearchRow("Portrait Lock Buddy", lastBeforeFooter: true)
                    .accessibilityIdentifier("portraitLock.buddyToggle")
            } footer: {
                Text("If using the iOS Portrait Orientation Lock feature, Phoebus will attempt to detect device rotations in Media Viewer and offer to let you rotate media.")
                    .apolloSectionFooter()
            }
        }
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
