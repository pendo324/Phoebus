import Foundation

extension YouTubeEmbed {
    /// The parts of YouTube's own player chrome drawn over the picture, which
    /// the app's controls replace: the desktop player's `ytp-` classes and the
    /// mobile player's controls (an iPhone is served the latter). The error
    /// screen (`.ytp-error`) is not among them: the app reads the API's error
    /// codes instead, but a player that fails still shows why.
    public static let hiddenOverlaySelectors = [
        ".ytp-chrome-top", ".ytp-gradient-top", ".ytp-gradient-bottom", ".ytp-chrome-bottom",
        ".ytp-large-play-button", ".ytp-bezel", ".ytp-bezel-text-wrapper", ".ytp-spinner",
        ".ytp-pause-overlay", ".ytp-watermark", ".ytp-show-cards-title", ".ytp-ce-element",
        ".ytp-cards-teaser", ".ytp-paid-content-overlay", ".ytp-impression-link", ".ytp-youtube-button",
        ".ytp-title", ".ytp-iv-player-content", ".videowall-endscreen", ".ytp-endscreen-content", ".ytp-unmute",
        "#player-controls", "#player-control-overlay", ".ytmCuedOverlayHost", ".ytmVideoInfoHost",
        ".ytwPlayerTopControlsHost", ".ytwPlayerMiddleControlsHost", ".ytwPlayerFullscreenControlsHost",
        ".ytFullscreenVideoRecommendationsHost", "ytm-endscreen-video-renderer",
    ]

    /// The caption layer drawn over the picture.
    public static let captionSelectors = [".ytp-caption-window-container", ".caption-window", ".ytmCaptionsHost"]

    /// Runs in every frame (`forMainFrameOnly: false`) but acts only in
    /// YouTube's embed frame: hides the player's chrome and drives the
    /// `<video>` element directly, reporting its events as `video` messages.
    /// Every call returns whether the video element handled it, so the app can
    /// fall back to the IFrame API. It stays inert when the element isn't
    /// found. Unless `captionsWanted` (the system caption setting), it also
    /// keeps the player's captions off and hides the caption layer.
    public static func frameScript(captionsWanted: Bool) -> String {
        let hidden = (hiddenOverlaySelectors + (captionsWanted ? [] : captionSelectors)).joined(separator: ",")
        return #"""
        (function () {
          'use strict';
          if (window.__phoebusYouTubeFrame) { return; }
          if (!/^(www\.)?youtube(-nocookie)?\.com$/i.test(location.hostname) || location.pathname.indexOf('/embed/') !== 0) { return; }
          window.__phoebusYouTubeFrame = true;
          function post(message) {
            try { window.webkit.messageHandlers.\#(messageHandlerName).postMessage(message); } catch (e) {}
          }
          var style = document.createElement('style');
          style.textContent = '\#(hidden){display:none !important}';
          (document.head || document.documentElement).appendChild(style);

          var video = null, adWatcher = null, watchedPlayer = null, lastAd = false;
          var captionsWanted = \#(captionsWanted ? "true" : "false"), captionResets = [], captionRound = 0;
          var wantMuted = null, wantRate = null, overrides = [], keepPlayingUntil = 0;
          var events = ['loadstart', 'loadedmetadata', 'durationchange', 'canplay', 'play', 'playing', 'pause', 'waiting',
                        'seeked', 'timeupdate', 'ratechange', 'volumechange', 'ended', 'emptied'];
          var reapplyOn = { loadstart: 1, loadedmetadata: 1, emptied: 1, play: 1, playing: 1 };

          function moviePlayer() { return document.getElementById('movie_player'); }
          function adShowing() {
            var player = moviePlayer();
            return !!(player && player.classList.contains('ad-showing'));
          }
          function report(type) {
            if (!video) { return; }
            var duration = video.duration;
            post({
              event: 'video', type: type, current: video.currentTime, duration: isFinite(duration) ? duration : 0,
              rate: video.playbackRate, muted: video.muted || video.volume === 0, paused: video.paused,
              ended: video.ended, waiting: !video.paused && video.readyState < 3, ad: adShowing()
            });
          }
          // YouTube re-mutes and resets the speed when a source changes, so the
          // app's choice is applied again then (and not on every volume change).
          function applyWanted() {
            if (!video) { return; }
            if (wantMuted !== null) {
              var player = moviePlayer();
              try {
                if (player && player.isMuted && player.isMuted() !== wantMuted) { wantMuted ? player.mute() : player.unMute(); }
              } catch (e) {}
              if (video.muted !== wantMuted) { video.muted = wantMuted; }
              if (!wantMuted && video.volume === 0) { video.volume = 1; }
            }
            if (wantRate !== null && video.playbackRate !== wantRate) { video.playbackRate = wantRate; }
          }
          // The player turns its captions back on when a source loads, so
          // they are unloaded again then and shortly after. Rate-limited so a
          // player that keeps loading them can't make this spin.
          function captionsOff() {
            var now = Date.now(), player = moviePlayer();
            captionResets = captionResets.filter(function (time) { return now - time < 5000; });
            if (!player || captionResets.length >= 6) { return; }
            captionResets.push(now);
            try { if (player.unloadModule) { player.unloadModule('captions'); } } catch (e) {}
            try { if (player.setOption) { player.setOption('captions', 'track', {}); } } catch (e) {}
          }
          function keepCaptionsOff() {
            if (captionsWanted || Date.now() - captionRound < 1000) { return; }
            captionRound = Date.now();
            captionsOff();
            [400, 1500, 4000].forEach(function (delay) { setTimeout(captionsOff, delay); });
          }
          // The player itself re-mutes (its muted autoplay) after the app chose
          // sound: the app's choice wins, unless the player keeps refusing it.
          function soundOverridden() {
            if (wantMuted === null || video.muted === wantMuted) { return false; }
            var now = Date.now();
            overrides = overrides.filter(function (time) { return now - time < 2000; });
            if (overrides.length >= 3) { return false; }
            overrides.push(now);
            return true;
          }
          // Changing the sound changes the app's audio session, which can pause
          // the video; a pause right after one is undone, not shown.
          function soundChanging() {
            keepPlayingUntil = (video && !video.paused) ? Date.now() + 1500 : 0;
          }
          function onEvent(event) {
            if (event.target !== video) { return; }
            if (event.type === 'pause' && !video.ended && Date.now() < keepPlayingUntil) {
              var resumed = video.play();
              if (resumed && resumed.catch) { resumed.catch(function () { keepPlayingUntil = 0; report('pause'); }); }
              return;
            }
            if (event.type === 'loadstart' || event.type === 'loadedmetadata' || event.type === 'emptied') { keepCaptionsOff(); }
            if (reapplyOn[event.type] || (event.type === 'volumechange' && soundOverridden())) { applyWanted(); }
            report(event.type);
          }
          function watchAds() {
            var player = moviePlayer();
            if (!player || player === watchedPlayer) { return; }
            watchedPlayer = player;
            if (adWatcher) { adWatcher.disconnect(); }
            adWatcher = new MutationObserver(function () {
              var ad = adShowing();
              if (ad !== lastAd) { lastAd = ad; report('ad'); }
            });
            adWatcher.observe(player, { attributes: true, attributeFilter: ['class'] });
          }
          function attach(element) {
            if (video === element) { return; }
            if (video) { events.forEach(function (name) { video.removeEventListener(name, onEvent); }); }
            video = element;
            events.forEach(function (name) { video.addEventListener(name, onEvent); });
            applyWanted();
            keepCaptionsOff();
            report('attached');
          }
          function look() {
            watchAds();
            if (video && video.isConnected) { return; }
            var found = document.querySelector('video.html5-main-video') || document.querySelector('video');
            if (found) { attach(found); }
          }
          new MutationObserver(look).observe(document.documentElement, { childList: true, subtree: true });
          look();

          window.__phoebusFrame = {
            play: function () {
              if (!video || !video.currentSrc) { return false; }
              var promise = video.play();
              if (promise && promise.catch) { promise.catch(function () { report('pause'); }); }
              return true;
            },
            pause: function () { keepPlayingUntil = 0; if (!video) { return false; } video.pause(); return true; },
            mute: function () { wantMuted = true; if (!video) { return false; } soundChanging(); applyWanted(); report('volumechange'); return true; },
            unMute: function () { wantMuted = false; if (!video) { return false; } soundChanging(); applyWanted(); report('volumechange'); return true; },
            seek: function (seconds) {
              if (!video || !video.currentSrc || adShowing()) { return false; }
              video.currentTime = seconds;
              return true;
            },
            keepPlaying: function () { soundChanging(); return true; },
            setRate: function (rate) { wantRate = rate; if (!video) { return false; } applyWanted(); return true; }
          };
        })();
        """#
    }
}
