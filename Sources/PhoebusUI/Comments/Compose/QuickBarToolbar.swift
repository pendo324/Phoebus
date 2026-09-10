import SwiftUI
import PhoebusCore

/// Apollo's "Quick Bar" over the keyboard, with Reborn's GIF chip after the
/// photo button: Add photos, GIF, Insert link, Bold text, Italicize text,
/// Enter subreddit, Enter user, More actions. Glyphs are Apollo's own, in the
/// accent. The ••• menu follows Apollo's order: Preview, Superscript, Quote,
/// Spoiler, Strikethrough, Header, Unordered List, Ordered List, Horizontal
/// Line, Code, Text Faces, SpongeText. Formatting applies to the selection
/// (`MarkdownFormatting`).
public struct QuickBarToolbar: View {
    @Binding var text: String
    @ObservedObject var editor: MarkdownEditorController
    var onAddPhoto: (() -> Void)?
    @State private var showingTextFaces = false
    @State private var showingGiphyPicker = false
    @State private var showingPreview = false
    @State private var showingSpongeAlert = false

    public init(text: Binding<String>, editor: MarkdownEditorController, onAddPhoto: (() -> Void)? = nil) {
        self._text = text
        self.editor = editor
        self.onAddPhoto = onAddPhoto
    }

    public var body: some View {
        HStack(spacing: 0) {
            glyph("option-photo", "Add photos") { onAddPhoto?() }
            Button { showingGiphyPicker = true } label: {
                Text("GIF")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 3)
                    .frame(height: 15)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(lineWidth: 1.2))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .accessibilityLabel("GIF")
            .accessibilityIdentifier("quickbar.gifButton")
            glyph("option-link", "Insert link") { editor.apply(.link) }
            glyph("option-bold", "Bold text") { editor.apply(.bold) }
            glyph("option-italic", "Italicize text") { editor.apply(.italic) }
            glyph("option-subreddit", "Enter subreddit") { editor.apply(.subreddit) }
            glyph("option-author", "Enter user") { editor.apply(.user) }
            Menu {
                menuRow("Preview", "option-preview") { present { showingPreview = true } }
                menuRow("Superscript", "option-superscript") { editor.apply(.superscript) }
                menuRow("Quote", "option-quote") { editor.apply(.quote) }
                menuRow("Spoiler", "option-spoiler") { editor.apply(.spoiler) }
                menuRow("Strikethrough", "option-strikethrough") { editor.apply(.strikethrough) }
                menuRow("Header", "option-header") { editor.apply(.header) }
                menuRow("Unordered List", "option-unordered-list") { editor.apply(.unorderedList) }
                menuRow("Ordered List", "option-ordered-list") { editor.apply(.orderedList) }
                menuRow("Horizontal Line", "option-horizontal-rule") { editor.apply(.horizontalRule) }
                menuRow("Code", "option-code") { editor.apply(.code) }
                menuRow("Text Faces", "option-text-faces") { present { showingTextFaces = true } }
                menuRow("SpongeText", "option-spongetext") {
                    if !editor.apply(.spongeText) { showingSpongeAlert = true }
                }
                .accessibilityIdentifier("quickBar.spongeText")
            } label: {
                StockIcon("option-more")
                    .foregroundStyle(Color.apolloAccent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            // Preview first even though the menu opens upwards, and its
            // rows in the label colour, as Apollo's.
            .menuOrder(.fixed)
            .tint(Color.primary)
            .accessibilityLabel("More actions")
        }
        .foregroundStyle(Color.apolloAccent)
        .frame(height: 46)
        .alert("SpongeText", isPresented: $showingSpongeAlert) {
            Button("OK") {}
        } message: {
            Text(SpongeText.noSelectionMessage)
        }
        .sheet(isPresented: $showingTextFaces, onDismiss: { editor.presenting(false) }) {
            TextFacesPickerScreen { face in editor.insert(face) }
        }
        .sheet(isPresented: $showingGiphyPicker, onDismiss: { editor.presenting(false) }) {
            // Reborn's own markdown token, expanded into the GIF on render.
            GiphyPickerScreen { gif in editor.insert("![gif](giphy|\(gif.id))") }
        }
        .sheet(isPresented: $showingPreview, onDismiss: { editor.presenting(false) }) {
            MarkdownPreviewSheet(text: text)
        }
        .onChange(of: showingGiphyPicker) { _, shown in if shown { editor.presenting(true) } }
    }

    private func present(_ show: () -> Void) {
        editor.presenting(true)
        show()
    }

    private func glyph(_ name: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            StockPNG.image(name)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    private func menuRow(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label { Text(title) } icon: { StockPNG.image(icon) }
        }
    }
}

/// The ••• menu's Preview: the comment as it will read.
struct MarkdownPreviewSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if text.isEmpty {
                        Text("Nothing to preview").foregroundStyle(.secondary)
                    } else {
                        InlineMediaBodyView(text)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayModeIfAvailable()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
