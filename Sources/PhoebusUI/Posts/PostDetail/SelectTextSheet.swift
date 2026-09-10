import SwiftUI

/// Apollo's "Select Text" sheet, offered on both the post and comment "•••" menus.
/// A post's body is SwiftUI `Text`, which cannot be selected on iOS.
///
/// A read-only `UITextView` is used rather than `.textSelection(.enabled)`, which
/// gives no selection handles on iOS: the user can copy the whole text but cannot
/// select a range.
public struct SelectTextSheet: View {
    let title: String
    let body_: String
    let onDone: () -> Void

    public init(title: String, body: String, onDone: @escaping () -> Void) {
        self.title = title
        self.body_ = body
        self.onDone = onDone
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SelectableTextView(text: title.isEmpty ? body_ : title + "\n\n" + body_)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
            }
            .navigationTitle("Select Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDone() }
                }
            }
        }
        .accessibilityIdentifier("selectText.sheet")
    }
}

/// A read-only, selectable text view. A non-editable `UITextView` is the only
/// option that gives selection handles plus the system's Copy/Look Up/Translate
/// menu.
struct SelectableTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        // Selectable but not editable: this is the combination that
        // yields drag handles on a read-only view.
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.text = text
    }

    /// Wraps to the offered width; left to itself a non-scrolling text
    /// view takes its one-line width and runs off both edges.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: fitted.height)
    }
}
