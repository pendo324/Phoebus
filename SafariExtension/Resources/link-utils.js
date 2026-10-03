// Pure Reddit URL validation, shared by the content script and tests.
//
// Follows Apollo Reborn's Safari extension rules, each of which is
// defensive work that is easy to omit and hard to notice missing:
//
//   - host-suffix attacks: `evil-reddit.com` must not pass as reddit
//   - credentialed URLs and custom ports are rejected outright
//   - a bare root (`reddit.com/`) is not a destination worth leaving
//     Safari for
//   - media CDN hosts (`i.redd.it`, `v.redd.it`, preview hosts) carry
//     no post id, so they must stay in Safari
//   - only BARE `redd.it` is a post shortener, and only with exactly
//     one path segment
//
// Unlike Reborn, which builds a Universal Link (needs a stable Team ID
// to match an AASA file), this produces the custom scheme so a
// sideloaded build works.
(function (root, factory) {
    "use strict";

    var api = factory();
    if (typeof module === "object" && module.exports) {
        module.exports = api;
    }
    root.PhoebusLinkUtils = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
    "use strict";

    // Consumed and stripped by the content script so a declined open
    // cannot loop forever. See `consumeFallbackMarker`.
    var fallbackMarker = "phoebus_no_open";
    var appScheme = "phoebus";

    function isHostOrSubdomain(host, domain) {
        host = (host || "").toLowerCase();
        // The leading dot is what makes this a SUBDOMAIN test rather
        // than a suffix test: without it, `notreddit.com` passes.
        return host === domain || host.endsWith("." + domain);
    }

    function isRedditWebHost(host) {
        return isHostOrSubdomain(host, "reddit.com");
    }

    // Only bare redd.it is a post shortener. Its media subdomains
    // (i.redd.it, v.redd.it, preview.redd.it) are not navigable posts.
    function isRedditShortHost(host) {
        return (host || "").toLowerCase() === "redd.it";
    }

    function redditURL(value) {
        var url;
        try {
            url = new URL(value);
        } catch (error) {
            return null;
        }

        if ((url.protocol !== "http:" && url.protocol !== "https:") ||
            url.username || url.password || url.port) {
            return null;
        }
        if (!isRedditWebHost(url.hostname) && !isRedditShortHost(url.hostname)) {
            return null;
        }
        if (!url.pathname || url.pathname === "/" ||
            url.searchParams.has(fallbackMarker)) {
            return null;
        }
        if (isRedditShortHost(url.hostname) &&
            url.pathname.split("/").filter(Boolean).length !== 1) {
            return null;
        }

        url.protocol = "https:";
        return url;
    }

    // `phoebus://<host>/<path>` - scheme and host swapped in
    // place, everything else preserved. The app accepts this form
    // directly (`RedditURLTarget.parseAppScheme`), so no encoding or
    // round trip through a server is involved.
    function toAppURL(value) {
        var url = redditURL(value);
        if (!url) {
            return null;
        }
        return appScheme + "://" + url.hostname + url.pathname +
            (url.search || "") + (url.hash || "");
    }

    return {
        fallbackMarker: fallbackMarker,
        appScheme: appScheme,
        isRedditWebHost: isRedditWebHost,
        isRedditShortHost: isRedditShortHost,
        redditURL: redditURL,
        toAppURL: toAppURL
    };
});
