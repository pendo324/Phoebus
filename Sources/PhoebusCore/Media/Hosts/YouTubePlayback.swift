import Foundation

/// The IFrame Player API's `onStateChange` codes.
public enum YouTubePlayerState: Int, Sendable, Equatable {
    case unstarted = -1
    case ended = 0
    case playing = 1
    case paused = 2
    case buffering = 3
    case cued = 5

    /// Playing or about to: the transport shows Pause, as it does for an
    /// `AVPlayer` whose rate is non-zero while it buffers.
    public var isPlayingOrBuffering: Bool { self == .playing || self == .buffering }
}

/// What the script in YouTube's embed frame reads off the `<video>` element
/// (`YouTubeEmbed.frameScript`): the element's own state after `type`, the
/// event that caused the report (`attached`, `play`, `pause`, `timeupdate`,
/// `volumechange`, `ad`, ...).
public struct YouTubeVideoReport: Equatable, Sendable {
    public var type: String
    public var current: Double
    public var duration: Double
    public var rate: Double
    public var isMuted: Bool
    public var isPaused: Bool
    public var isEnded: Bool
    /// Playing, but waiting for data.
    public var isWaiting: Bool
    /// An ad is showing in the same element.
    public var isAd: Bool

    public init(type: String, current: Double = 0, duration: Double = 0, rate: Double = 1, isMuted: Bool = true,
                isPaused: Bool = true, isEnded: Bool = false, isWaiting: Bool = false, isAd: Bool = false) {
        self.type = type
        self.current = current
        self.duration = duration
        self.rate = rate
        self.isMuted = isMuted
        self.isPaused = isPaused
        self.isEnded = isEnded
        self.isWaiting = isWaiting
        self.isAd = isAd
    }

    /// The player state the element's flags amount to.
    public var state: YouTubePlayerState {
        if isEnded { return .ended }
        if isPaused { return .paused }
        return isWaiting ? .buffering : .playing
    }
}

/// What the embed page reports through `YouTubeEmbed.messageHandlerName`.
public enum YouTubePlayerMessage: Equatable, Sendable {
    case ready(duration: Double, isMuted: Bool)
    case state(YouTubePlayerState, current: Double?, duration: Double?)
    case time(current: Double, duration: Double, rate: Double?)
    case rate(Double)
    case error(code: Int)
    /// From the embed frame's script, once it has found the video element.
    case video(YouTubeVideoReport)

    /// Reads a script message body (`{ event: 'state', code: 1, ... }`).
    /// Nil for anything the page doesn't send, including an unknown state.
    public static func parse(_ body: Any) -> YouTubePlayerMessage? {
        guard let fields = body as? [String: Any], let event = fields["event"] as? String else { return nil }
        switch event {
        case "ready":
            return .ready(duration: number(fields["duration"]) ?? 0, isMuted: fields["muted"] as? Bool ?? true)
        case "state":
            guard let code = number(fields["code"]), let state = YouTubePlayerState(rawValue: Int(code)) else { return nil }
            return .state(state, current: number(fields["current"]), duration: number(fields["duration"]))
        case "time":
            guard let current = number(fields["current"]) else { return nil }
            return .time(current: current, duration: number(fields["duration"]) ?? 0, rate: number(fields["rate"]))
        case "rate":
            guard let rate = number(fields["rate"]), rate > 0 else { return nil }
            return .rate(rate)
        case "error":
            guard let code = number(fields["code"]) else { return nil }
            return .error(code: Int(code))
        case "video":
            guard let type = fields["type"] as? String else { return nil }
            return .video(YouTubeVideoReport(
                type: type, current: max(0, number(fields["current"]) ?? 0), duration: max(0, number(fields["duration"]) ?? 0),
                rate: number(fields["rate"]).flatMap { $0 > 0 ? $0 : nil } ?? 1,
                isMuted: fields["muted"] as? Bool ?? true, isPaused: fields["paused"] as? Bool ?? true,
                isEnded: fields["ended"] as? Bool ?? false, isWaiting: fields["waiting"] as? Bool ?? false,
                isAd: fields["ad"] as? Bool ?? false))
        default:
            return nil
        }
    }

    /// A JSON number as the platform delivers it: `NSNumber` from WebKit,
    /// `Int` or `Double` from Swift.
    private static func number(_ value: Any?) -> Double? {
        let result: Double?
        switch value {
        case let double as Double: result = double
        case let int as Int: result = Double(int)
        case let number as NSNumber: result = number.doubleValue
        default: result = nil
        }
        guard let result, result.isFinite else { return nil }
        return result
    }
}

/// A YouTube video's playback as the app's own controls see it, built from
/// the page's messages. Once the frame script reports the video element, the
/// element is the source of truth (state, time, rate and mute) and the IFrame
/// API's own reports are ignored. The time arrives a few times a second, so
/// `seconds(at:)` carries it forward between reports while the video plays,
/// the way an `AVPlayer` reports a smooth time.
public struct YouTubePlayback: Equatable, Sendable {
    /// The parts of the playback that change the controls' look, as opposed
    /// to the time, which changes continuously.
    public struct Status: Equatable, Sendable {
        public var isPlaying = false
        public var isMuted = true
        public var duration: Double = 0
        public var isReady = false
        /// Has played at least once, so the page has something to show.
        public var hasPlayed = false
        public var failureCode: Int?
        /// An ad is showing: the time and duration on offer are the content's.
        public var isAd = false

        public init(isPlaying: Bool = false, isMuted: Bool = true, duration: Double = 0, isReady: Bool = false,
                    hasPlayed: Bool = false, failureCode: Int? = nil, isAd: Bool = false) {
            self.isAd = isAd
            self.isPlaying = isPlaying
            self.isMuted = isMuted
            self.duration = duration
            self.isReady = isReady
            self.hasPlayed = hasPlayed
            self.failureCode = failureCode
        }

        /// Removed, private or embedding-disabled: nothing will play here.
        public var isUnplayable: Bool { failureCode.map(YouTubeEmbed.isUnplayableInline(errorCode:)) ?? false }
    }

    public private(set) var playerState: YouTubePlayerState = .unstarted
    public private(set) var isReady = false
    public private(set) var isMuted: Bool
    public private(set) var rate: Double = 1
    public private(set) var duration: Double = 0
    public private(set) var hasPlayed = false
    public private(set) var failureCode: Int?
    public private(set) var isAd = false
    /// The frame script has reported the video element.
    public private(set) var hasVideoSource = false
    /// What the user just asked for, until the player answers with a state.
    private var requestedPlaying: Bool?
    private var anchorSeconds: Double = 0
    private var anchorTime: TimeInterval = 0

    public init(isMuted: Bool = true) {
        self.isMuted = isMuted
    }

    /// Shows Pause: what was asked for until the player answers, then the
    /// player's own state.
    public var isPlaying: Bool { requestedPlaying ?? playerState.isPlayingOrBuffering }

    public var status: Status {
        Status(isPlaying: isPlaying, isMuted: isMuted, duration: duration, isReady: isReady,
               hasPlayed: hasPlayed, failureCode: failureCode, isAd: isAd)
    }

    /// The playhead at `now` (a monotonic clock, in seconds).
    public func seconds(at now: TimeInterval) -> Double {
        var value = anchorSeconds
        if playerState == .playing, requestedPlaying != false, !isAd {
            value += max(0, now - anchorTime) * rate
        }
        if duration > 0 { value = min(value, duration) }
        return max(0, value)
    }

    public mutating func apply(_ message: YouTubePlayerMessage, at now: TimeInterval) {
        let carried = seconds(at: now)
        switch message {
        case .ready(let duration, let isMuted):
            isReady = true
            setDuration(duration)
            if !hasVideoSource { self.isMuted = isMuted }
        case .state, .time, .rate:
            if !hasVideoSource { applyAPIReport(message, carried: carried, at: now) }
        case .error(let code):
            failureCode = code
            requestedPlaying = nil
        case .video(let report):
            applyVideo(report, at: now)
        }
    }

    private mutating func applyAPIReport(_ message: YouTubePlayerMessage, carried: Double, at now: TimeInterval) {
        switch message {
        case .state(let state, let current, let duration):
            playerState = state
            requestedPlaying = nil
            if state == .playing { hasPlayed = true }
            if let duration { setDuration(duration) }
            // An ended video rests on its last frame.
            let known = (state == .ended && self.duration > 0) ? self.duration : (current ?? carried)
            anchor(known, at: now)
        case .time(let current, let duration, let rate):
            setDuration(duration)
            if let rate, rate > 0 { self.rate = rate }
            anchor(current, at: now)
        case .rate(let rate):
            anchor(carried, at: now)
            self.rate = rate
        default:
            break
        }
    }

    private mutating func applyVideo(_ report: YouTubeVideoReport, at now: TimeInterval) {
        hasVideoSource = true
        isMuted = report.isMuted
        let wasAd = isAd
        isAd = report.isAd
        let state = report.state
        // An unstarted video that is merely paused isn't "paused" yet.
        playerState = (state == .paused && !hasPlayed && report.current == 0) ? .unstarted : state
        if requestedPlaying == state.isPlayingOrBuffering || state == .ended { requestedPlaying = nil }
        if state.isPlayingOrBuffering && !report.isWaiting { hasPlayed = true }
        // An ad's own time, duration and rate would make the scrub bar jump.
        guard !report.isAd else { return }
        if wasAd { anchor(report.current, at: now) }
        if report.rate > 0 { rate = report.rate }
        setDuration(report.duration)
        let known = (state == .ended && duration > 0) ? duration : report.current
        anchor(known, at: now)
    }

    /// The page was reloaded: the API's reports count again until the frame
    /// script finds the video element once more.
    public mutating func videoSourceLost() {
        hasVideoSource = false
        isAd = false
    }

    public mutating func requestPlaying(_ playing: Bool, at now: TimeInterval) {
        anchor(seconds(at: now), at: now)
        requestedPlaying = playing
    }

    /// The player never answered the request (an autoplay it refused, a page
    /// still loading): shows what the player is really doing.
    public mutating func settleRequest(at now: TimeInterval) {
        anchor(seconds(at: now), at: now)
        requestedPlaying = nil
    }

    public mutating func seek(to seconds: Double, at now: TimeInterval) {
        anchor(seconds, at: now)
    }

    public mutating func setMuted(_ muted: Bool) {
        isMuted = muted
    }

    private mutating func setDuration(_ value: Double) {
        if value.isFinite, value > 0 { duration = value }
    }

    private mutating func anchor(_ seconds: Double, at now: TimeInterval) {
        anchorSeconds = seconds.isFinite ? max(0, seconds) : 0
        anchorTime = now
    }
}
