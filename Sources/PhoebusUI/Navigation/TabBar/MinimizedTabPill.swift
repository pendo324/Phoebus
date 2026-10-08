#if canImport(UIKit)
import UIKit
import os
import PhoebusCore

/// Tab bar hide styles, for `idevicesyslog` (subsystem com.pendo324.Phoebus,
/// category tabbar).
let tabBarLog = Logger(subsystem: "com.pendo324.Phoebus", category: "tabbar")

extension TabBarMinimizeStyle.Rect {
    init(_ rect: CGRect) { self.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height) }

    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    var text: String { String(format: "(%.0f,%.0f %.0fx%.0f)", x, y, width, height) }
}

/// Keeps the real tab bar out of sight while the pill stands in for it.
///
/// UIKit's tab bar controller writes the bar's alpha, touch and
/// accessibility state back during its own layout passes, so one write is
/// not enough: the bar's opacity is watched and corrected as it changes, and
/// everything is reasserted on a timer.
@MainActor
private final class HiddenBarGuard {
    private weak var bar: UITabBar?
    private var observation: NSKeyValueObservation?
    private var applying = false
    private var overrides = 0
    private var alpha: CGFloat = 1
    private var acceptsTouches = true

    func engage(_ bar: UITabBar) {
        guard self.bar !== bar else { return }
        disengage()
        self.bar = bar
        overrides = 0
        alpha = bar.alpha
        acceptsTouches = bar.isUserInteractionEnabled
        observation = bar.layer.observe(\.opacity, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.opacityChanged() }
        }
    }

    func hold(alpha: Double, acceptsTouches: Bool) {
        self.alpha = CGFloat(alpha)
        self.acceptsTouches = acceptsTouches
        apply()
    }

    func reassert() { apply() }

    /// The bar as UIKit left it.
    func disengage() {
        observation?.invalidate()
        observation = nil
        if let bar {
            bar.alpha = 1
            bar.isUserInteractionEnabled = true
            bar.accessibilityElementsHidden = false
        }
        bar = nil
    }

    private func opacityChanged() {
        guard !applying, let bar, abs(bar.alpha - alpha) > 0.001 else { return }
        overrides += 1
        if overrides <= 3 {
            tabBarLog.notice("bar alpha set to \(Double(bar.alpha)) behind our back (want \(Double(self.alpha))); reasserted, count=\(self.overrides)")
        }
        apply()
    }

    private func apply() {
        guard let bar else { return }
        applying = true
        defer { applying = false }
        if abs(bar.alpha - alpha) > 0.001 { bar.alpha = alpha }
        if bar.isUserInteractionEnabled != acceptsTouches { bar.isUserInteractionEnabled = acceptsTouches }
        if bar.accessibilityElementsHidden == acceptsTouches { bar.accessibilityElementsHidden = !acceptsTouches }
    }
}

/// The glass capsule that stands in for the tab bar while it is minimized.
private final class MinimizedPillView: UIView {
    private let glass: UIVisualEffectView
    private let label = UILabel()
    private let drawsGlass: Bool
    var onTap: () -> Void = {}

    var title = "" {
        didSet {
            label.text = title
            accessibilityLabel = title
        }
    }

    var titleOpacity: CGFloat {
        get { label.alpha }
        set { label.alpha = newValue }
    }

    init(font: UIFont) {
        let effect: UIVisualEffect
        if LiquidGlass.isEnabled, #available(iOS 26.0, *) {
            let glassEffect = UIGlassEffect()
            glassEffect.isInteractive = true
            effect = glassEffect
            drawsGlass = true
        } else {
            effect = UIBlurEffect(style: .systemChromeMaterial)
            drawsGlass = false
        }
        glass = UIVisualEffectView(effect: effect)
        super.init(frame: .zero)
        backgroundColor = .clear

        if drawsGlass, #available(iOS 26.0, *) {
            glass.cornerConfiguration = .capsule()
        } else {
            glass.clipsToBounds = true
            glass.layer.cornerCurve = .continuous
        }
        addSubview(glass)

        label.font = font
        label.textColor = .label
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.numberOfLines = 1
        label.alpha = 0
        label.isAccessibilityElement = false
        glass.contentView.addSubview(label)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = "Expand tab bar"
        accessibilityIdentifier = "tabBar.minimizedPill"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        label.frame = bounds.insetBy(dx: 18, dy: 0)
        if !drawsGlass { glass.layer.cornerRadius = bounds.height / 2 }
    }

    /// A tap is accepted this tall even though the pill is shorter.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let inset = max(0, (TabBarMinimizeStyle.minimumTouchHeight - bounds.height) / 2)
        return bounds.insetBy(dx: 0, dy: -inset).contains(point)
    }

    override func accessibilityActivate() -> Bool {
        onTap()
        return true
    }

    @objc private func tapped() { onTap() }
}

/// Reborn "Minimize" hide style (#1349): drives the collapse and reveal of
/// one tab bar through a glass pill.
///
/// The real bar is not resized. A capsule over it shrinks from the bar's glass
/// to a small centered pill naming the current tab while the bar fades away,
/// and the reverse on the way back. Tapping the pill asks for the bar back.
@MainActor
final class MinimizedTabPillController {
    private enum Phase { case idle, collapsing, collapsed, expanding }

    private weak var bar: UITabBar?
    private var pill: MinimizedPillView?
    private let hiddenBar = HiddenBarGuard()
    private var onTap: () -> Void = {}
    private let font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
        for: .systemFont(ofSize: 12, weight: .medium), maximumPointSize: 17)

    private var phase = Phase.idle
    private var collapsing = true
    /// 1 = the full bar, 0 = the compact pill. Briefly above 1 while the
    /// reveal settles.
    private var expansion = 1.0
    private var barFrame = TabBarMinimizeStyle.Rect.zero
    private var expanded = TabBarMinimizeStyle.Rect.zero
    private var safeAreaBottom = 0.0
    private var titleSize = CGSize.zero

    private var link: CADisplayLink?
    private var linkProxy: DisplayLinkProxy?
    private var generation = 0
    private var startedAt: CFTimeInterval = 0
    private var startOffset: TimeInterval = 0
    private var moveBegan: CFTimeInterval = 0
    private var moveTicks = 0

    private(set) var title = "" {
        didSet {
            titleSize = (title as NSString).size(withAttributes: [.font: font])
            pill?.title = title
        }
    }

    /// Whether the pill is on screen, mid-morph or at rest.
    var isPresented: Bool { pill != nil }

    func onTap(_ action: @escaping () -> Void) { onTap = action }

    func setTitle(_ title: String) {
        guard title != self.title else { return }
        self.title = title
        if phase == .collapsed { placeResting() }
    }

    func collapse(_ bar: UITabBar, title: String, animated: Bool) {
        guard bar.window != nil, !bar.isHidden, bar.superview != nil else {
            tabBarLog.notice("collapse skipped: inWindow=\(bar.window != nil) hidden=\(bar.isHidden) hasSuperview=\(bar.superview != nil)")
            return
        }
        if self.bar === bar, phase == .collapsing || phase == .collapsed {
            setTitle(title)
            return
        }
        if bar !== self.bar { release() }
        self.bar = bar
        self.title = title
        if pill == nil {
            guard attach(to: bar) else { return }
        }
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        tabBarLog.notice("collapse start: from=\(self.expansion) animated=\(animated) reduceMotion=\(reduceMotion) bar=\(self.barFrame.text, privacy: .public) glass=\(self.expanded.text, privacy: .public) pill=\(self.compact.text, privacy: .public)")
        move(collapsing: true, animated: animated && !reduceMotion)
    }

    func expand(animated: Bool) {
        guard pill != nil, phase != .expanding else { return }
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        tabBarLog.notice("reveal start: from=\(self.expansion) animated=\(animated) reduceMotion=\(reduceMotion)")
        move(collapsing: false, animated: animated && !reduceMotion)
    }

    /// Back to the plain tab bar at once.
    func release() {
        stopLink()
        generation += 1
        hiddenBar.disengage()
        pill?.removeFromSuperview()
        pill = nil
        phase = .idle
        expansion = 1
    }

    // MARK: Setup

    private func attach(to bar: UITabBar) -> Bool {
        guard let superview = bar.superview else { return false }
        measure(bar, in: superview)
        let pill = MinimizedPillView(font: font)
        pill.title = title
        pill.onTap = { [weak self] in self?.onTap() }
        pill.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin]
        pill.frame = expanded.cgRect
        pill.alpha = 0
        superview.insertSubview(pill, aboveSubview: bar)
        self.pill = pill
        expansion = 1
        hiddenBar.engage(bar)
        return true
    }

    /// The bar's own frame and the frame of its glass, in the bar's superview.
    private func measure(_ bar: UITabBar, in superview: UIView) {
        barFrame = TabBarMinimizeStyle.Rect(superview.convert(bar.bounds, from: bar))
        safeAreaBottom = Double(bar.window?.safeAreaInsets.bottom ?? 0)
        if let platter = Self.platter(in: bar) {
            let rect = TabBarMinimizeStyle.Rect(superview.convert(platter.bounds, from: platter))
            if TabBarMinimizeStyle.isPlausibleGlass(rect, inBar: barFrame) {
                expanded = rect
                return
            }
            tabBarLog.notice("platter frame \(rect.text, privacy: .public) is not the bar's glass in bar \(self.barFrame.text, privacy: .public); using the fallback")
        }
        expanded = TabBarMinimizeStyle.fallbackGlassRect(inBar: barFrame, safeAreaBottom: safeAreaBottom)
    }

    private static func platter(in bar: UITabBar) -> UIView? {
        let base: AnyClass? = NSClassFromString("UIKit._UITabBarPlatterView")
        let candidates = bar.subviews.map { view in
            TabBarPlatter.Candidate(
                className: NSStringFromClass(type(of: view)),
                inheritsPlatterBase: base.map { view.isKind(of: $0) } ?? false,
                width: Double(view.bounds.width), visible: !view.isHidden && view.alpha > 0.01)
        }
        let subviews = bar.subviews.map {
            "\(NSStringFromClass(type(of: $0))) \(TabBarMinimizeStyle.Rect($0.frame).text)\($0.isHidden ? " hidden" : "")"
        }.joined(separator: ", ")
        guard let index = TabBarPlatter.pick(from: candidates) else {
            tabBarLog.notice("platter not found; bar subviews: [\(subviews, privacy: .public)]")
            return nil
        }
        tabBarLog.notice("platter found: \(candidates[index].className, privacy: .public); bar subviews: [\(subviews, privacy: .public)]")
        return bar.subviews[index]
    }

    private var compact: TabBarMinimizeStyle.Rect {
        TabBarMinimizeStyle.compactRect(inBar: barFrame, titleWidth: titleSize.width, titleHeight: titleSize.height,
                                        safeAreaBottom: safeAreaBottom)
    }

    // MARK: Motion

    private func move(collapsing: Bool, animated: Bool) {
        stopLink()
        generation += 1
        self.collapsing = collapsing
        phase = collapsing ? .collapsing : .expanding
        moveTicks = 0
        moveBegan = CACurrentMediaTime()
        guard animated else {
            apply(expansion: collapsing ? 0 : 1)
            finishMotion()
            return
        }
        startOffset = TabBarMinimizeStyle.startOffset(fromExpansion: expansion, collapsing: collapsing)
        // The recorded timeline starts on the first frame, not now, so
        // the time spent setting the glass up is not charged to the motion.
        startedAt = 0
        startLink(moving: true)
        // A display link that never fires must not leave the bar half-hidden.
        let token = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            MainActor.assumeIsolated { self?.motionStalled(token) }
        }
    }

    private func motionStalled(_ token: Int) {
        guard token == generation, phase == .collapsing || phase == .expanding, moveTicks == 0 else { return }
        tabBarLog.notice("display link silent for 400 ms; jumping to the end of the \(self.collapsing ? "collapse" : "reveal", privacy: .public)")
        apply(expansion: collapsing ? 0 : 1)
        finishMotion()
    }

    private func step(_ link: CADisplayLink) {
        switch phase {
        case .collapsing, .expanding: motionTick(link)
        case .collapsed: restTick()
        case .idle: stopLink()
        }
    }

    private func motionTick(_ link: CADisplayLink) {
        moveTicks += 1
        if startedAt == 0 {
            startedAt = link.targetTimestamp
            tabBarLog.notice("first frame \(Int((CACurrentMediaTime() - self.moveBegan) * 1000)) ms after the start")
        }
        let inactive = UIApplication.shared.applicationState != .active
        let state = TabBarMinimizeStyle.expansion(afterSeconds: link.targetTimestamp - startedAt,
                                                  startOffset: startOffset, collapsing: collapsing)
        apply(expansion: inactive ? (collapsing ? 0 : 1) : state.progress)
        if inactive || state.finished { finishMotion() }
    }

    /// The bar and the pill at `expansion`: the capsule between them, and
    /// the bar's items fading as the capsule's glass takes over.
    private func apply(expansion: Double) {
        self.expansion = expansion
        guard let pill else { return }
        pill.frame = TabBarMinimizeStyle.rect(from: compact, to: expanded, expansion: expansion).cgRect
        pill.alpha = TabBarMinimizeStyle.pillOpacity(expansion: expansion)
        pill.titleOpacity = TabBarMinimizeStyle.titleOpacity(expansion: expansion)
        // The pill takes the taps until the bar's items are back.
        let barReady = TabBarMinimizeStyle.barAcceptsTouches(expansion: expansion, collapsing: collapsing)
        hiddenBar.hold(alpha: TabBarMinimizeStyle.barOpacity(expansion: expansion), acceptsTouches: barReady)
        pill.isUserInteractionEnabled = !barReady
        pill.accessibilityElementsHidden = barReady
    }

    private func finishMotion() {
        let ticks = moveTicks
        let milliseconds = Int((CACurrentMediaTime() - moveBegan) * 1000)
        if collapsing {
            apply(expansion: 0)
            phase = .collapsed
            tabBarLog.notice("collapse end: \(milliseconds) ms, \(ticks) frames, bar alpha=\(Double(self.bar?.alpha ?? -1)) pill=\(TabBarMinimizeStyle.Rect(self.pill?.frame ?? .zero).text, privacy: .public)")
            startLink(moving: false)
        } else {
            tabBarLog.notice("reveal end: \(milliseconds) ms, \(ticks) frames")
            release()
        }
    }

    /// While collapsed: keep the bar hidden and the pill where it belongs.
    private func restTick() {
        guard let bar, let pill, let superview = pill.superview, bar.window != nil, bar.superview === superview else {
            tabBarLog.notice("tab bar left while minimized; restoring it")
            release()
            return
        }
        hiddenBar.reassert()
        if TabBarMinimizeStyle.Rect(superview.convert(bar.bounds, from: bar)) != barFrame {
            measure(bar, in: superview)
            placeResting()
        }
    }

    private func placeResting() { pill?.frame = compact.cgRect }

    private func startLink(moving: Bool) {
        stopLink()
        let proxy = DisplayLinkProxy { [weak self] link in
            guard let self else { return link.invalidate() }
            step(link)
        }
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick(_:)))
        let maximum = Float(UIScreen.main.maximumFramesPerSecond)
        link.preferredFrameRateRange = moving
            ? CAFrameRateRange(minimum: min(60, maximum), maximum: maximum, preferred: maximum)
            : CAFrameRateRange(minimum: 10, maximum: 20, preferred: 20)
        link.add(to: .main, forMode: .common)
        self.link = link
        linkProxy = proxy
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
        linkProxy = nil
    }
}

@MainActor
private final class DisplayLinkProxy: NSObject {
    private let handler: @MainActor (CADisplayLink) -> Void

    init(_ handler: @escaping @MainActor (CADisplayLink) -> Void) { self.handler = handler }

    @objc func tick(_ link: CADisplayLink) { handler(link) }
}
#endif
