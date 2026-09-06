import SwiftUI
import PhoebusCore
#if canImport(UIKit)
import UIKit
import UIKit.UIGestureRecognizerSubclass
import ObjectiveC
import OSLog

private let magnifierLog = Logger(subsystem: "com.pendo324.Phoebus", category: "InfoRowMagnifier")

/// One stat in a post's info row the magnifier can land on.
enum InfoRowStat: Int, CaseIterable {
    case score, comments, age, translation

    var caption: String {
        switch self {
        case .score: return "Upvote"
        case .comments: return "Comments"
        case .age: return "Posted"
        case .translation: return "Translate"
        }
    }
}

/// Each stat's frame in the info row's "infoRow" coordinate space.
struct InfoRowStatFrames: PreferenceKey {
    static let defaultValue: [InfoRowStat: CGRect] = [:]
    static func reduce(value: inout [InfoRowStat: CGRect], nextValue: () -> [InfoRowStat: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Reports this stat's frame to the info row's magnifier.
    func infoRowStat(_ stat: InfoRowStat) -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(key: InfoRowStatFrames.self,
                                   value: [stat: geo.frame(in: .named(InfoRowMagnifierProbe.space))])
        })
    }
}

/// Reborn's "Magnify Info Row on Hold": holding the info row raises a
/// glass card with the row zoomed; an accent pill follows the finger
/// from icon to icon, and releasing activates the one under it.
/// Dragging well away dims the card to "Release to Cancel".
///
/// A long press on the row's own cell, limited to the info row, so it wins
/// over the cell's context menu and the list's scroll as Reborn's does, while a
/// short tap still reaches the stat beneath.
struct InfoRowMagnifierProbe: UIViewRepresentable {
    static let space = "infoRow"

    let targets: [InfoRowStat: CGRect]
    let enabled: Bool
    let onActivate: (InfoRowStat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        let coordinator = context.coordinator
        coordinator.probe = view
        coordinator.targets = targets
        coordinator.onActivate = onActivate
        coordinator.enabled = enabled
        DispatchQueue.main.async { coordinator.attach() }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var probe: UIView?
        var targets: [InfoRowStat: CGRect] = [:]
        var onActivate: (InfoRowStat) -> Void = { _ in }
        var enabled = false
        private weak var host: UIView?
        private var recognizer: InfoRowHoldRecognizer?
        private var loupe: InfoRowLoupeView?
        private var selected: InfoRowStat?
        private var cancelled = false

        func attach() {
            guard let probe else { return }
            // The row's list cell, so the press beats the cell's context menu.
            var candidate = probe.superview
            while let view = candidate, !(view is UICollectionViewCell || view is UITableViewCell) {
                candidate = view.superview
            }
            // Where the list's rows aren't cells, the row's own view: the
            // ancestor sitting directly in the scroll view.
            if candidate == nil {
                var view = probe.superview
                while let current = view, !(current.superview is UIScrollView) { view = current.superview }
                candidate = view
            }
            guard let cell = candidate, host !== cell else { return }
            magnifierLog.notice("attached to \(String(describing: type(of: cell)), privacy: .public)")
            if let recognizer { recognizer.view?.removeGestureRecognizer(recognizer) }
            // No target/action: the recognizer calls back itself, on its own clock.
            let press = InfoRowHoldRecognizer(target: nil, action: nil)
            press.setAction { [weak self] in self?.handle($0) }
            press.delegate = self
            cell.addGestureRecognizer(press)
            recognizer = press
            host = cell
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard enabled, let probe, probe.window != nil, !targets.isEmpty else { return false }
            let inside = probe.bounds.insetBy(dx: 0, dy: -6).contains(touch.location(in: probe))
            if inside {
                // For Export Debug Logs: what else wants this touch.
                var names: [String] = []
                var view: UIView? = touch.view
                while let current = view {
                    names += (current.gestureRecognizers ?? []).map { NSStringFromClass(type(of: $0)) }
                    view = current.superview
                }
                magnifierLog.notice("touch on the info row; recognizers: \(names.joined(separator: ","), privacy: .public)")
            }
            return inside
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            // The row's context menu (its long press, lift and relationship
            // recognizers) waits for the magnifier to fail, as Reborn
            // suppresses that menu over the info row. Scrolling, swipes and
            // taps aren't held up.
            guard other !== gestureRecognizer else { return false }
            let name = NSStringFromClass(type(of: other))
            return ["ContextMenu", "Relationship", "TouchDuration", "DragLift", "Click", "Preview"]
                .contains { name.contains($0) }
        }

        /// Everything but the context menu keeps running alongside: SwiftUI's
        /// own gestures would otherwise force the press to fail.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            !self.gestureRecognizer(gestureRecognizer, shouldBeRequiredToFailBy: other)
        }

        private func handle(_ press: InfoRowHoldRecognizer) {
            guard let probe, let window = probe.window else { return }
            let point = press.location(in: probe)
            switch press.phase {
            case .began:
                magnifierLog.notice("hold began over \(self.targets.count) stats")
                let ordered = targets.sorted { $0.value.minX < $1.value.minX }
                guard let first = ordered.first else { return }
                let strip = ordered.reduce(first.value) { $0.union($1.value) }.insetBy(dx: -8, dy: -9)
                let stripInWindow = probe.convert(strip, to: window)
                let image = UIGraphicsImageRenderer(bounds: stripInWindow).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
                }
                let card = InfoRowLoupeView(image: image, stripSize: strip.size, zoom: 1.8)
                window.addSubview(card)
                loupe = card
                cancelled = false
                selected = nil
                card.position(above: press.location(in: window), in: window)
                card.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
                card.alpha = 0
                UIView.animate(withDuration: 0.22, delay: 0, usingSpringWithDamping: 0.8,
                               initialSpringVelocity: 0.4, options: [.allowUserInteraction]) {
                    card.transform = .identity
                    card.alpha = 1
                }
                Haptics.light()
                track(point, strip: strip, window: window, press: press)
            case .changed:
                guard let loupe else { return }
                let ordered = targets.sorted { $0.value.minX < $1.value.minX }
                guard let first = ordered.first else { return }
                let strip = ordered.reduce(first.value) { $0.union($1.value) }.insetBy(dx: -8, dy: -9)
                loupe.position(above: press.location(in: window), in: window)
                track(point, strip: strip, window: window, press: press)
            case .ended:
                let stat = cancelled ? nil : selected
                dismissLoupe()
                // The stat's own tap may still fire for this touch.
                InfoRowHoldRecognizer.lastHoldEnded = Date()
                if let stat { onActivate(stat) }
            case .cancelled:
                magnifierLog.notice("hold cancelled")
                InfoRowHoldRecognizer.lastHoldEnded = Date()
                dismissLoupe()
            }
        }

        private func track(_ point: CGPoint, strip: CGRect, window: UIWindow, press: UIGestureRecognizer) {
            guard let loupe else { return }
            // Well above or below the row: release cancels.
            let away = point.y < strip.minY - 60 || point.y > strip.maxY + 60
            if away != cancelled {
                cancelled = away
                loupe.setCancelled(away)
                if !away, let selected, let rect = targets[selected] {
                    loupe.select(rect.offsetBy(dx: -strip.minX, dy: -strip.minY), caption: selected.caption)
                }
            }
            guard !away else { return }
            let nearest = targets.min { abs($0.value.midX - point.x) < abs($1.value.midX - point.x) }
            guard let (stat, rect) = nearest, stat != selected else { return }
            if selected != nil { Haptics.selection() }
            selected = stat
            loupe.select(rect.offsetBy(dx: -strip.minX, dy: -strip.minY), caption: stat.caption)
        }

        private func dismissLoupe() {
            guard let card = loupe else { return }
            loupe = nil
            UIView.animate(withDuration: 0.16, animations: {
                card.alpha = 0
                card.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
            }, completion: { _ in card.removeFromSuperview() })
        }
    }
}

/// The glass card: the strip zoomed, an accent pill on the selected icon,
/// and its caption below.
final class InfoRowLoupeView: UIView {
    private let zoom: CGFloat
    private let pill = UIView()
    private let caption = UILabel()
    private var hasSelection = false
    private var lockedCenterY: CGFloat?

    init(image: UIImage, stripSize: CGSize, zoom: CGFloat) {
        self.zoom = zoom
        let pad: CGFloat = 10, captionHeight: CGFloat = 16, gap: CGFloat = 4
        let imageSize = CGSize(width: stripSize.width * zoom, height: stripSize.height * zoom)
        let size = CGSize(width: imageSize.width + pad * 2, height: imageSize.height + pad * 2 + gap + captionHeight)
        super.init(frame: CGRect(origin: .zero, size: size))
        isUserInteractionEnabled = false

        let effect: UIVisualEffect
        if LiquidGlass.isEnabled, #available(iOS 26.0, *) {
            effect = UIGlassEffect()
        } else {
            effect = UIBlurEffect(style: .systemMaterial)
        }
        let card = UIVisualEffectView(effect: effect)
        card.frame = bounds
        card.layer.cornerRadius = min(22, size.height / 2)
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        addSubview(card)

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: 8)
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: card.layer.cornerRadius).cgPath

        let clip = UIView(frame: CGRect(x: pad, y: pad, width: imageSize.width, height: imageSize.height))
        clip.layer.cornerRadius = 10
        clip.layer.cornerCurve = .continuous
        clip.clipsToBounds = true
        card.contentView.addSubview(clip)

        let strip = UIImageView(image: image)
        strip.frame = clip.bounds
        strip.contentMode = .scaleToFill
        clip.addSubview(strip)

        // The pill sits above the opaque strip with a soft wash, so the
        // selected icon reads as lit.
        pill.layer.cornerRadius = 8
        pill.layer.cornerCurve = .continuous
        pill.layer.borderWidth = 1.5
        let tint = UIColor(Color.apolloAccent)
        pill.layer.borderColor = tint.withAlphaComponent(0.9).cgColor
        pill.backgroundColor = tint.withAlphaComponent(0.16)
        clip.addSubview(pill)

        caption.frame = CGRect(x: pad, y: imageSize.height + pad + gap, width: imageSize.width, height: captionHeight)
        caption.font = .systemFont(ofSize: 12, weight: .semibold)
        caption.textColor = .label
        caption.textAlignment = .center
        card.contentView.addSubview(caption)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func select(_ rectInStrip: CGRect, caption text: String) {
        let scaled = CGRect(x: rectInStrip.minX * zoom, y: rectInStrip.minY * zoom,
                            width: rectInStrip.width * zoom, height: rectInStrip.height * zoom)
            .insetBy(dx: -7, dy: -5)
        caption.text = text
        if !hasSelection {
            hasSelection = true
            pill.frame = scaled
        } else {
            UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.4,
                           options: [.beginFromCurrentState, .allowUserInteraction]) { self.pill.frame = scaled }
        }
    }

    func setCancelled(_ cancelled: Bool) {
        if cancelled { caption.text = "Release to Cancel" }
        UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.alpha = cancelled ? 0.45 : 1
            self.transform = cancelled ? CGAffineTransform(scaleX: 0.9, y: 0.9) : .identity
            self.pill.alpha = cancelled ? 0 : 1
        }
    }

    /// Centred on the finger horizontally; vertically anchored above the
    /// first press and then kept there, so the card doesn't bob.
    func position(above point: CGPoint, in host: UIView) {
        let margin: CGFloat = 10
        let w = bounds.width, h = bounds.height
        let x = max(margin + w / 2, min(point.x, host.bounds.width - margin - w / 2))
        if lockedCenterY == nil {
            var top = point.y - h - 44
            if top < host.safeAreaInsets.top + 6 { top = point.y + 44 }
            lockedCenterY = top + h / 2
        }
        center = CGPoint(x: x, y: lockedCenterY ?? point.y)
    }
}

/// Info Row "Overlay": Reborn's small card over the tapped stat: a dark
/// material with an accent border and wash, the headline over the date,
/// gone after 1.6 s.
struct InfoRowOverlayCard: View {
    let title: String
    let message: String?

    var body: some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 13, weight: .semibold))
            if let message {
                Text(message).font(.system(size: 12)).opacity(0.72)
            }
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thickMaterial)
                .environment(\.colorScheme, .dark)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.apolloAccent.opacity(0.16)))
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.apolloAccent.opacity(0.9), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .fixedSize()
        .allowsHitTesting(false)
    }
}

/// Reborn's age detail ("Posted 3h Ago" over the full date).
enum InfoRowAgeDetail {
    /// `condensed`: the Overlay card's shorter date line.
    static func lines(created: Date, now: Date = Date(), condensed: Bool = false) -> (title: String, message: String?) {
        let interval = abs(now.timeIntervalSince(created))
        let relative: String
        switch interval {
        case ..<5: return ("Posted Just now", nil)
        case ..<60: relative = "\(Int(interval))s"
        case ..<3600: relative = "\(Int(interval / 60))m"
        case ..<86400: relative = "\(Int(interval / 3600))h"
        case ..<2_592_000: relative = "\(Int(interval / 86400))d"
        case ..<31_536_000: relative = "\(Int(interval / 2_592_000))mo"
        default: relative = String(format: "%.1fy", interval / 31_556_736)
        }
        let formatter = DateFormatter()
        formatter.dateStyle = condensed ? .medium : .long
        formatter.timeStyle = .short
        let date = formatter.string(from: created)
        return ("Posted \(relative) Ago", condensed ? date : "Posted on \(date)")
    }
}
#endif

/// Reborn's "% Upvoted" detail: approximate vote totals from the fuzzed
/// score and rounded percentage, shown only at 60% or above, where the
/// estimate holds.
enum InfoRowPercentDetail {
    static func lines(score: Int, ratio: Double, condensed: Bool) -> (title: String, message: String?) {
        let percent = ratio * 100
        let rounded = Int(percent.rounded())
        let percentText = rounded.formatted()
        let ratioLine = "~\(rounded):\(100 - rounded) upvote to downvote ratio"
        let title = "\(percentText)% Upvoted"
        let p = Double(rounded) / 100
        guard rounded >= 60, rounded <= 100, score > 0, 2 * p - 1 > 0 else {
            if condensed { return (title, ratioLine) }
            let reason = score <= 0
                ? "Upvote and downvote totals are not shown when the score is zero or negative because Reddit does not expose enough information to estimate them."
                : "Upvote and downvote totals are not shown below 60% because they become inaccurate as the upvote percentage approaches 50%."
            return (title, "\(percentText)% of voters upvoted this post.\n\n\(ratioLine)\n\n\(reason)")
        }
        let upvotes = Int((p * Double(score) / (2 * p - 1)).rounded())
        let downvotes = upvotes - score
        let counts = "~\(upvotes.formatted()) \(upvotes == 1 ? "upvote" : "upvotes"), ~\(downvotes.formatted()) \(downvotes == 1 ? "downvote" : "downvotes")"
        if condensed { return (title, "\(counts)\n\(ratioLine)") }
        return (title, "\(percentText)% of voters upvoted this post.\n\n\(counts)\n\n\(ratioLine)\n\nCounts are approximate because Reddit rounds the upvote percentage and fuzzes the displayed score.")
    }
}

/// Info Row Popup / Overlay on one stat: a tap shows `lines` as an alert
/// (Popup) or as the small card just above the stat (Overlay).
struct InfoRowDetailTap: ViewModifier {
    let popup: Bool
    let overlay: Bool
    /// `.leading` for a stat near the left margin, so the card stays on screen.
    var edge: HorizontalAlignment = .center
    let lines: (_ condensed: Bool) -> (title: String, message: String?)

    @State private var alert: PostRow.AgeDetail?
    @State private var card: PostRow.AgeDetail?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: Alignment(horizontal: edge, vertical: .top)) {
                Color.clear.frame(width: 0, height: 0).overlay(alignment: Alignment(horizontal: edge, vertical: .bottom)) {
                    if let card {
                        InfoRowOverlayCard(title: card.title, message: card.message)
                            .padding(.bottom, 8)
                            .transition(.opacity.combined(with: .offset(y: 6)))
                            .id(card.id)
                    }
                }
            }
            .zIndex(card == nil ? 0 : 1)
            .contentShape(Rectangle())
            .highPriorityGesture(TapGesture().onEnded(show), including: popup || overlay ? .all : .subviews)
            .alert(alert?.title ?? "", isPresented: $alert.isPresent()) {
                Button("OK", role: .cancel) {}
            } message: {
                if let message = alert?.message { Text(message) }
            }
    }

    private func show() {
        if overlay {
            let text = lines(true)
            let next = PostRow.AgeDetail(title: text.title, message: text.message)
            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) { card = next }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.6))
                guard card?.id == next.id else { return }
                withAnimation(.easeIn(duration: 0.35)) { card = nil }
            }
        } else if popup {
            let text = lines(false)
            alert = PostRow.AgeDetail(title: text.title, message: text.message)
        }
    }
}

/// The magnifier's hold, timed by itself rather than by
/// `UILongPressGestureRecognizer`'s state machine: the stats' own
/// SwiftUI tap gestures hold the long press back until the finger moves
/// enough to fail them. This drives the loupe from its own timer
/// whatever state UIKit leaves the recognizer in; reaching `.began`
/// only serves to cancel the row's context menu where it can.
final class InfoRowHoldRecognizer: UIGestureRecognizer {
    enum Phase { case began, changed, ended, cancelled }

    /// When a hold last finished, so the same touch's tap is ignored.
    nonisolated(unsafe) static var lastHoldEnded: Date?

    /// Whether a stat's tap belongs to a hold that just ended.
    static var tapFollowsHold: Bool {
        lastHoldEnded.map { Date().timeIntervalSince($0) < 0.4 } ?? false
    }

    /// A hold is open: row swipes, page swipes and scrolling stand down so
    /// the finger can slide between the stats.
    nonisolated(unsafe) static var isHolding = false

    private(set) var phase: Phase = .began
    private var active = false {
        didSet {
            Self.isHolding = active
            if active {
                if let view { scrollLock.lock(ScrollGestureExclusivity.enclosingScrollViews(of: view)) }
            } else {
                scrollLock.release()
            }
        }
    }
    private let scrollLock = ScrollLock()
    private var timer: Timer?
    private var start: CGPoint = .zero
    private weak var trackedTouch: UITouch?

    private static let holdDuration: TimeInterval = 0.35
    private static let allowableMovement: CGFloat = 10

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func location(in view: UIView?) -> CGPoint {
        trackedTouch?.location(in: view) ?? super.location(in: view)
    }

    private func fire(_ next: Phase) {
        phase = next
        // Straight to the handler: UIKit may hold this recognizer's state
        // back, and the loupe mustn't wait for it.
        sendAction()
    }

    private var sendAction: () -> Void = {}

    func setAction(_ action: @escaping (InfoRowHoldRecognizer) -> Void) {
        sendAction = { [unowned self] in action(self) }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard trackedTouch == nil, let touch = touches.first, touches.count == 1 else {
            if !active { state = .failed }
            return
        }
        trackedTouch = touch
        start = touch.location(in: view?.window)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.holdDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let touch = self.trackedTouch, !self.active else { return }
                self.active = true
                self.takeTouch(touch)
                self.fire(.began)
                if self.state == .possible { self.state = .began }
            }
        }
    }

    /// Once the loupe is open the touch is the magnifier's alone: every
    /// other recognizer on its path (the stats' and row's taps, the row
    /// swipe, the context menu, the list's scroll, page swipes) is switched
    /// off and on again, which cancels it for this touch. Waiting to win
    /// the usual arbitration lets the row swipe start instead when sliding
    /// to another stat.
    private func takeTouch(_ touch: UITouch) {
        var view = touch.view
        while let current = view {
            for recognizer in current.gestureRecognizers ?? [] where recognizer !== self && recognizer.isEnabled {
                recognizer.isEnabled = false
                recognizer.isEnabled = true
            }
            view = current.superview
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        if active {
            fire(.changed)
            if state == .began || state == .changed { state = .changed }
            return
        }
        let point = touch.location(in: view?.window)
        if hypot(point.x - start.x, point.y - start.y) > Self.allowableMovement {
            timer?.invalidate()
            state = .failed
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        finish(.ended)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        finish(.cancelled)
    }

    private func finish(_ outcome: Phase) {
        timer?.invalidate()
        if active {
            fire(outcome)
            active = false
            state = outcome == .ended ? .ended : .cancelled
        } else {
            state = .failed
        }
    }

    override func reset() {
        super.reset()
        timer?.invalidate()
        timer = nil
        // UIKit failed this recognizer while the loupe was open (another
        // gesture won the touch): close it rather than leave it frozen.
        if active {
            magnifierLog.notice("hold taken by another gesture")
            fire(.cancelled)
        }
        active = false
        trackedTouch = nil
    }
}
