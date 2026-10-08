import Foundation

/// Reborn "Hide Style" values (`TabBarCollapseSide`): 0 Left, 1 Right, 2 Fade,
/// 3 Down, 4 Minimize (#1349).
public enum TabBarHideStyle {
    public static let left = 0
    public static let right = 1
    public static let fade = 2
    public static let down = 3
    public static let minimize = 4

    public static let all = [left, right, fade, down, minimize]
    public static let titles = ["Left", "Right", "Fade", "Down", "Minimize"]

    /// Left and Right are UIKit's own minimize; the rest animate the bar
    /// themselves.
    public static func usesNativeMinimize(_ style: Int) -> Bool { style <= right }
}

/// Which of a Liquid Glass tab bar's subviews draws its glass: iOS 26 names
/// the view `_UITabBarPlatterView`, iOS 27 a subclass of it
/// (`_UITabBarItemPlatterView`), and the bar also keeps a hidden platter
/// for its collapsed pill.
public enum TabBarPlatter {
    public struct Candidate: Equatable, Sendable {
        public let className: String
        /// Inherits from `UIKit._UITabBarPlatterView`.
        public let inheritsPlatterBase: Bool
        public let width: Double
        /// On screen: not hidden and not transparent.
        public let visible: Bool

        public init(className: String, inheritsPlatterBase: Bool, width: Double, visible: Bool) {
            self.className = className; self.inheritsPlatterBase = inheritsPlatterBase
            self.width = width; self.visible = visible
        }

        var isPlatter: Bool { inheritsPlatterBase || className.hasSuffix("PlatterView") }
    }

    /// The index of the platter to measure: a visible one over a hidden one,
    /// then the widest. `nil` when none of the subviews is a platter.
    public static func pick(from candidates: [Candidate]) -> Int? {
        candidates.indices
            .filter { candidates[$0].isPlatter }
            .max { lhs, rhs in
                let a = candidates[lhs], b = candidates[rhs]
                if a.visible != b.visible { return !a.visible }
                if a.width != b.width { return a.width < b.width }
                return lhs > rhs
            }
    }
}

/// Reborn "Minimize" hide style (#1349): on scroll down the tab bar becomes a
/// small centered pill naming the current tab, as in Safari's bottom toolbar.
/// The geometry and the two measured motion curves are Reborn's.
public enum TabBarMinimizeStyle {
    /// A point of a measured curve: seconds since the press, and how far the
    /// morph has got (0 = where it started, 1 = where it ends).
    public struct Sample: Equatable, Sendable {
        public let time: TimeInterval
        public let progress: Double
    }

    private static func samples(_ points: [(Double, Double)]) -> [Sample] {
        points.map { Sample(time: $0.0, progress: $0.1) }
    }

    /// Both curves play 10% faster than they were recorded, keeping their shape.
    public static let playbackRate = 1.10

    static let collapseCurve = samples([
        (0.000000, 0.000000), (0.015000, 0.175270), (0.046667, 0.196879), (0.058333, 0.237695),
        (0.091667, 0.321729), (0.103333, 0.396158), (0.120000, 0.500600), (0.135000, 0.597839),
        (0.151667, 0.660264), (0.168333, 0.727491), (0.186667, 0.785114), (0.201667, 0.828331),
        (0.218333, 0.870348), (0.235000, 0.903962), (0.255000, 0.925570), (0.268333, 0.948379),
        (0.285000, 0.965186), (0.303333, 0.977191), (0.336667, 0.986795), (0.366667, 1.000000),
    ])

    /// Overshoots to 1.019 and settles back, as Safari's does.
    static let expandCurve = samples([
        (0.000000, 0.000000), (0.013333, 0.035760), (0.030000, 0.109834), (0.048333, 0.212005),
        (0.063333, 0.335888), (0.081667, 0.499361), (0.088333, 0.554278), (0.111667, 0.633461),
        (0.145000, 0.767561), (0.178333, 0.803321), (0.211667, 0.854406), (0.246667, 0.896552),
        (0.281667, 0.937420), (0.311667, 0.970626), (0.345000, 0.991060), (0.376667, 1.000000),
        (0.423333, 1.019157), (0.505000, 1.011494), (0.625000, 0.997446), (0.905000, 1.000000),
    ])

    public static func curve(collapsing: Bool) -> [Sample] { collapsing ? collapseCurve : expandCurve }

    /// Seconds of recorded time a whole morph covers.
    public static func duration(collapsing: Bool) -> TimeInterval { curve(collapsing: collapsing).last?.time ?? 0 }

    /// Where on the recorded curve a morph starts. A reversal resumes at the
    /// point that matches the size the pill has now, instead of jumping to an
    /// end or replaying the whole animation for a sliver.
    public static func startOffset(fromExpansion expansion: Double, collapsing: Bool) -> TimeInterval {
        let samples = curve(collapsing: collapsing)
        let ceiling = samples.map(\.progress).max() ?? 1
        let motion = min(max(collapsing ? 1 - expansion : expansion, 0), ceiling)
        for i in 1..<samples.count where motion <= samples[i].progress {
            let previous = samples[i - 1], next = samples[i]
            let span = next.progress - previous.progress
            let fraction = span > 0 ? (motion - previous.progress) / span : 0
            return previous.time + fraction * (next.time - previous.time)
        }
        return 0
    }

    /// 1 = full tab bar, 0 = the compact pill, for a morph `seconds` of wall
    /// time after it began at `startOffset`. `finished` once the curve has run out.
    public static func expansion(afterSeconds seconds: TimeInterval, startOffset: TimeInterval,
                                 collapsing: Bool) -> (progress: Double, finished: Bool) {
        let samples = curve(collapsing: collapsing)
        let elapsed = max(0, seconds) * playbackRate + startOffset
        guard let last = samples.last, elapsed < last.time else { return (collapsing ? 0 : 1, true) }
        var motion = 1.0
        for i in 1..<samples.count where elapsed <= samples[i].time {
            let previous = samples[i - 1], next = samples[i]
            let fraction = (elapsed - previous.time) / (next.time - previous.time)
            motion = previous.progress + fraction * (next.progress - previous.progress)
            break
        }
        return (collapsing ? 1 - motion : motion, false)
    }

    // MARK: Geometry

    static let minimumPillWidth = 96.0
    static let minimumPillHeight = 32.0
    static let titleHorizontalPadding = 36.0
    static let titleVerticalPadding = 14.0
    /// A tap is accepted this tall even though the pill is shorter.
    public static let minimumTouchHeight = 44.0

    /// 96x32 at least, wider for a longer title, and always clear of the
    /// screen's edges.
    public static func pillSize(titleWidth: Double, titleHeight: Double,
                                availableWidth: Double) -> (width: Double, height: Double) {
        let width = max(minimumPillWidth, titleWidth.rounded(.up) + titleHorizontalPadding)
        let height = max(minimumPillHeight, titleHeight.rounded(.up) + titleVerticalPadding)
        return (min(width, max(44, availableWidth - 32)), height)
    }

    /// Space between the pill and the bottom of the screen.
    public static func bottomGap(safeAreaBottom: Double) -> Double { max(8, safeAreaBottom - 20) }

    /// A rectangle in the coordinate space of the bar's superview.
    public struct Rect: Equatable, Sendable {
        public var x, y, width, height: Double

        public static let zero = Rect(x: 0, y: 0, width: 0, height: 0)

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x; self.y = y; self.width = width; self.height = height
        }

        public var maxX: Double { x + width }
        public var maxY: Double { y + height }
        public var midX: Double { x + width / 2 }
        public var isEmpty: Bool { width <= 0 || height <= 0 }
    }

    /// The pill at rest: centered over the bar, `bottomGap` above its bottom edge.
    public static func compactRect(inBar bar: Rect, titleWidth: Double, titleHeight: Double,
                                   safeAreaBottom: Double) -> Rect {
        let size = pillSize(titleWidth: titleWidth, titleHeight: titleHeight, availableWidth: bar.width)
        return Rect(x: bar.midX - size.width / 2,
                    y: bar.maxY - bottomGap(safeAreaBottom: safeAreaBottom) - size.height,
                    width: size.width, height: size.height)
    }

    static let fallbackGlassInset = 21.0
    static let fallbackGlassHeight = 62.0

    /// Where the bar's glass sits when UIKit's own view for it can't be
    /// found: inset from the sides of the bar, 14 points above a home
    /// indicator, as on the system bar.
    public static func fallbackGlassRect(inBar bar: Rect, safeAreaBottom: Double) -> Rect {
        let height = min(fallbackGlassHeight, bar.height)
        return Rect(x: bar.x + fallbackGlassInset, y: bar.maxY - max(8, safeAreaBottom - 14) - height,
                    width: max(0, bar.width - 2 * fallbackGlassInset), height: height)
    }

    /// Whether a measured glass rectangle can be the bar's glass: wide, tall
    /// enough to hold the tabs and inside the bar. Anything else (a view that
    /// is not laid out yet, a collapsed platter) falls back to measured sizes.
    public static func isPlausibleGlass(_ glass: Rect, inBar bar: Rect) -> Bool {
        let slack = 1.0
        return glass.width >= bar.width * 0.5 && glass.height >= 30 && glass.height <= bar.height + slack
            && glass.x >= bar.x - slack && glass.maxX <= bar.maxX + slack
            && glass.y >= bar.y - slack && glass.maxY <= bar.maxY + slack
    }

    /// The capsule between the pill (`expansion` 0) and the bar's glass (1).
    public static func rect(from compact: Rect, to expanded: Rect, expansion: Double) -> Rect {
        func mix(_ from: Double, _ to: Double) -> Double { from + (to - from) * expansion }
        return Rect(x: mix(compact.x, expanded.x), y: mix(compact.y, expanded.y),
                    width: mix(compact.width, expanded.width), height: mix(compact.height, expanded.height))
    }

    // MARK: Cross-fade between the bar and the pill

    /// The tab bar's own items: gone by 70% expanded, fully back at 95%.
    public static func barOpacity(expansion: Double) -> Double { clamp01((expansion - 0.70) / 0.25) }

    /// The pill's glass stands in for the bar while its items are away.
    public static func pillOpacity(expansion: Double) -> Double { 1 - barOpacity(expansion: expansion) }

    /// The title is only drawn once the pill is small enough to read as one.
    public static func titleOpacity(expansion: Double) -> Double { clamp01((0.35 - expansion) / 0.25) }

    /// While the bar is on its way back it takes taps again at 95%, not at the end
    /// of the settling tail.
    public static func barAcceptsTouches(expansion: Double, collapsing: Bool) -> Bool {
        !collapsing && expansion >= 0.95
    }

    private static func clamp01(_ value: Double) -> Double { min(1, max(0, value)) }
}
