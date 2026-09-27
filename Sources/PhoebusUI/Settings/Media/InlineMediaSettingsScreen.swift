import SwiftUI
import PhoebusCore

/// Reborn's Inline Media settings sub-screen (Settings > Custom API >
/// Media > Inline Media Previews): a master toggle plus alignment,
/// size, and tap-to-play controls.
public struct InlineMediaSettingsScreen: View {
    @Setting(InlineMediaSettingsStore.storage) private var settings

    public init() {}

    public var body: some View {
        // A live preview card above the controls, pinned by default, so
        // alignment and size are adjusted with the result in view.
        SettingsPreviewScreenLayout(screen: .inlineMedia) {
            InlineMediaPreviewMock(settings: settings)
        } content: {
            Section {
                Toggle("Inline Media Previews", isOn: $settings.enabled)
                    .apolloSearchRow("Inline Media Previews", lastBeforeFooter: true)
            } footer: {
                Text("Renders images, GIFs, and videos linked within a post or comment's body inline, instead of as a plain link.")
                    .apolloSectionFooter()
            }
            if settings.enabled {
                // The section title is the full "Inline Media Alignment". Alignment is
                // a value row whose tap opens an action sheet (title and message
                // verbatim below); the option order is Center, Left, Right.
                Section {
                    ApolloSettingsPicker("Inline Media Alignment", selection: $settings.alignment,
                                 options: Array([InlineMediaAlignment.center, .left, .right]),
                                 display: { $0.displayName })
                    .apolloSearchRow("Inline Media Alignment", lastBeforeFooter: true)
                } footer: {
                    // Verbatim sheet message.
                    Text("Horizontal position of inline media narrower than the row.")
                    .apolloSectionFooter()
                }
                // Size is a slider snapping to three detents (50/75/100) with a live
                // "%" value.
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Inline Media Size")
                            Spacer()
                            Text("\(settings.size.rawValue)%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(settings.size.rawValue) },
                                set: { v in $settings.update { $0.size = InlineMediaSize.snapped(to: v) } }
                            ),
                            in: 50...100,
                            step: 25
                        )
                        .accessibilityLabel("Inline Media Size")
                    }
                    .apolloSearchRow("Inline Media Size")
                }
                // Four autoplay modes, including "WiFi Only", which keeps GIFs off
                // cellular data.
                Section {
                    ApolloSettingsPicker("Autoplay Inline GIFs", selection: $settings.autoplayMode,
                                 options: Array(InlineGIFAutoplayMode.realOrder),
                                 display: { $0.displayName })
                    .apolloSearchRow("Autoplay Inline GIFs", lastBeforeFooter: true)
                } footer: {
                    // Verbatim sheet message.
                    Text("Tap to Play pauses GIFs behind a play button; tapping plays or pauses that GIF inline.")
                    .apolloSectionFooter()
                }
            }
            // A separate row, deliberately outside the `settings.enabled` gate:
            // message media is its own toggle rather than a sub-option of the
            // post/comment one, and its footer spells out the distinction.
            Section {
                Toggle("Inline Media in Messages", isOn: $settings.enabledInMessages)
                    .apolloSearchRow("Inline Media in Messages", lastBeforeFooter: true)
            } footer: {
                // Paraphrases the footer: the setting governs the threads Apollo
                // draws itself, not Reddit's own modern chat, which renders its own
                // media.
                Text("Renders media inline in the message threads Phoebus draws itself. Reddit's modern Chat renders its own media, so this doesn't apply there.")
                    .apolloSectionFooter()
            }
        }
        .apolloSettingsSearchScroll()
        .navigationTitle("Inline Media")
    }
}
