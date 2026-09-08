import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit
#if canImport(VisionKit)
import VisionKit
#endif

/// A fullscreen image the way Apollo's viewer zooms it: a `UIScrollView`
/// doing the pinch, so the zoom tracks the fingers' midpoint, rubber-bands
/// past its limits, pans with momentum and settles on the system's own
/// curves. Double-tap zooms to the tapped point. A single tap and a
/// vertical swipe at the fitted size go back to the pager (chrome, dismiss
/// or comments), since this view sits over the page and takes its touches.
struct ZoomableImageView: UIViewRepresentable {
    let url: URL
    var liveText: Bool
    var onSingleTap: (() -> Void)?
    var onVerticalSwipe: ((CGFloat, CGFloat) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ZoomingScrollView {
        let view = ZoomingScrollView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: ZoomingScrollView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        context.coordinator.onVerticalSwipe = onVerticalSwipe
        view.hostsOwnSwipe = onVerticalSwipe != nil
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        let liveText = liveText
        Task {
            guard let data = await MediaBytes.data(for: url), let image = UIImage(data: data) else { return }
            await MainActor.run { view.setImage(image) }
            #if canImport(VisionKit)
            guard liveText, ImageAnalyzer.isSupported else { return }
            let analysis = try? await ImageAnalyzer().analyze(image, configuration: .init([.text]))
            await MainActor.run { view.setLiveText(analysis) }
            #endif
        }
    }

    final class Coordinator {
        var loadedURL: URL?
        /// The GIF player hosted in `ZoomableGIFView`.
        var gifHost: UIHostingController<AnyView>?
        var onSingleTap: (() -> Void)?
        var onVerticalSwipe: ((CGFloat, CGFloat) -> Void)?
    }
}

final class ZoomingScrollView: UIScrollView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    weak var coordinator: ZoomableImageView.Coordinator?
    /// Whether any image on screen is zoomed in, so viewer-level drags
    /// (swipe to dismiss, swipe for comments) leave its pan alone.
    @MainActor static var isZoomedOnScreen = false
    /// Double-tap, for a viewer's own single tap to wait on.
    let doubleTap = UITapGestureRecognizer()
    /// Off where the viewer runs its own vertical swipe above the pager.
    var hostsOwnSwipe = true { didSet { updatePanning() } }
    private let imageView = UIImageView()
    /// What zooms: the image view, or hosted content (`setContent`).
    private var zoomView: UIView { hostedView ?? imageView }
    private var hostedView: UIView?
    /// The content's own size (its aspect, for hosted content).
    private var naturalSize: CGSize?
    private var fittedForSize: CGSize = .zero
    private let swipe = UIPanGestureRecognizer()
    #if canImport(VisionKit)
    private var liveTextInteraction: AnyObject?
    #endif

    init() {
        super.init(frame: .zero)
        delegate = self
        backgroundColor = .clear
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        decelerationRate = .fast
        contentInsetAdjustmentBehavior = .never
        bouncesZoom = true
        minimumZoomScale = 1
        maximumZoomScale = 5
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        addSubview(imageView)

        doubleTap.addTarget(self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(singleTapped))
        singleTap.require(toFail: doubleTap)
        singleTap.delegate = self
        addGestureRecognizer(singleTap)

        swipe.addTarget(self, action: #selector(swiped(_:)))
        swipe.delegate = self
        addGestureRecognizer(swipe)
        updatePanning()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setImage(_ image: UIImage) {
        imageView.image = image
        naturalSize = image.size
        fittedForSize = .zero
        setNeedsLayout()
    }

    /// Zooms `view` (a GIF player) instead of an image, at `aspect`
    /// (height over width).
    func setContent(_ view: UIView, aspect: CGFloat) {
        if hostedView !== view {
            hostedView?.removeFromSuperview()
            imageView.removeFromSuperview()
            hostedView = view
            addSubview(view)
        }
        let size = CGSize(width: 1000, height: 1000 * aspect)
        guard naturalSize != size else { return }
        naturalSize = size
        fittedForSize = .zero
        setNeedsLayout()
    }

    #if canImport(VisionKit)
    func setLiveText(_ analysis: ImageAnalysis?) {
        guard let analysis else { return }
        let interaction = (liveTextInteraction as? ImageAnalysisInteraction) ?? {
            let new = ImageAnalysisInteraction()
            imageView.addInteraction(new)
            liveTextInteraction = new
            return new
        }()
        interaction.analysis = analysis
        interaction.preferredInteractionTypes = .textSelection
    }
    #endif

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let natural = naturalSize, natural.width > 0, natural.height > 0,
              bounds.width > 0, bounds.height > 0 else { return }
        if fittedForSize != bounds.size {
            // The fitted frame at 1x; zooming scales it from here.
            fittedForSize = bounds.size
            setZoomScale(1, animated: false)
            let fit = min(bounds.width / natural.width, bounds.height / natural.height)
            // Up to an image's own pixels, and at least 5x.
            let scale = hostedView == nil ? (imageView.image?.scale ?? 1) : 1
            maximumZoomScale = hostedView == nil ? max(5, scale / (fit * UIScreen.main.scale)) : 5
            zoomView.frame = CGRect(x: 0, y: 0, width: natural.width * fit, height: natural.height * fit)
            contentSize = zoomView.frame.size
        }
        center(zoomView)
    }

    /// Keeps the image centred while it's smaller than the screen.
    private func center(_ view: UIView) {
        let x = max(0, (bounds.width - contentSize.width) / 2)
        let y = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil, zoomScale > minimumZoomScale + 0.01 { Self.isZoomedOnScreen = false }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        ZoomingScrollView.reservePinch(from: self)
    }

    /// Pages with one finger only, in any pager this sits in: the pager's
    /// pan otherwise takes a two-finger pinch that drifts sideways and
    /// pages the album instead of zooming.
    static func reservePinch(from view: UIView) {
        var candidate = view.superview
        while let current = candidate {
            if let pager = current as? UIScrollView, pager.isPagingEnabled {
                pager.panGestureRecognizer.maximumNumberOfTouches = 1
            }
            candidate = current.superview
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { zoomView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        center(zoomView)
        updatePanning()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        updatePanning()
    }

    /// At the fitted size the scroll view doesn't pan, so a horizontal drag
    /// pages the gallery and a vertical one is the pager's swipe.
    private func updatePanning() {
        let zoomed = zoomScale > minimumZoomScale + 0.01
        panGestureRecognizer.isEnabled = zoomed
        swipe.isEnabled = !zoomed && hostsOwnSwipe
        if window != nil { Self.isZoomedOnScreen = zoomed }
    }

    @objc private func doubleTapped(_ tap: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale + 0.01 {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = tap.location(in: zoomView)
            let scale = min(2.5, maximumZoomScale)
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                            width: size.width, height: size.height), animated: true)
        }
    }

    @objc private func singleTapped() { coordinator?.onSingleTap?() }

    @objc private func swiped(_ pan: UIPanGestureRecognizer) {
        guard pan.state == .ended else { return }
        let t = pan.translation(in: self)
        coordinator?.onVerticalSwipe?(t.y, t.x)
    }

    /// Taps alongside the SwiftUI gestures hosting the pager, which would
    /// otherwise win them.
    func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        recognizer is UITapGestureRecognizer && other.view !== self
    }

    /// The swipe only claims mostly-vertical drags, leaving horizontal ones
    /// to the pager.
    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard recognizer === swipe else { return super.gestureRecognizerShouldBegin(recognizer) }
        let v = swipe.velocity(in: self)
        return swipe.numberOfTouches < 2 && abs(v.y) > abs(v.x)
    }
}

/// A fullscreen GIF the same way: its player hosted inside the zoom view,
/// so it pinches, pans and double-taps like an image.
struct ZoomableGIFView: UIViewRepresentable {
    let url: URL
    var isPlaying: Bool
    var onSingleTap: (() -> Void)?
    var onVerticalSwipe: ((CGFloat, CGFloat) -> Void)?
    /// The GIF's height over width, once known.
    var onRatio: (CGFloat) -> Void = { _ in }

    func makeCoordinator() -> ZoomableImageView.Coordinator { ZoomableImageView.Coordinator() }

    func makeUIView(context: Context) -> ZoomingScrollView {
        let view = ZoomingScrollView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: ZoomingScrollView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        context.coordinator.onVerticalSwipe = onVerticalSwipe
        view.hostsOwnSwipe = onVerticalSwipe != nil
        let onRatio = onRatio
        let surface = AnyView(GIFSurface(url: url, isPlaying: isPlaying, onRatio: { [weak view] ratio in
            onRatio(ratio)
            guard let view, let host = context.coordinator.gifHost else { return }
            DispatchQueue.main.async { view.setContent(host.view, aspect: ratio) }
        }))
        if let host = context.coordinator.gifHost {
            host.rootView = surface
        } else {
            let host = UIHostingController(rootView: surface)
            host.view.backgroundColor = .clear
            host.view.isUserInteractionEnabled = false
            context.coordinator.gifHost = host
            view.setContent(host.view, aspect: 9.0 / 16.0)
        }
    }
}
#endif
