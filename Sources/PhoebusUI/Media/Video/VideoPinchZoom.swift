#if canImport(UIKit)
import SwiftUI
import UIKit

/// Pinch-to-zoom on a fullscreen video, as Apollo's viewer zooms a video
/// like an image: the picture scales about the fingers, a drag pans it
/// while zoomed, and letting go below the fitted size settles back to it.
@MainActor
final class VideoZoom {
    /// The view drawing the video; only it scales, not the controls.
    weak var target: UIView?
    private(set) var scale: CGFloat = 1
    private var offset: CGPoint = .zero
    static let maximumScale: CGFloat = 5

    var isZoomed: Bool { scale > 1.01 }

    /// Scales by `factor` about `point` (in the target's superview), then
    /// follows the fingers' drift.
    func pinch(by factor: CGFloat, at point: CGPoint, drift: CGPoint) {
        guard let target else { return }
        let next = min(max(scale * factor, 0.5), Self.maximumScale * 1.5)
        let applied = next / scale
        let center = target.center
        offset = CGPoint(x: (1 - applied) * (point.x - center.x) + applied * offset.x + drift.x,
                         y: (1 - applied) * (point.y - center.y) + applied * offset.y + drift.y)
        scale = next
        apply()
    }

    func pan(by delta: CGPoint) {
        offset = CGPoint(x: offset.x + delta.x, y: offset.y + delta.y)
        apply()
    }

    /// Back inside the limits: the fitted size at most zoomed out, the
    /// picture's edges never pulled in past the screen's.
    func settle() {
        guard let target else { return }
        if scale <= 1 {
            scale = 1
            offset = .zero
        } else {
            scale = min(scale, Self.maximumScale)
            let maxX = (scale - 1) * target.bounds.width / 2
            let maxY = (scale - 1) * target.bounds.height / 2
            offset = CGPoint(x: min(max(offset.x, -maxX), maxX), y: min(max(offset.y, -maxY), maxY))
        }
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.apply()
        }
    }

    func reset() {
        scale = 1
        offset = .zero
        apply()
    }

    private func apply() {
        target?.transform = CGAffineTransform(translationX: offset.x, y: offset.y).scaledBy(x: scale, y: scale)
        ZoomingScrollView.isZoomedOnScreen = isZoomed
        // The pager stays put while the picture is zoomed, as with an image.
        var candidate = target?.superview
        while let current = candidate {
            if let pager = current as? UIScrollView, pager.isPagingEnabled { pager.isScrollEnabled = !isZoomed }
            candidate = current.superview
        }
    }
}

/// The pinch and the zoomed pan for one video page. The recognizers live
/// on the screen's hosting view (`AncestorGestureHost`), since the
/// player's overlays take the touches on the video itself, and act only
/// on gestures that start over this page.
struct VideoPinchCatcher: UIViewRepresentable {
    let zoom: VideoZoom

    func makeUIView(context: Context) -> UIView {
        let view = AncestorGestureHost()
        view.backgroundColor = .clear
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinched(_:)))
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.panned(_:)))
        pan.maximumNumberOfTouches = 1
        for recognizer in [pinch, pan] as [UIGestureRecognizer] {
            recognizer.delegate = context.coordinator
            recognizer.cancelsTouchesInView = false
        }
        view.recognizers = [pinch, pan]
        context.coordinator.regionView = view
        context.coordinator.pan = pan
        context.coordinator.zoom = zoom
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.zoom = zoom
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        coordinator.zoom?.reset()
        (view as? AncestorGestureHost)?.detach()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var zoom: VideoZoom?
        weak var regionView: UIView?
        weak var pan: UIPanGestureRecognizer?
        private var lastPoint: CGPoint?

        @objc func pinched(_ pinch: UIPinchGestureRecognizer) {
            guard let zoom, let space = zoom.target?.superview else { return }
            switch pinch.state {
            case .began:
                lastPoint = pinch.location(in: space)
                pinch.scale = 1
            case .changed:
                // A lifted finger moves the midpoint; skip that frame's drift.
                guard pinch.numberOfTouches == 2 else { lastPoint = nil; return }
                let point = pinch.location(in: space)
                let drift = lastPoint.map { CGPoint(x: point.x - $0.x, y: point.y - $0.y) } ?? .zero
                zoom.pinch(by: pinch.scale, at: point, drift: drift)
                pinch.scale = 1
                lastPoint = point
            default:
                lastPoint = nil
                zoom.settle()
            }
        }

        @objc func panned(_ pan: UIPanGestureRecognizer) {
            guard let zoom, let space = zoom.target?.superview else { return }
            switch pan.state {
            case .changed:
                zoom.pan(by: pan.translation(in: space))
                pan.setTranslation(.zero, in: space)
            case .ended, .cancelled:
                zoom.settle()
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            recognizer !== pan || zoom?.isZoomed == true
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        /// Only touches over this page: every page's recognizers share the
        /// screen's hosting view.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let region = regionView, let window = region.window else { return false }
            return region.convert(region.bounds, to: window).contains(touch.location(in: window))
        }
    }
}
#endif
