#if canImport(UIKit)
import UIKit

/// Never the hit-test result itself (touches pass through), but hosts
/// recognizers on an ancestor, where UIKit consults them: a recognizer is
/// offered a touch only if it belongs to the hit view or one of its
/// ancestors. Used by the gallery viewer's swipe catcher and the video
/// scrubber.
final class AncestorGestureHost: UIView {
    var recognizers: [UIGestureRecognizer] = []
    private weak var host: UIView?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        // The topmost ancestor below the window: the screen's hosting view, where
        // a pager's paging pan lives too.
        var candidate: UIView = self
        while let parent = candidate.superview, !(parent is UIWindow) {
            candidate = parent
        }
        guard candidate !== host else { return }
        detach()
        host = candidate
        for recognizer in recognizers {
            candidate.addGestureRecognizer(recognizer)
        }
    }

    func detach() {
        guard let host else { return }
        for recognizer in recognizers {
            host.removeGestureRecognizer(recognizer)
        }
        self.host = nil
    }
}
#endif
