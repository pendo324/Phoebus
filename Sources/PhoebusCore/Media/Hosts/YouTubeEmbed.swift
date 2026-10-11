import Foundation

/// The page and identity for playing a YouTube video in a web view: pure
/// string building, kept in PhoebusCore so the smoke test can assert it
/// (the web view itself is `YouTubePlayerView` in PhoebusUI).
public enum YouTubeEmbed {
    /// Name of the script message handler the page reports player errors to.
    public static let messageHandlerName = "phoebusYouTube"

    /// The page's origin, which becomes the embed's `Referer`. YouTube's
    /// embedded player requires an identifying `Referer` and refuses one that
    /// is empty or is youtube.com itself ("This video is unavailable", error
    /// 152-4), so a bundled page is loaded under `https://<bundle id>`, as
    /// YouTube's API client identity requirements describe.
    public static func origin(bundleIdentifier: String?) -> URL {
        let id = (bundleIdentifier ?? "").lowercased()
        return URL(string: "https://\(id.isEmpty ? "phoebus" : id)") ?? URL(string: "https://phoebus")!
    }

    /// True for an 11-character YouTube video ID (letters, digits, `-`, `_`).
    public static func isValidVideoID(_ id: String) -> Bool {
        id.utf8.count == 11 && id.utf8.allSatisfy {
            ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A)
                || $0 == 0x2D || $0 == 0x5F
        }
    }

    /// IFrame Player API error codes after which the video can't play inline:
    /// 100 removed or private, 101 and 150 the owner disabled embedding, 152
    /// and 153 the embed was refused. (2 and 5 are bad parameters and
    /// transient player faults, which a retry or a different link won't fix
    /// by leaving the app.)
    public static func isUnplayableInline(errorCode: Int) -> Bool {
        [100, 101, 150, 152, 153].contains(errorCode)
    }

    /// How often the page reports the playhead while the video plays. The app
    /// carries the time forward between reports (`YouTubePlayback`).
    public static let timeUpdateInterval: TimeInterval = 0.25

    /// A call into the page's player, run with `evaluateJavaScript`.
    public enum Command: Equatable, Sendable {
        case play
        case pause
        case mute
        case unMute
        /// `allowSeekAhead` false while a scrub bar is dragged, true when it
        /// lets go, as the API recommends.
        case seek(seconds: Double, allowSeekAhead: Bool)
        case setPlaybackRate(Double)
        /// A pause in the next moment is undone (the audio session is about to
        /// change); the IFrame API has no such call.
        case keepPlaying

        public var script: String {
            switch self {
            case .play: return "phoebusYT.play()"
            case .pause: return "phoebusYT.pause()"
            case .mute: return "phoebusYT.mute()"
            case .unMute: return "phoebusYT.unMute()"
            case .seek(let seconds, let allowSeekAhead):
                return "phoebusYT.seek(\(Self.literal(seconds)), \(allowSeekAhead))"
            case .setPlaybackRate(let rate):
                return "phoebusYT.setRate(\(Self.literal(rate)))"
            case .keepPlaying: return "void 0"
            }
        }

        /// The same call on the embed frame's script (`frameScript`), which
        /// answers true when the video element took it.
        public var frameScript: String {
            switch self {
            case .play: return "window.__phoebusFrame ? __phoebusFrame.play() : false"
            case .pause: return "window.__phoebusFrame ? __phoebusFrame.pause() : false"
            case .mute: return "window.__phoebusFrame ? __phoebusFrame.mute() : false"
            case .unMute: return "window.__phoebusFrame ? __phoebusFrame.unMute() : false"
            case .seek(let seconds, _):
                return "window.__phoebusFrame ? __phoebusFrame.seek(\(Self.literal(seconds))) : false"
            case .setPlaybackRate(let rate):
                return "window.__phoebusFrame ? __phoebusFrame.setRate(\(Self.literal(rate))) : false"
            case .keepPlaying: return "window.__phoebusFrame ? __phoebusFrame.keepPlaying() : true"
            }
        }

        /// A finite, non-negative number the script can parse in any locale.
        private static func literal(_ value: Double) -> String {
            String(format: "%.3f", value.isFinite ? max(0, value) : 0)
        }
    }

    /// The page for the YouTube IFrame Player API, with YouTube's own
    /// controls off: the app draws its own and drives the player through the
    /// `phoebusYT` functions (`Command`). The page reports `ready`, `state`,
    /// `time`, `rate` and `error` (with the API's error code) to
    /// `messageHandlerName`; once the frame script finds the video element
    /// its `video` reports take over from `state`, `time` and `rate`. Nil for
    /// a video ID that isn't a real one, which would otherwise be spliced into
    /// the script. `captionsWanted` (the system caption setting) loads the
    /// video with captions on (`cc_load_policy: 1`) or off (`0`).
    ///
    /// The player's chrome over the picture is hidden by the frame script.
    public static func html(videoID: String, startSeconds: Int, origin: URL, captionsWanted: Bool) -> String? {
        guard isValidVideoID(videoID) else { return nil }
        let originString = origin.absoluteString
        let intervalMilliseconds = Int(timeUpdateInterval * 1000)
        return """
        <!DOCTYPE html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>html,body{margin:0;height:100%;background:transparent;overflow:hidden}iframe{display:block}</style>
        </head><body><div id="playerHost"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
        var ytPlayer = null, ticker = null;
        function post(message) {
          try { window.webkit.messageHandlers.\(messageHandlerName).postMessage(message); } catch (e) {}
        }
        function postTime() {
          if (!ytPlayer || !ytPlayer.getCurrentTime) { return; }
          post({ event: 'time', current: ytPlayer.getCurrentTime(), duration: ytPlayer.getDuration(), rate: ytPlayer.getPlaybackRate() });
        }
        function startTicker() { if (ticker === null) { ticker = setInterval(postTime, \(intervalMilliseconds)); } }
        function stopTicker() { if (ticker !== null) { clearInterval(ticker); ticker = null; } }
        var phoebusYT = {
          play: function () { if (ytPlayer) { ytPlayer.playVideo(); } },
          pause: function () { if (ytPlayer) { ytPlayer.pauseVideo(); } },
          mute: function () { if (ytPlayer) { ytPlayer.mute(); } },
          unMute: function () { if (ytPlayer) { ytPlayer.unMute(); } },
          setRate: function (rate) { if (ytPlayer) { ytPlayer.setPlaybackRate(rate); } },
          seek: function (seconds, allowSeekAhead) {
            if (!ytPlayer) { return; }
            ytPlayer.seekTo(seconds, allowSeekAhead);
            setTimeout(postTime, 120);
          }
        };
        function onYouTubeIframeAPIReady() {
          ytPlayer = new YT.Player('playerHost', {
            width: '100%', height: '100%', videoId: '\(videoID)',
            playerVars: {
              controls: 0, disablekb: 1, fs: 0, rel: 0, iv_load_policy: 3, modestbranding: 1, playsinline: 1,
              start: \(max(0, startSeconds)), cc_load_policy: \(captionsWanted ? 1 : 0), origin: '\(originString)', widget_referrer: '\(originString)'
            },
            events: {
              onReady: function (e) {
                post({ event: 'ready', duration: e.target.getDuration(), muted: e.target.isMuted() });
              },
              onStateChange: function (e) {
                if (e.data === 1 || e.data === 3) { startTicker(); } else { stopTicker(); }
                post({ event: 'state', code: e.data, current: e.target.getCurrentTime(), duration: e.target.getDuration() });
              },
              onPlaybackRateChange: function (e) { post({ event: 'rate', rate: e.data }); },
              onError: function (e) { post({ event: 'error', code: e.data }); }
            }
          });
        }
        </script></body></html>
        """
    }
}
