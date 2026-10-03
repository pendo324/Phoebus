// Deterministic URL-validation tests.
//
// The negative cases matter most: each one is an attack or a footgun that
// a naive `host.includes("reddit.com")` check would wave through.
//
// Run: node --test SafariExtension/Tests/*.test.js
const assert = require("node:assert/strict");
const test = require("node:test");

const links = require("../Resources/link-utils.js");

const canonicalVariants = [
    "https://reddit.com/r/apolloapp/comments/13rhvfe/title/",
    "https://www.reddit.com/r/apolloapp/comments/13rhvfe/title/commentid/?context=3",
    "https://old.reddit.com/r/apolloapp/comments/13rhvfe/title/",
    "https://new.reddit.com/r/apolloapp/comments/13rhvfe/title/",
    "https://np.reddit.com/r/apolloapp/comments/13rhvfe/title/",
    "https://m.reddit.com/r/apolloapp/comments/13rhvfe/title/",
    "https://de.reddit.com/r/apolloapp/comments/13rhvfe/title/",
    "https://reddit.com/comments/13rhvfe",
    "https://reddit.com/gallery/13rhvfe",
    "https://reddit.com/r/apolloapp/wiki/index",
    "https://reddit.com/u/username",
    "https://reddit.com/user/username/comments",
    "https://reddit.com/r/apolloapp/s/5Jba9qWfeT",
    "https://reddit.com/u/username/s/opaque-token",
    "https://redd.it/13rhvfe"
];

for (const value of canonicalVariants) {
    test(`accepts ${value}`, () => {
        assert.equal(links.redditURL(value)?.href, value);
        assert.match(links.toAppURL(value), /^phoebus:\/\//);
    });
}

test("builds a scheme+host swapped URL, preserving path, query and fragment", () => {
    assert.equal(
        links.toAppURL("https://www.reddit.com/r/swift/comments/abc/t/?context=3#c1"),
        "phoebus://www.reddit.com/r/swift/comments/abc/t/?context=3#c1"
    );
});

test("upgrades an HTTP Reddit page before building the app URL", () => {
    const source = "http://old.reddit.com/r/apolloapp/comments/13rhvfe/title/";
    assert.equal(
        links.redditURL(source)?.href,
        "https://old.reddit.com/r/apolloapp/comments/13rhvfe/title/"
    );
    assert.equal(
        links.toAppURL(source),
        "phoebus://old.reddit.com/r/apolloapp/comments/13rhvfe/title/"
    );
});

test("does not treat Reddit media hosts as post short links", () => {
    // These carry no post id, so there is nothing to route: they must
    // stay in Safari rather than bouncing to an app that cannot show
    // them.
    for (const value of [
        "https://i.redd.it/image.jpg",
        "https://v.redd.it/video/DASHPlaylist.mpd",
        "https://preview.redd.it/image.png",
        "https://external-preview.redd.it/image.jpg"
    ]) {
        assert.equal(links.redditURL(value), null);
    }
});

test("rejects host-suffix lookalikes", () => {
    // THE case that justifies `isHostOrSubdomain` prepending a dot
    // rather than calling endsWith directly.
    //
    // `reddit.com.attacker.example` would not do: the host allowlist
    // already rejects it. These hosts end with "reddit.com" but are not
    // subdomains of it, which is what distinguishes the two
    // implementations.
    for (const value of [
        "https://evil-reddit.com/r/apolloapp",
        "https://notreddit.com/r/apolloapp",
        "https://myreddit.com/r/apolloapp"
    ]) {
        assert.equal(links.redditURL(value), null, value);
    }
    // And the genuine subdomain must still be accepted, so the rule
    // cannot be satisfied by rejecting everything.
    assert.ok(links.redditURL("https://old.reddit.com/r/apolloapp"));
});

test("rejects malformed redd.it paths", () => {
    assert.equal(links.toAppURL("https://redd.it/abc/extra"), null);
});

test("rejects roots, unsafe schemes, lookalikes, credentials, and fallback loops", () => {
    for (const value of [
        "https://reddit.com/",
        "ftp://reddit.com/r/apolloapp",
        // Attacker-controlled domain that merely CONTAINS the real one
        // as a prefix. Caught by the host allowlist.
        "https://reddit.com.attacker.example/r/apolloapp",
        "https://redd.it.attacker.example/13rhvfe",
        "https://user@reddit.com/r/apolloapp",
        "https://reddit.com:444/r/apolloapp",
        // Our own loop marker must never be re-handled.
        "https://reddit.com/r/apolloapp?phoebus_no_open=1"
    ]) {
        assert.equal(links.redditURL(value), null, value);
    }
});
