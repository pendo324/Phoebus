import SwiftUI
import PhoebusCore

/// Settings > Appearance > Text Sizes & Fonts: a size for each kind of text
/// on top of the app-wide Text Size, and a built-in font family for titles,
/// content and post/comment details. Phoebus's own screen; Apollo has one size.
public struct TextSizesAndFontsScreen: View {
    @Setting(TextScaleSettings.self) private var settings

    public init() {}

    public var body: some View {
        SettingsPreviewScreenLayout(screen: .textSizes) {
            TextSizesPreviewMock(settings: settings)
        } content: {
            // search: rows "Post Titles", "Post Details", "Opened Post Title", "Post Text", "Comment Headers", "Comment Text", "Link Previews"
            Section {
                ForEach(TextRole.scalable, id: \.self) { role in
                    scaleRow(role)
                }
            } header: {
                Text("Sizes")
                    .apolloSectionHeader()
            } footer: {
                Text("Each size is relative to the Text Size on the Appearance screen.")
                    .apolloSectionFooter()
            }

            // search: rows "Titles Font", "Content Font", "Interface Font"
            Section {
                ForEach(TextFontGroup.allCases, id: \.self) { group in
                    ApolloSettingsPicker(group.title, selection: familyBinding(group),
                                         options: TextFontFamily.allCases,
                                         display: { $0.title })
                        .apolloSearchRow("\(group.title) Font",
                                         lastBeforeFooter: group == .interface)
                        .accessibilityIdentifier("textSizes.font.\(group.rawValue)")
                }
            } header: {
                Text("Fonts")
                    .apolloSectionHeader()
            } footer: {
                Text("Titles are post titles. Content is post and comment text. Interface is post details, comment headers and link previews; menus, settings and other screens keep the system font. A custom theme's font takes precedence over all three.")
                    .apolloSectionFooter()
            }

            Section {
                Button("Reset to Defaults", role: .destructive) {
                    $settings.update { $0 = .default }
                }
                .disabled(settings == .default)
                .apolloPlainSettingsRowInsets(rule: false)
                .accessibilityIdentifier("textSizes.reset")
            }
        }
        .apolloSettingsSearchScroll()
        .navigationTitle("Text Sizes & Fonts")
        .accessibilityIdentifier("textSizes.screen")
    }

    private func scaleRow(_ role: TextRole) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(role.title)
                Spacer()
                Text("\(Int((settings.scale(for: role) * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { settings.scale(for: role) },
                    set: { value in $settings.update { $0.setScale(value, for: role) } }
                ),
                in: TextScaleSettings.scaleRange,
                step: TextScaleSettings.scaleStep
            )
            .accessibilityLabel(role.title)
            .accessibilityIdentifier("textSizes.scale.\(role.rawValue)")
        }
        .apolloSearchRow(role.title)
    }

    private func familyBinding(_ group: TextFontGroup) -> Binding<TextFontFamily> {
        Binding(
            get: { settings.family(for: group) },
            set: { family in $settings.update { $0.setFamily(family, for: group) } }
        )
    }
}
