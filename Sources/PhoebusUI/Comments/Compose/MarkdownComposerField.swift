import SwiftUI
import PhoebusCore

/// The markdown text area with Apollo's Quick Bar under it, for every
/// compose surface. Full-screen (the "New Comment" modal) it fills the
/// space, starts focused and keeps the keyboard up while it's on screen,
/// with the Quick Bar pinned above the keyboard; inline it is a few
/// lines tall.
public struct MarkdownComposerField: View {
    @Binding var text: String
    let placeholder: String
    let lineLimit: ClosedRange<Int>
    let fillsAvailableSpace: Bool
    /// The Quick Bar's "Add photos".
    var onAddPhoto: (() -> Void)?
    private let externalEditor: MarkdownEditorController?
    @StateObject private var ownEditor: MarkdownEditorController
    private var editor: MarkdownEditorController { externalEditor ?? ownEditor }

    public init(text: Binding<String>, placeholder: String, lineLimit: ClosedRange<Int> = 3...6,
                fillsAvailableSpace: Bool = false, editor: MarkdownEditorController? = nil,
                onAddPhoto: (() -> Void)? = nil) {
        self._text = text
        self.placeholder = placeholder
        self.lineLimit = lineLimit
        self.fillsAvailableSpace = fillsAvailableSpace
        self.externalEditor = editor
        _ownEditor = StateObject(wrappedValue: MarkdownEditorController(locksFocus: fillsAvailableSpace))
        self.onAddPhoto = onAddPhoto
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MarkdownTextView(text: $text, controller: editor)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty, !placeholder.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 12)
                            .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: fillsAvailableSpace ? nil : CGFloat(lineLimit.lowerBound) * 22 + 24,
                       maxHeight: fillsAvailableSpace ? .infinity : CGFloat(lineLimit.upperBound) * 22 + 24)
            QuickBarToolbar(text: $text, editor: editor, onAddPhoto: onAddPhoto)
        }
    }
}
