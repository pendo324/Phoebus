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

    /// The page for the YouTube IFrame Player API. It reports `ready` and
    /// `error` (with the API's error code) to `messageHandlerName`. Nil for a
    /// video ID that isn't a real one, which would otherwise be spliced into
    /// the script. `captionsWanted` (the system caption setting) loads the
    /// video with captions on (`cc_load_policy: 1`) or off (`0`).
    public static func html(videoID: String, startSeconds: Int, origin: URL, captionsWanted: Bool) -> String? {
        guard isValidVideoID(videoID) else { return nil }
        let originString = origin.absoluteString
        return """
        <!DOCTYPE html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>html,body{margin:0;height:100%;background:black;overflow:hidden}iframe{display:block}</style>
        </head><body><div id="player"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
        function post(message) {
          try { window.webkit.messageHandlers.\(messageHandlerName).postMessage(message); } catch (e) {}
        }
        function onYouTubeIframeAPIReady() {
          new YT.Player('player', {
            width: '100%', height: '100%', videoId: '\(videoID)',
            playerVars: { playsinline: 1, start: \(max(0, startSeconds)), cc_load_policy: \(captionsWanted ? 1 : 0), origin: '\(originString)', widget_referrer: '\(originString)' },
            events: {
              onReady: function () { post({ event: 'ready' }); },
              onError: function (e) { post({ event: 'error', code: e.data }); }
            }
          });
        }
        </script></body></html>
        """
    }
}
