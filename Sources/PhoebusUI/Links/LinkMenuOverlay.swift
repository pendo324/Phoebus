import SwiftUI
#if canImport(UIKit)
import UIKit

/// The system's own link long-press over a link card: iOS's link preview
/// ("Tap to show preview", the host and full address) with Apollo's
/// actions, Copy Link / Share… / Open in Safari.
///
/// That preview belongs to link text, so this is an invisible text view
/// whose whole area is one link, laid over the card. iOS 17's text-item
/// menu API keeps the system preview while replacing the actions. A tap
/// is the text item's primary action, handed back to `onTap`.
struct LinkMenuOverlay: UIViewRepresentable {
    let url: URL
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(url: url, onTap: onTap) }

    func makeUIView(context: Context) -> LinkFillTextView {
        let view = LinkFillTextView()
        view.delegate = context.coordinator
        view.url = url
        return view
    }

    /// Exactly the card's size: the text inside must never size the view,
    /// or filling it would grow it and refill it forever.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: LinkFillTextView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    func updateUIView(_ view: LinkFillTextView, context: Context) {
        context.coordinator.url = url
        context.coordinator.onTap = onTap
        if view.url != url { view.url = url }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var url: URL
        var onTap: () -> Void

        init(url: URL, onTap: @escaping () -> Void) {
            self.url = url
            self.onTap = onTap
        }

        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem,
                      defaultAction: UIAction) -> UIAction? {
            UIAction { [weak self] _ in self?.onTap() }
        }

        func textView(_ textView: UITextView, menuConfigurationFor textItem: UITextItem,
                      defaultMenu: UIMenu) -> UITextItem.MenuConfiguration? {
            let url = self.url
            let copy = UIAction(title: "Copy Link", image: UIImage(systemName: "doc.on.doc")) { _ in
                PasteboardHelper.copy(url: url)
            }
            let share = UIAction(title: "Share…", image: UIImage(systemName: "square.and.arrow.up")) { [weak textView] _ in
                var presenter = textView?.window?.rootViewController
                while let next = presenter?.presentedViewController { presenter = next }
                let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                sheet.popoverPresentationController?.sourceView = textView
                presenter?.present(sheet, animated: true)
            }
            let safari = UIAction(title: "Open in Safari", image: UIImage(systemName: "safari")) { _ in
                UIApplication.shared.open(url)
            }
            return UITextItem.MenuConfiguration(preview: .default, menu: UIMenu(children: [copy, share, safari]))
        }

        /// Never leaves a selection behind: the text is only there to be
        /// a link.
        func textViewDidChangeSelection(_ textView: UITextView) {
            if textView.selectedRange.length > 0 {
                textView.selectedRange = NSRange(location: 0, length: 0)
            }
        }
    }
}

/// A transparent text view filled edge to edge with one link, so a press
/// anywhere on it lands on the link.
final class LinkFillTextView: UITextView {
    var url: URL? { didSet { fill() } }
    private var filledSize: CGSize = .zero

    init() {
        super.init(frame: .zero, textContainer: nil)
        backgroundColor = .clear
        isEditable = false
        // Links in a text view only take presses while it is selectable.
        isSelectable = true
        isScrollEnabled = false
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        // The link draws nothing: the card underneath is the visual.
        linkTextAttributes = [.foregroundColor: UIColor.clear]
        tintColor = .clear
        accessibilityElementsHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { size }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = CGSize(width: bounds.width.rounded(), height: bounds.height.rounded())
        if size != filledSize { fill() }
    }

    /// Lines of non-breaking spaces until the text covers the bounds.
    private func fill() {
        guard let url, bounds.width > 0, bounds.height > 0 else { return }
        filledSize = CGSize(width: bounds.width.rounded(), height: bounds.height.rounded())
        let font = UIFont.systemFont(ofSize: 20)
        let space = "\u{00A0}"
        let spaceWidth = max((space as NSString).size(withAttributes: [.font: font]).width, 1)
        let perLine = Int(bounds.width / spaceWidth) + 1
        let lines = Int(bounds.height / font.lineHeight) + 1
        let line = String(repeating: space, count: perLine)
        let text = Array(repeating: line, count: lines).joined(separator: "\n")
        attributedText = NSAttributedString(string: text, attributes: [.font: font, .link: url])
    }

    // Selection handles and the edit menu never appear.
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool { false }
}
#endif
