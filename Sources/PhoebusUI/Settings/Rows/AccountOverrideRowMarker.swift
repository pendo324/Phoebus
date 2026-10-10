import SwiftUI
import PhoebusCore

/// "Separate Settings per Account": a settings row whose field the
/// active account overrides gets a dot, and a long press offers "Use
/// Global Default". Applied by `apolloSearchRow` to the fields its row's
/// bindings write; with the switch off there are none and the row is
/// returned untouched.
struct AccountOverrideRowMarker: ViewModifier {
    let fields: [SettingRowField]

    func body(content: Content) -> some View {
        if fields.isEmpty {
            content
        } else {
            content.modifier(AccountOverrideBadge(fields: fields))
        }
    }
}

private struct AccountOverrideBadge: ViewModifier {
    let fields: [SettingRowField]
    /// Bumped when one of the fields' stores saves, since an override can
    /// come or go without the value changing.
    @State private var revision = 0

    private func overridden() -> [SettingRowField] {
        guard let account = AccountSettingsScope.activeAccount else { return [] }
        return fields.filter {
            AccountSettingsOverrides.overriddenFields(of: $0.key, account: account).contains($0.field)
        }
    }

    func body(content: Content) -> some View {
        let _ = revision
        let overridden = overridden()
        content
            .overlay(alignment: .leading) {
                if !overridden.isEmpty {
                    Circle()
                        .fill(Color.apolloAccent)
                        .frame(width: 6, height: 6)
                        // Into the row's 32pt leading inset, beside the title.
                        .offset(x: -14)
                        .accessibilityElement()
                        .accessibilityLabel("Set for this account")
                        .accessibilityIdentifier("settings.accountOverride.marker")
                }
            }
            .contextMenu {
                if overridden.isEmpty {
                    Text("Uses the Global Default")
                } else {
                    Button {
                        guard let account = AccountSettingsScope.activeAccount else { return }
                        for field in overridden {
                            AccountSettingsOverrides.removeField(field.field, of: field.key, account: account)
                        }
                    } label: {
                        Label("Use Global Default", systemImage: "arrow.uturn.backward")
                    }
                    .accessibilityIdentifier("settings.accountOverride.useGlobal")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .apolloSettingsChanged)) { note in
                guard let key = note.object as? String, fields.contains(where: { $0.key == key }) else { return }
                revision &+= 1
            }
    }
}
