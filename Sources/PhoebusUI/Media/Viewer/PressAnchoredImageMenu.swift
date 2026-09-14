#if canImport(UIKit)
import SwiftUI
import UIKit
import PhoebusCore

/// The fullscreen image viewer's long-press menu: Copy Image, Save Image,
/// Save All Media (albums) and Share, in Reborn's order. It opens where the
/// finger pressed (Reborn #1254) using a 1pt clear preview centred on the press.
///
/// A zero-size probe hands a `UIContextMenuInteraction` to the page's own
/// UIKit container, the pattern `AncestorGestureHost` uses, so the image's
/// zoom, pan and double-tap keep working.
struct PressAnchoredImageMenu: UIViewRepresentable {
    let urls: [URL]
    let index: Int
    /// A GIF: Copy GIF / Save GIF, saved as the GIF.
    var isGIF = false

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.coordinator = context.coordinator
        context.coordinator.urls = urls
        context.coordinator.index = index
        context.coordinator.isGIF = isGIF
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        context.coordinator.urls = urls
        context.coordinator.index = index
        context.coordinator.isGIF = isGIF
    }

    static func dismantleUIView(_ view: ProbeView, coordinator: Coordinator) {
        view.detach()
    }

    final class ProbeView: UIView {
        weak var coordinator: Coordinator?
        private weak var host: UIView?
        private var interaction: UIContextMenuInteraction?

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, host == nil, let coordinator else { return }
            // The page's own cell in the pager (one interaction per page),
            // else the screen's hosting view; either way the menu only
            // answers presses on this image (`probe`).
            var host: UIView = self
            var candidate: UIView? = superview
            while let current = candidate, !(current is UIWindow) {
                if let cell = current as? UICollectionViewCell { host = cell.contentView; break }
                host = current
                candidate = current.superview
            }
            coordinator.probe = self
            let interaction = UIContextMenuInteraction(delegate: coordinator)
            host.addInteraction(interaction)
            self.host = host
            self.interaction = interaction
        }

        func detach() {
            if let interaction { host?.removeInteraction(interaction) }
            interaction = nil
        }
    }

    final class Coordinator: NSObject, UIContextMenuInteractionDelegate {
        var urls: [URL] = []
        var index = 0
        var isGIF = false
        weak var probe: UIView?
        private var pressLocation: CGPoint?

        private var url: URL? { urls.isEmpty ? nil : urls[min(index, urls.count - 1)] }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
            guard let url, let probe, let source = interaction.view,
                  probe.convert(probe.bounds, to: source).contains(location) else { return nil }
            pressLocation = location
            let urls = urls
            let isGIF = isGIF
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                var actions: [UIMenuElement] = [
                    UIAction(title: isGIF ? "Copy GIF" : "Copy Image", image: UIImage(systemName: "doc.on.doc")) { _ in
                        Task {
                            if let data = await MediaBytes.data(for: url) {
                                PasteboardHelper.copyImage(data)
                            }
                        }
                    },
                    UIAction(title: isGIF ? "Save GIF" : "Save Image", image: UIImage(systemName: "square.and.arrow.down")) { _ in
                        SaveAllMediaJob.shared.start([isGIF ? .gif(url) : .image(url)])
                    },
                ]
                if urls.count > 1 {
                    actions.append(UIAction(title: SaveAllMediaSummary.menuTitle,
                                            image: UIImage(systemName: SaveAllMediaSummary.menuSymbol)) { _ in
                        SaveAllMediaJob.shared.start(urls.map { .image($0) })
                    })
                }
                actions.append(UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { [weak interaction] _ in
                    Self.share(url, from: interaction?.view)
                })
                return UIMenu(title: "", children: actions)
            }
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
            pressPreview(interaction)
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
            pressPreview(interaction)
        }

        /// A 1pt clear preview at the press, so the menu opens there.
        private func pressPreview(_ interaction: UIContextMenuInteraction) -> UITargetedPreview? {
            guard let source = interaction.view, source.window != nil, let pressLocation else { return nil }
            let anchor = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
            anchor.isUserInteractionEnabled = false
            let parameters = UIPreviewParameters()
            parameters.backgroundColor = .clear
            parameters.visiblePath = UIBezierPath(rect: anchor.bounds)
            return UITargetedPreview(view: anchor, parameters: parameters,
                                     target: UIPreviewTarget(container: source, center: pressLocation))
        }

        private static func share(_ url: URL, from view: UIView?) {
            var presenter = view?.window?.rootViewController
            while let next = presenter?.presentedViewController { presenter = next }
            let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            sheet.popoverPresentationController?.sourceView = view
            presenter?.present(sheet, animated: true)
        }
    }
}
#endif
