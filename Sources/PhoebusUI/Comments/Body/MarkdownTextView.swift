import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit

/// Drives a `MarkdownTextView` from outside it: the Quick Bar applies its
/// actions to the real selection, as Apollo's composer does.
@MainActor
public final class MarkdownEditorController: ObservableObject {
    fileprivate weak var textView: KeepFocusTextView?
    fileprivate var onTextChange: ((String) -> Void)?

    public var hasSelection: Bool { (textView?.selectedRange.length ?? 0) > 0 }

    /// Applies `action` to the selection; false when it can't apply.
    @discardableResult
    public func apply(_ action: MarkdownAction) -> Bool {
        guard let textView,
              let edit = MarkdownFormatting.apply(action, to: textView.text ?? "", selection: textView.selectedRange)
        else { return false }
        set(edit.text, selection: edit.selection)
        return true
    }

    /// Inserts at the cursor, replacing any selection.
    public func insert(_ string: String) {
        guard let textView else { return }
        let ns = (textView.text ?? "") as NSString
        let range = textView.selectedRange
        set(ns.replacingCharacters(in: range, with: string),
            selection: NSRange(location: range.location + (string as NSString).length, length: 0))
    }

    /// Apollo's full-screen composer: focused on appear, keyboard held.
    public let locksFocus: Bool

    public init(locksFocus: Bool = false) { self.locksFocus = locksFocus }

    /// Lets the keyboard go while a sheet is over the editor, and takes it
    /// back after.
    public func presenting(_ presenting: Bool) {
        guard locksFocus, let textView else { return }
        textView.keepsFocus = !presenting
        if !presenting { textView.becomeFirstResponder() }
    }

    /// Before the editor closes.
    public func release() {
        textView?.keepsFocus = false
    }

    private func set(_ text: String, selection: NSRange) {
        guard let textView else { return }
        textView.text = text
        textView.selectedRange = selection
        textView.scrollRangeToVisible(selection)
        onTextChange?(text)
    }
}

/// Apollo's composer text area: a `UITextView`, focused as it appears,
/// whose keyboard stays up for as long as the editor is on screen.
public struct MarkdownTextView: UIViewRepresentable {
    @Binding var text: String
    let controller: MarkdownEditorController
    var font: UIFont = .preferredFont(forTextStyle: .body)

    public init(text: Binding<String>, controller: MarkdownEditorController) {
        _text = text
        self.controller = controller
    }

    public func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    public func makeUIView(context: Context) -> UITextView {
        let view = KeepFocusTextView()
        view.delegate = context.coordinator
        view.font = font
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.text = text
        view.keyboardDismissMode = .none
        view.alwaysBounceVertical = true
        view.textContainerInset = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        view.keepsFocus = controller.locksFocus
        controller.textView = view
        controller.onTextChange = { [weak coordinator = context.coordinator] in coordinator?.text.wrappedValue = $0 }
        return view
    }

    public func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.text = $text
        if view.text != text { view.text = text }
    }

    public final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        public func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }
    }
}

/// Takes the keyboard when it joins a window and won't hand it back while
/// `keepsFocus` is set: there is no way to lower it but to close the editor.
final class KeepFocusTextView: UITextView {
    var keepsFocus = true

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, keepsFocus else { return }
        // After the sheet's presentation settles, or the keyboard is
        // dropped again during the transition.
        DispatchQueue.main.async { [weak self] in self?.becomeFirstResponder() }
    }

    override var canResignFirstResponder: Bool { !keepsFocus || window == nil }
}
#endif
