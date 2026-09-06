import SwiftUI
import PhoebusCore

/// A Liquid Glass search field, matching the shape iOS 26 system apps
/// use (Shortcuts' bottom bar).
///
/// SwiftUI's `.searchable` in a `List` has a defect on iOS 26: the
/// focused field paints its own fill across the field's full height,
/// pinning typed text against a hard edge. Clearing `backgroundColor`,
/// `borderStyle` and every subview's background does not suppress it
/// (every candidate subview has zero height while the fill spans the
/// row), so this is a plain SwiftUI `TextField` on a shape drawn here.
///
/// Used only when `LiquidGlass.isEnabled`; older systems keep the
/// `.searchable` path. The shape is Apple's iOS 26 pattern, not stock
/// Apollo's (a UIKit `navigationItem.searchController`).
public struct GlassSearchField: View {
    @Binding var text: String
    let placeholder: String
    /// Shown trailing the field, outside the capsule, like Shortcuts'
    /// dismiss button. `nil` hides it.
    var onDismiss: (() -> Void)?
    /// Raises the keyboard as soon as the field appears. True when the
    /// field has just replaced the tab pill, since the user already tapped
    /// a search button.
    var focusOnAppear: Bool = false

    @State private var isFieldFocused = false

    public init(
        text: Binding<String>,
        placeholder: String,
        onDismiss: (() -> Void)? = nil,
        focusOnAppear: Bool = false
    ) {
        _text = text
        self.placeholder = placeholder
        self.onDismiss = onDismiss
        self.focusOnAppear = focusOnAppear
    }

    public var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)

                GlassSearchTextField(
                    text: $text,
                    placeholder: placeholder,
                    isFocused: $isFieldFocused
                )

                // Filled-state clear button inside the capsule.
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                    .accessibilityIdentifier("glassSearch.clear")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            // One flat surface, no inner rectangle. Real Liquid Glass, matching
            // `LiquidGlassTabBar`: both controls go through `apolloGlassBackground`
            // so they stay identical as the system restyles them, which a measured
            // constant or theme colour would not. The field's own fill is cleared
            // so the glass is the only thing drawn.
            .apolloGlassBackground(in: Capsule(), interactive: true)

            // The outer dismiss button sits outside the capsule as its own circular
            // glass control.
            if let onDismiss {
                Button {
                    text = ""
                    isFieldFocused = false
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .apolloGlassBackground(in: Circle(), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss search")
                .accessibilityIdentifier("glassSearch.dismiss")
            }
        }
        .onAppear {
            guard focusOnAppear else { return }
            // One runloop turn: focusing in the same turn the field is inserted
            // is dropped, leaving the field without a keyboard.
            DispatchQueue.main.async { isFieldFocused = true }
        }
    }
}

/// Per-screen search classification, following Apple's HIG ("Search
/// fields" > iOS) entry points:
///
/// - Bottom toolbar (`apolloGlassSearchField`): a screen that filters
///   its own already-loaded list. Settings, Recently Read, Theme
///   Gallery, App Icons, Modmail.
/// - Search tab, field at the top: the dedicated landing page.
///   `SubredditSearchScreen` (suggestions, Random, Trending) keeps
///   `.searchable` at the top, as does `PostSearchScreen`.
/// - Inline: the Subreddits root's "Filter Subreddits" bar, which sits
///   above the list it filters and so stays distinct from the global
///   Search tab.
///
/// Attaches the right search affordance for the running system: on Liquid
/// Glass a pinned `GlassSearchField` in a bottom bar, elsewhere the
/// stock `.searchable`.
public extension View {
    /// Bottom-toolbar search on glass systems, stock `.searchable`
    /// everywhere else.
    ///
    /// Use this for a screen that filters its own list, not for a search
    /// landing page or a filter whose position next to its content carries
    /// meaning; see `ApolloGlassSearchField`.
    /// - Parameter alwaysVisible: pins the non-glass `.searchable` field
    ///   open under the nav bar instead of hiding it until a pull-down.
    ///   Defaults to true: these screens filter a list the user is already
    ///   looking at, a hidden filter is effectively missing, and Apollo
    ///   shows a persistent pill under the nav bar. It also keeps the glass
    ///   and non-glass paths equivalent, since the glass path always shows
    ///   its search button.
    func apolloGlassSearchField(
        text: Binding<String>,
        prompt: String,
        alwaysVisible: Bool = true
    ) -> some View {
        modifier(ApolloGlassSearchField(
            text: text, prompt: prompt, alwaysVisible: alwaysVisible))
    }


}

struct ApolloGlassSearchField: ViewModifier {
    @Binding var text: String
    let prompt: String
    var alwaysVisible: Bool = true

    @Environment(\.glassSearchCoordinator) private var coordinator
    @Environment(\.glassSearchTabIsActive) private var tabIsActive

    func body(content: Content) -> some View {
        if let coordinator {
            // Glass + inside the custom tab bar: the bar draws the field, so this
            // screen only publishes its prompt and mirrors the query back (see
            // `GlassSearchCoordinator`). Observation happens in a child view
            // holding an `@ObservedObject`: reading the coordinator from
            // `@Environment` does not subscribe to `objectWillChange`, so
            // `.onChange(of: coordinator.text)` would never fire.
            GlassSearchBridge(
                coordinator: coordinator,
                text: $text,
                prompt: prompt,
                tabIsActive: tabIsActive,
                content: content
            )
        } else {
            // No glass search (standard `TabView`, a pre-iOS-26 system, or glass
            // turned off): stock `.searchable`. `.navigationBarDrawer(displayMode:
            // .always)` keeps the field pinned under the nav bar; plain
            // `.searchable` hides it until a pull-down, which is unreachable on a
            // list that opens already scrolled.
            if alwaysVisible {
                content.searchable(
                    text: $text,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: prompt
                )
            } else {
                content.searchable(text: $text, prompt: prompt)
            }
        }
    }
}

private struct GlassSearchBridge<Content: View>: View {
    @ObservedObject var coordinator: GlassSearchCoordinator
    @Binding var text: String
    let prompt: String
    let tabIsActive: Bool
    let content: Content

    /// Stable for this screen's lifetime; see
    /// `GlassSearchCoordinator.resign(owner:)`.
    @State private var id = UUID()

    var body: some View {
        content
            .onAppear {
                guard tabIsActive else { return }
                coordinator.register(prompt: prompt, owner: id)
                adopt()
            }
            .onChange(of: tabIsActive) { _, isActive in
                // Switching tabs does not fire `.onDisappear` (the content stays in
                // the hierarchy), so this is what retracts the prompt.
                if isActive {
                    coordinator.register(prompt: prompt, owner: id)
                    adopt()
                } else {
                    coordinator.resign(owner: id)
                    text = ""
                }
            }
            .onDisappear {
                coordinator.resign(owner: id)
                text = ""
            }
            .onChange(of: coordinator.text) { _, newValue in
                text = newValue
            }
    }

    /// Syncs this screen's query with the shared coordinator when the
    /// screen becomes visible. The screen wins if it already has a query,
    /// otherwise the coordinator does; always copying coordinator to screen
    /// would erase a pre-seeded query (such as the `APOLLO_SETTINGS_SEARCH`
    /// debug seed).
    private func adopt() {
        if !text.isEmpty {
            coordinator.text = text
            // A pre-seeded query has nowhere to show unless the field is up.
            coordinator.isActive = true
        } else {
            text = coordinator.text
        }
    }
}

/// Shared channel between a screen that wants a search field and the
/// Liquid Glass tab bar that draws it.
///
/// The iOS 26 system pattern (Shortcuts) has one bottom cluster: the tab
/// pill, with search collapsing it rather than stacking on it. A screen
/// cannot draw that itself, since the pill is owned by
/// `LiquidGlassTabBar` several levels up, and a preference key can't
/// carry it (the payload is a `Binding`, and preference values must be
/// `Equatable`). So the tab bar owns this object, publishes it through
/// the environment, and a screen registers its prompt on appear.
///
/// `prompt == nil` means no screen currently wants search, which hides
/// the magnifier button on every other tab.
@MainActor
public final class GlassSearchCoordinator: ObservableObject {
    /// The live query. Owned here so it survives the field being
    /// collapsed and re-expanded within the same screen visit.
    @Published public var text: String = ""
    /// Whether the field has replaced the tab pill.
    @Published public var isActive: Bool = false
    /// Set by the visible screen; `nil` when no screen wants search.
    @Published public var prompt: String?

    /// Identity of the screen that currently owns the prompt. A pushed
    /// screen can register while its parent is still in the hierarchy, and
    /// SwiftUI fires the incoming screen's `.onAppear` before the outgoing
    /// screen's `.onDisappear`, so an unguarded retraction would clear the
    /// prompt the new screen just registered.
    private var ownerID: UUID?

    public init() {}

    /// Claims the search affordance for `owner`. A change of owner resets
    /// the field, so each screen starts its search from scratch, as
    /// `.searchable` does across a push.
    public func register(prompt: String, owner: UUID) {
        if ownerID != owner {
            ownerID = owner
            text = ""
            isActive = false
        }
        self.prompt = prompt
    }

    /// Releases it, but only if `owner` still holds it, so a late
    /// `.onDisappear` from a superseded screen can't wipe the new owner's
    /// prompt.
    public func resign(owner: UUID) {
        guard ownerID == owner else { return }
        ownerID = nil
        prompt = nil
        dismiss()
    }

    public func dismiss() {
        text = ""
        isActive = false
    }
}

/// Whether the tab hosting this view is the one on screen.
///
/// `LiquidGlassTabBar` keeps every tab's content in the hierarchy and
/// only changes opacity, so SwiftUI fires `.onAppear` for all five tabs
/// at launch; without this a background tab's search prompt would
/// register and the search button would appear over Posts.
private struct GlassSearchTabIsActiveKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

private struct GlassSearchCoordinatorKey: EnvironmentKey {
    static let defaultValue: GlassSearchCoordinator? = nil
}

public extension EnvironmentValues {
    var glassSearchCoordinator: GlassSearchCoordinator? {
        get { self[GlassSearchCoordinatorKey.self] }
        set { self[GlassSearchCoordinatorKey.self] = newValue }
    }

    var glassSearchTabIsActive: Bool {
        get { self[GlassSearchTabIsActiveKey.self] }
        set { self[GlassSearchTabIsActiveKey.self] = newValue }
    }
}

#if canImport(UIKit)
/// A `UITextField` wrapper, used instead of SwiftUI's `TextField`.
///
/// SwiftUI's `TextField` paints an opaque fill while focused that
/// covers the glass capsule drawn behind it. `.background(Color.clear)`,
/// overlay reordering and a global `UITextField.appearance()
/// .backgroundColor` all fail to remove it. A `UITextField` owned
/// directly honours `backgroundColor`, since nothing renders on top.
///
/// `@FocusState` cannot cross a `UIViewRepresentable`, so focus is a
/// plain `Bool` binding driven through `becomeFirstResponder`/
/// `resignFirstResponder`, with the delegate reporting user-initiated
/// changes back so the flag never goes stale (e.g. keyboard dismissed
/// by a swipe).
struct GlassSearchTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    @Binding var isFocused: Bool
    /// Return-key handler; `nil` just dismisses the keyboard.
    var onSubmit: (() -> Void)? = nil
    var textAlignment: NSTextAlignment = .natural
    var font: UIFont = .preferredFont(forTextStyle: .body)

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.backgroundColor = .clear
        field.borderStyle = .none
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.returnKeyType = .search
        field.clearButtonMode = .never
        field.font = font
        field.textAlignment = textAlignment
        field.adjustsFontForContentSizeCategory = true
        // Explicit so a theme change cannot leave the field unstyled.
        field.textColor = .label
        field.tintColor = .tintColor
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        // Let the capsule set the width; otherwise the field's intrinsic
        // content size fights the HStack and the capsule collapses around short
        // text.
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.secondaryLabel]
        )
        // Guarded both ways: calling these unconditionally on every update
        // would re-raise a keyboard the user just dismissed.
        if isFocused, !field.isFirstResponder {
            field.becomeFirstResponder()
        } else if !isFocused, field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: GlassSearchTextField

        init(parent: GlassSearchTextField) { self.parent = parent }

        @objc func editingChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            if !parent.isFocused { parent.isFocused = true }
        }


        func textFieldDidEndEditing(_ field: UITextField) {
            if parent.isFocused { parent.isFocused = false }
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            parent.onSubmit?()
            field.resignFirstResponder()
            return true
        }
    }
}
#endif
