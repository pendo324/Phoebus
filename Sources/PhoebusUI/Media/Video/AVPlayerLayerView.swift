import SwiftUI
import AVKit
import UIKit

/// A bare `AVPlayerLayer` with no playback chrome. SwiftUI's `VideoPlayer`
/// draws AVKit's controls over Apollo's own control panel, so inline
/// players use a plain layer.
struct AVPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    /// `.resizeAspect` letterboxes, matching `VideoPlayer`'s default
    /// so swapping this in does not change how a clip is framed.
    var videoGravity: AVLayerVideoGravity = .resizeAspect

    /// Tap routing, when the caller wants it handled here rather than by
    /// a SwiftUI gesture. SwiftUI gesture arbitration ranks an ancestor's
    /// `.highPriorityGesture` above any plain content gesture, so a
    /// `UITapGestureRecognizer` on the actual video view sees the touch
    /// first in UIKit, before SwiftUI's recognizers can claim it.
    var onTapAtPoint: ((CGPoint, CGSize) -> Void)?

    /// Hands the on-screen layer out, for system PiP, which is driven by
    /// a layer rather than a player.
    var onLayer: ((AVPlayerLayer) -> Void)?

    func makeUIView(context: Context) -> PlayerLayerBackedView {
        let view = PlayerLayerBackedView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = videoGravity
        view.backgroundColor = .black
        // Interactive ONLY when this view owns the tap. Otherwise it
        // draws only and every gesture belongs to SwiftUI: a plain
        // interactive UIView inside a `UIViewRepresentable` consumes
        // the touch, and an `.onTapGesture` on an ancestor never sees
        // it.
        if onTapAtPoint != nil {
            view.isUserInteractionEnabled = true
            let recognizer = UITapGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handleTap(_:)))
            // Recognize alongside every other recognizer and never
            // require another to fail first, or an ancestor's row/pager
            // gesture can pre-empt this one and the tap never fires.
            recognizer.delegate = context.coordinator
            // Must not wait on SwiftUI's own recognizers. cancelsTouchesInView
            // is false so the row's own tap still works outside the media.
            recognizer.cancelsTouchesInView = false
            view.addGestureRecognizer(recognizer)
            context.coordinator.recognizer = recognizer
        } else {
            view.isUserInteractionEnabled = false
        }
        context.coordinator.onTapAtPoint = onTapAtPoint
        onLayer?(view.playerLayer)
        return view
    }

    func updateUIView(_ view: PlayerLayerBackedView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
        view.playerLayer.videoGravity = videoGravity
        // Re-captured every update: the closure holds SwiftUI state
        // that goes stale otherwise, which would leave the recognizer
        // calling into an old view's bindings.
        context.coordinator.onTapAtPoint = onTapAtPoint
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTapAtPoint: ((CGPoint, CGSize) -> Void)?
        var recognizer: UITapGestureRecognizer?

        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            guard let view = sender.view else { return }
            onTapAtPoint?(sender.location(in: view), view.bounds.size)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool { false }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRequireFailureOf other: UIGestureRecognizer
        ) -> Bool { false }
    }

    /// Backing the view with `AVPlayerLayer` itself, rather than adding
    /// one as a sublayer, is what keeps the layer sized to the view.
    /// A sublayer needs manual frame updates and ends up stretched or
    /// clipped whenever the view resizes.
    final class PlayerLayerBackedView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
