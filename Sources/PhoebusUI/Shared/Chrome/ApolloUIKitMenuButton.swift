import SwiftUI
import UIKit
import PhoebusCore

/// A real UIKit `UIMenu`, hosted in SwiftUI.
///
/// A SwiftUI `Menu` differs from Reborn's glass menu in two ways: icons
/// sit on the trailing edge instead of leading, and a submenu expands
/// inline instead of opening a follow-up list. Reborn builds `UIMenu`s
/// whose submenus use `options: 0` (not inline); SwiftUI's nested `Menu`
/// maps onto the inline form. Used only on the Liquid Glass path; the
/// pre-glass action sheet keeps its own rendering.
struct ApolloUIKitMenuButton: UIViewRepresentable {
    let systemImage: String
    let title: String?
    let composerRow: [ApolloComposerAction]
    let rows: [ApolloActionSheetRow]

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(StockIcon.uiImage(systemImage), for: .normal)
        // The menu is the button's action, so a single tap opens it.
        button.showsMenuAsPrimaryAction = true
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .vertical)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        button.setImage(StockIcon.uiImage(systemImage), for: .normal)
        // Rebuilt on every update: checked state and titles change as the
        // user picks, and a menu cached from `makeUIView` would go stale.
        button.menu = Self.menu(title: title, composerRow: composerRow, rows: rows)
    }

    /// Builds the `UIMenu` for `rows`. `static` so the smoke test can
    /// exercise the real construction.
    static func menu(title: String?,
                     composerRow: [ApolloComposerAction] = [],
                     rows: [ApolloActionSheetRow]) -> UIMenu {
        let sections = ApolloMenuSectioning
            .sections(count: rows.count) { rows[$0].startsSection }
            .map { $0.map { rows[$0] } }

        var children: [UIMenuElement] = sections.map { section in
            // One inline child per group draws the separators, mirroring Reborn's
            // inline section around an injected row.
            UIMenu(title: "",
                   options: .displayInline,
                   children: section.map(element(for:)))
        }
        // The composer's post-type icons lead the menu as one inline section;
        // an inline section of image-only actions renders as a compact icon row.
        if !composerRow.isEmpty {
            let icons = composerRow.map { entry -> UIMenuElement in
                let action = UIAction(title: entry.label,
                                      image: UIImage(systemName: entry.systemImage)) { _ in
                    entry.action()
                }
                action.accessibilityIdentifier = "feed.overflow.compose.\(entry.label)"
                return action
            }
            children.insert(
                UIMenu(title: "", options: .displayInline, children: icons),
                at: 0)
        }
        return UIMenu(title: title ?? "", children: children)
    }

    private static func element(for row: ApolloActionSheetRow) -> UIMenuElement {
        let image = row.icon.flatMap { StockIcon.uiImage($0) }

        if !row.submenu.isEmpty {
            // `options: []`, not `.displayInline`: inline submenus expand in
            // place, plain ones open as a follow-up list like Reborn's sort menu.
            return UIMenu(title: row.title,
                          image: image,
                          options: [],
                          children: row.submenu.map(element(for:)))
        }

        let action = UIAction(title: row.title,
                              image: image,
                              attributes: row.isDestructive ? .destructive : []) { _ in
            row.action()
        }
        // Icon rows carry no checkmark: Reborn's icon rows pass `checked` as
        // NO and only icon-less text rows get a real checkmark.
        if row.isChecked, row.icon == nil {
            action.state = .on
        }
        action.accessibilityIdentifier = row.accessibilityIdentifier
            ?? "actionSheet.row.\(row.title)"
        return action
    }
}
