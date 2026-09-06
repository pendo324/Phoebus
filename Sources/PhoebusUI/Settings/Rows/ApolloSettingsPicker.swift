import SwiftUI

/// Apollo's settings-row picker: a grey value on the trailing edge,
/// with no stepper glyph and no chevron.
///
/// SwiftUI's default `Picker` in a `Form`/`List` draws the value in the
/// accent colour with a stepper glyph, and `.pickerStyle(.navigationLink)`
/// adds a chevron and pushes a screen. This keeps the menu behaviour
/// (tap the row, pick from a popup) with Apollo's value styling.
public struct ApolloSettingsPicker<Value: Hashable, Label: View>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let display: (Value) -> String
    /// Draws a trailing disclosure chevron after the value.
    ///
    /// Apollo uses both shapes: General's "Default Sort · Hot" has none,
    /// Profile Layout's "Profile Style · Immersive ›" has one. Presentational
    /// only; the choices still open as a menu.
    let showsChevron: Bool
    /// Draws Reborn's menu-button accessory instead: the value followed by
    /// a 9pt semibold `chevron.up.chevron.down` at 3pt padding, in secondary
    /// label colour ("Hard ⌃⌄"). Used by Hide Style, Scroll Behavior and
    /// Header Style.
    let showsMenuChevrons: Bool
    let label: () -> Label

    public init(_ title: String,
                selection: Binding<Value>,
                options: [Value],
                display: @escaping (Value) -> String,
                showsChevron: Bool = false,
                showsMenuChevrons: Bool = false,
                @ViewBuilder label: @escaping () -> Label) {
        self.title = title
        self._selection = selection
        self.options = options
        self.display = display
        self.showsChevron = showsChevron
        self.showsMenuChevrons = showsMenuChevrons
        self.label = label
    }

    public var body: some View {
        Menu {
            // A Picker inside a Menu gives checkmark-on-selected for free.
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(display(option)).tag(option)
                }
            }
        } label: {
            HStack {
                label()
                    // A `Menu` label centres wrapped text; keep titles leading like
                    // every other settings row.
                    .multilineTextAlignment(.leading)
                Spacer()
                Text(display(selection))
                    // Secondary grey, not `.tint`.
                    .foregroundStyle(.secondary)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                if showsMenuChevrons {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, -5) // HStack's 8pt minus the real 3pt
                }
            }
            .contentShape(Rectangle())
        }
        // Keeps the row from taking the accent colour, since a `Menu`'s
        // label is treated as a control.
        .tint(.primary)
        .accessibilityIdentifier("settingsPicker.\(title)")
    }
}

public extension ApolloSettingsPicker where Label == Text {
    init(_ title: String,
         selection: Binding<Value>,
         options: [Value],
         display: @escaping (Value) -> String,
         showsChevron: Bool = false,
         showsMenuChevrons: Bool = false) {
        self.init(title, selection: selection, options: options,
                  display: display, showsChevron: showsChevron,
                  showsMenuChevrons: showsMenuChevrons) {
            Text(title)
        }
    }
}
