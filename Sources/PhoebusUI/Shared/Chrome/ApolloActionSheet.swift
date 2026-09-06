import SwiftUI
import PhoebusCore

/// A custom bottom action sheet matching Apollo's "Sort by…" and
/// subreddit-actions sheets.
///
/// SwiftUI's `.confirmationDialog` cannot render per-row icons, selected-row
/// checkmarks or disclosure chevrons, all of which Apollo uses (a trailing ✓
/// on the active sort, a `›` on rows that push a second sheet). This draws
/// the standard iOS action-sheet look (rounded stacked card + separate Cancel
/// card) with that row chrome.
public struct ApolloActionSheetRow: Identifiable {
    public enum Trailing {
        case none
        case checkmark
        case chevron
    }

    public let id = UUID()
    let title: String
    let icon: String?
    let trailing: Trailing
    let isDestructive: Bool
    let accessibilityIdentifier: String?
    let action: () -> Void

    /// Starts a new visual group above this row.
    ///
    /// Only the compact menu path draws it. Apollo's glass "•••" menu shows a
    /// separator under "Gallery View" because Reborn registers that row as an
    /// inline section. The sheet has no such grouping, so this is ignored there.
    let startsSection: Bool

    /// Rows of a nested menu, for a row that opens a second sheet.
    ///
    /// Only the compact path uses it: a `.chevron` row on the sheet path pushes a
    /// follow-up sheet ("Top" -> time period), while a `UIMenu` expresses the
    /// same thing as a submenu, as Reborn does when it swaps "Submit Post" for a
    /// nested post-type menu.
    ///
    /// The row's own `action` is kept; the sheet path needs it to present the
    /// follow-up sheet.
    let submenu: [ApolloActionSheetRow]

    /// A picture before the title, for rows whose "icon" is content
    /// rather than a symbol (a flair's sprite). Sheet path only.
    let leading: AnyView?

    /// True when this row's trailing checkmark should be drawn.
    ///
    /// The menu path maps it to `UIAction.state = .on`, as Reborn does, so a
    /// checkmark is not a reason to keep a surface as a sheet.
    var isChecked: Bool { if case .checkmark = trailing { return true } else { return false } }

    public init(_ title: String, icon: String? = nil, trailing: Trailing = .none, isDestructive: Bool = false, startsSection: Bool = false, submenu: [ApolloActionSheetRow] = [], leading: AnyView? = nil, accessibilityIdentifier: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.leading = leading
        self.icon = icon
        self.trailing = trailing
        self.isDestructive = isDestructive
        self.startsSection = startsSection
        self.submenu = submenu
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }
}

public struct ApolloActionSheet: View {
    let title: String?
    let rows: [ApolloActionSheetRow]
    let onDismiss: () -> Void

    public init(title: String?, rows: [ApolloActionSheetRow], onDismiss: @escaping () -> Void) {
        self.title = title
        self.rows = rows
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            ScrollView {
            VStack(spacing: 0) {
                if let title {
                    Text(title)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                    Divider()
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    Button {
                        onDismiss()
                        // Defer the action until the sheet has started dismissing so a row that
                        // presents a follow-up sheet (e.g. Top -> time period) does not collide
                        // with this sheet's dismissal.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            row.action()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            if let icon = row.icon {
                                ApolloIconImage(icon)
                                    .frame(width: 26)
                            }
                            if let leading = row.leading {
                                leading
                            }
                            Text(row.title)
                            Spacer()
                            switch row.trailing {
                            case .none:
                                EmptyView()
                            case .checkmark:
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                            case .chevron:
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .foregroundStyle(row.isDestructive ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
                        .padding(.horizontal, 16)
                        .frame(height: 56)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier(row.accessibilityIdentifier ?? "actionSheet.row.\(row.title)")
                    if index < rows.count - 1 {
                        Divider()
                    }
                }
            }
            // Floating chrome over content: glass where it can be drawn, a material
            // where it cannot.
            .apolloGlassBackground(
                in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                fallback: .regularMaterial
            )
            }
            .scrollBounceBehaviorBasedOnSizeIfAvailable()

            Button {
                onDismiss()
            } label: {
                Text("Cancel")
                    .fontWeight(.semibold)
                    .frame(height: 56)
                    .frame(maxWidth: .infinity)
            }
            .apolloGlassBackground(
                in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                fallback: .regularMaterial,
                interactive: true
            )
            .accessibilityIdentifier("actionSheet.cancel")
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .presentationBackground(.clear)
    }
}

extension View {
    /// Presents an `ApolloActionSheet` with the standard action-sheet
    /// presentation chrome (clear backdrop, height fitted to content).
    public func apolloActionSheet(isPresented: Binding<Bool>, title: String?, rows: [ApolloActionSheetRow]) -> some View {
        modifier(ApolloActionSheetPresenter(isPresented: isPresented, title: title, rows: rows))
    }
}

/// Under Liquid Glass a plain list of choices is the system's own action
/// sheet, which iOS 26 draws as glass, as Reborn's UIAlertControllers are;
/// the drawn sheet stays for rows the system one can't show (icons,
/// checkmarks, pictures, follow-up sheets) and without Liquid Glass.
private struct ApolloActionSheetPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let title: String?
    let rows: [ApolloActionSheetRow]

    private var usesSystemSheet: Bool {
        LiquidGlass.isEnabled && rows.allSatisfy {
            $0.icon == nil && $0.leading == nil && $0.submenu.isEmpty
                && { if case .none = $0.trailing { return true } else { return false } }($0)
        }
    }

    func body(content: Content) -> some View {
        if usesSystemSheet {
            content.confirmationDialog(title ?? "", isPresented: $isPresented,
                                      titleVisibility: title == nil ? .hidden : .visible) {
                ForEach(rows) { row in
                    Button(row.title, role: row.isDestructive ? .destructive : nil, action: row.action)
                }
                Button("Cancel", role: .cancel) {}
            }
        } else {
            content.legacyApolloActionSheet(isPresented: $isPresented, title: title, rows: rows)
        }
    }
}

extension View {
    fileprivate func legacyApolloActionSheet(isPresented: Binding<Bool>, title: String?, rows: [ApolloActionSheetRow]) -> some View {
        sheet(isPresented: isPresented) {
            ApolloActionSheet(title: title, rows: rows) {
                isPresented.wrappedValue = false
            }
            // Height fits the content but is capped so a long sheet (the subreddit
            // "•••" sheet can reach ~9 rows) cannot clip its own Cancel button; past the
            // cap the row list scrolls.
            .presentationDetents([.height(min(CGFloat(rows.count) * 56 + (title == nil ? 0 : 41) + 80, 620))])
            .presentationDragIndicator(.hidden)
        }
    }
}

/// One icon in a menu's leading composer row.
///
/// Apollo puts the composer at the top of a subreddit's "•••" menu as a row
/// of icons (link+, text+, poll+) rather than a "Submit Post" text row.
/// Reborn builds it as a leading inline menu of post-type icons.
public struct ApolloComposerAction: Identifiable {
    public let id = UUID()
    let systemImage: String
    let label: String
    let action: () -> Void

    public init(systemImage: String, label: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.action = action
    }
}

/// Apollo's "•••" menu, in whichever of its two shapes applies.
///
/// - Compact native menu, anchored to the button, rows grouped by separators.
/// - Full-width bottom action sheet with a Cancel card.
///
/// They are the same menu on different rendering paths: on Liquid Glass
/// (iOS 26) Apollo converts its ActionController sheet into a `UIMenu`;
/// elsewhere it presents a bottom sheet. This picks between them with the
/// same gate as every other glass surface, so the app stays on one path.
public struct ApolloOverflowMenu: View {
    let title: String?
    let rows: [ApolloActionSheetRow]
    /// Leading post-type icon row; empty for menus with no composer
    /// (a multireddit, Home).
    let composerRow: [ApolloComposerAction]
    /// The button's own symbol name rather than an arbitrary SwiftUI label,
    /// because the glass path hosts a `UIButton`/`UIMenu` whose bar-button-style
    /// control takes a `UIImage`.
    let systemImage: String

    @State private var showingSheet = false

    public init(title: String? = nil,
                systemImage: String,
                composerRow: [ApolloComposerAction] = [],
                rows: [ApolloActionSheetRow]) {
        self.title = title
        self.systemImage = systemImage
        self.composerRow = composerRow
        self.rows = rows
    }

    /// Rows split into their separator-delimited groups.
    ///
    /// Thin wrapper over `ApolloMenuSectioning` (in PhoebusCore, where the rule
    /// lives).
    public static func sections(of rows: [ApolloActionSheetRow]) -> [[ApolloActionSheetRow]] {
        ApolloMenuSectioning
            .sections(count: rows.count) { rows[$0].startsSection }
            .map { $0.map { rows[$0] } }
    }

    /// A menu row's label.
    ///
    /// Carries the row's icon only. UIKit owns a menu row's checkmark and puts
    /// it on the trailing edge from `UIAction.state`; the leading icon slot
    /// already holds the sort's trophy/droplet/clock glyph.
    @ViewBuilder
    private func rowLabel(_ row: ApolloActionSheetRow) -> some View {
        if let icon = row.icon {
            Label { Text(row.title) } icon: { ApolloIconImage(icon) }
        } else {
            Text(row.title)
        }
    }

    /// One menu row.
    ///
    /// An icon row carries no checkmark: Reborn builds rows from two buffers.
    /// `actions` rows get an image and a hardcoded `checked = NO`; `textActions`
    /// rows get no image and a real `checked`. The sorts are `actions` rows, so
    /// the glass sort menu shows six icons and no checkmark. The pre-glass sheet
    /// does show a checkmark; `ApolloOverflowMenu` selects between the two.
    ///
    /// An icon-less checked row uses a `Toggle`, which SwiftUI maps onto
    /// `UIAction.state` so UIKit draws the checkmark on the trailing edge.
    @ViewBuilder
    private func menuRow(_ row: ApolloActionSheetRow) -> some View {
        if row.isChecked, row.icon == nil {
            Toggle(isOn: .constant(true)) {
                rowLabel(row)
            }
            .accessibilityIdentifier(row.accessibilityIdentifier ?? "actionSheet.row.\(row.title)")
        } else {
            Button(role: row.isDestructive ? .destructive : nil) {
                row.action()
            } label: {
                rowLabel(row)
            }
            .accessibilityIdentifier(row.accessibilityIdentifier ?? "actionSheet.row.\(row.title)")
        }
    }

    public var body: some View {
        if LiquidGlass.isEnabled, LiquidGlass.canRenderGlass {
            // A real UIMenu, not SwiftUI's: SwiftUI puts row icons on the trailing
            // edge and expands a submenu inline, where Reborn's are leading and open a
            // follow-up list. See `ApolloUIKitMenuButton`.
            ApolloUIKitMenuButton(systemImage: systemImage,
                                  title: title,
                                  composerRow: composerRow,
                                  rows: rows)
                .fixedSize()
                .apolloRecordGlassPath(.glass)
        } else {
            Button {
                showingSheet = true
            } label: {
                ApolloIconImage(systemImage)
                .accessibilityLabel(title ?? "Actions")
            }
            .apolloActionSheet(isPresented: $showingSheet, title: title,
                               rows: composerRow.map { action in
                                   // The sheet has no inline icon row, so each composer icon becomes a
                                   // normal labelled row, like the "Submit Post ›" row.
                                   ApolloActionSheetRow(action.label, icon: action.systemImage,
                                                        accessibilityIdentifier: "feed.overflow.compose.\(action.label)",
                                                        action: action.action)
                               } + rows)
            .apolloRecordGlassPath(.fallback)
        }
    }
}
