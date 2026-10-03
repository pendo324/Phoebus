// "Open in Phoebus" content script.
//
// Two modes, stored in extension storage:
//   automatic (default) - navigate as soon as the page is eligible
//   ask                 - show a real, tappable anchor
//   off                 - do nothing
//
// Automatic is the default because ask mode costs two taps per link: the
// in-page button, then iOS's own confirmation.
//
// The custom scheme is used deliberately. A Universal Link would skip
// iOS's "Open in Phoebus?" confirmation, but it matches on Team ID +
// bundle ID via an AASA file the developer hosts, which a sideloaded
// build cannot satisfy.
(function () {
    "use strict";

    var links = globalThis.PhoebusLinkUtils;
    // Delay before showing the button, so a normal handoff leaves the
    // page before the button can flash onscreen.
    var BUTTON_DELAY_MS = 750;
    // How long to wait for the native handler before falling back to a
    // plain scheme navigation. Short: this is a local XPC round trip,
    // and the cost of waiting is a page that appears to do nothing.
    var NATIVE_OPEN_TIMEOUT_MS = 400;

    var DEFAULT_MODE = "automatic";

    var lastHandledURL = "";
    var button = null;
    var dismissed = false;
    var buttonTimer = null;

    // A declined confirmation, or no app installed, leaves the page
    // exactly where it was, and the script would fire again forever.
    // A marker query parameter is consumed and stripped here;
    // `redditURL` also treats a marked URL as ineligible.
    function consumeFallbackMarker(href) {
        var url;
        try {
            url = new URL(href);
        } catch (error) {
            return false;
        }
        if (!url.searchParams.has(links.fallbackMarker)) {
            return false;
        }
        url.searchParams.delete(links.fallbackMarker);
        try {
            window.history.replaceState(null, "", url.href);
        } catch (error) {
            // Cleaning the address bar is cosmetic; suppressing the
            // loop is not, and `lastHandledURL` below does that.
        }
        lastHandledURL = url.href;
        return true;
    }

    function markedURL(href) {
        var url = new URL(href);
        url.searchParams.set(links.fallbackMarker, "1");
        return url.href;
    }

    function removeButton() {
        if (button && button.parentNode) {
            button.parentNode.removeChild(button);
        }
        button = null;
    }

    function showButton(appURL) {
        removeButton();

        var anchor = document.createElement("a");
        anchor.className = "phoebus-open-button";
        anchor.href = appURL;
        anchor.textContent = "Open in Phoebus";
        // The tap IS the user gesture, which is what keeps iOS willing
        // to hand off to another app.
        anchor.addEventListener("click", function () {
            // Mark before leaving so that if the user declines the
            // system prompt and stays here, the page is no longer
            // eligible and cannot immediately re-prompt.
            try {
                window.history.replaceState(null, "", markedURL(window.location.href));
            } catch (error) {
                // Non-fatal: `dismissed` still suppresses a re-show.
            }
            dismissed = true;
            removeButton();
        });

        var dismiss = document.createElement("span");
        dismiss.className = "phoebus-open-dismiss";
        dismiss.textContent = "\u00d7";
        dismiss.addEventListener("click", function (event) {
            event.preventDefault();
            event.stopPropagation();
            dismissed = true;
            removeButton();
        });
        anchor.appendChild(dismiss);

        (document.body || document.documentElement).appendChild(anchor);
        button = anchor;
    }

    // Hand off to the app.
    //
    // Two routes, tried in order, because they fail in different ways:
    //
    //   1. The native handler. An app extension can call
    //      `NSExtensionContext.open(_:)`, and a request from the appex
    //      to its OWN containing app is not a cross-app launch, so iOS
    //      has no third party to ask about. Whether Safari actually
    //      permits this from a web-extension context is version
    //      dependent, so its success is never assumed.
    //   2. `window.location`, which always works but always raises
    //      iOS's "Open in Phoebus?" confirmation.
    //
    // Route 1 is not awaited indefinitely: if the native side is
    // missing or silent, the user would otherwise sit on a Reddit page
    // that never opens. Anything other than an explicit success falls
    // through to route 2.
    function openApp(appURL) {
        var settled = false;

        function fallback() {
            if (settled) {
                return;
            }
            settled = true;
            window.location.href = appURL;
        }

        var timer = setTimeout(fallback, NATIVE_OPEN_TIMEOUT_MS);

        function handleNativeReply(response) {
            if (settled) {
                return;
            }
            if (response && response.opened === true) {
                // The app is being launched; leaving the page alone
                // avoids a second, redundant handoff attempt.
                settled = true;
                clearTimeout(timer);
                return;
            }
            clearTimeout(timer);
            fallback();
        }

        try {
            var pending = browser.runtime.sendNativeMessage(
                "application.id", { action: "open", url: appURL }
            );
            if (pending && typeof pending.then === "function") {
                pending.then(handleNativeReply, function () {
                    clearTimeout(timer);
                    fallback();
                });
            } else {
                browser.runtime.sendNativeMessage(
                    "application.id", { action: "open", url: appURL },
                    handleNativeReply
                );
            }
        } catch (error) {
            clearTimeout(timer);
            fallback();
        }
    }

    function runCheck(mode) {
        if (mode === "off") {
            return;
        }

        var href = window.location.href;
        if (href === lastHandledURL || consumeFallbackMarker(href)) {
            return;
        }

        var appURL = links.toAppURL(href);
        if (!appURL) {
            removeButton();
            return;
        }

        lastHandledURL = href;

        if (mode === "automatic") {
            // Marked first: if the app is not installed or the user
            // declines, the page we return to is ineligible.
            var marked;
            try {
                marked = markedURL(href);
                window.history.replaceState(null, "", marked);
            } catch (error) {
                // Proceed regardless; `lastHandledURL` still guards.
            }
            openApp(appURL);
            return;
        }

        // Ask mode.
        if (dismissed) {
            return;
        }
        if (buttonTimer) {
            clearTimeout(buttonTimer);
        }
        buttonTimer = setTimeout(function () {
            showButton(appURL);
        }, BUTTON_DELAY_MS);
    }

    function start(mode) {
        runCheck(mode);

        // Reddit is a single-page app: the URL changes without a new
        // document, so a one-shot check would only ever see the first
        // page.
        window.addEventListener("popstate", function () {
            dismissed = false;
            runCheck(mode);
        });

        var observer = new MutationObserver(function () {
            if (window.location.href !== lastHandledURL) {
                dismissed = false;
            }
            runCheck(mode);
        });
        observer.observe(document.documentElement || document, {
            childList: true,
            subtree: true
        });
    }

    function startFromStorage(item) {
        var mode = (item && item.phoebusMode) || DEFAULT_MODE;
        start(mode);
    }

    try {
        var pending = browser.storage.local.get("phoebusMode");
        if (pending && typeof pending.then === "function") {
            pending.then(startFromStorage, function () { start(DEFAULT_MODE); });
        } else {
            browser.storage.local.get(startFromStorage);
        }
    } catch (error) {
        start(DEFAULT_MODE);
    }
})();
