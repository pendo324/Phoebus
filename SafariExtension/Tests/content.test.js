// Behavioural tests for the content script, run in a stub DOM.
//
// Proves the things that are easy to get silently wrong:
//   - "ask" mode NEVER navigates on its own
//   - "automatic" mode does
//   - "off" does nothing at all
//   - an ineligible URL is left completely alone
//   - the loop marker is consumed, and a marked URL is not re-handled
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "..", "Resources", "content.js"), "utf8");
const utils = fs.readFileSync(path.join(__dirname, "..", "Resources", "link-utils.js"), "utf8");

// `native` controls the stubbed browser.runtime.sendNativeMessage:
//   "absent"  - the API does not exist (older Safari, or a failed
//               permission), so calling it throws
//   "opened"  - the handler reports it launched the app
//   "refused" - the handler reports it could not
//   "silent"  - the handler never answers, exercising the timeout
async function run(href, mode, native = "absent") {
    const timers = [];
    const nativeMessages = [];
    const appended = [];
    const navigations = [];
    const replacedStates = [];

    function element(tagName) {
        return {
            tagName,
            children: [],
            style: {},
            appendChild(child) { child.parentNode = this; this.children.push(child); },
            addEventListener(type, handler) { (this.handlers ||= {})[type] = handler; },
            removeChild(child) {
                this.children = this.children.filter((c) => c !== child);
            }
        };
    }

    const documentElement = element("html");
    const body = element("body");
    body.appendChild = function (child) {
        child.parentNode = this;
        this.children.push(child);
        appended.push(child);
    };
    body.removeChild = function (child) {
        this.children = this.children.filter((c) => c !== child);
    };

    const location = {
        _href: href,
        get href() { return this._href; },
        set href(value) { navigations.push(value); }
    };

    const window = {
        location,
        addEventListener() {},
        history: {
            replaceState(_state, _title, url) {
                replacedStates.push(url);
                location._href = url;
            }
        },
        setTimeout(callback, delay) {
            timers.push({ callback, delay });
            return timers.length;
        },
        clearTimeout() {}
    };

    const sandbox = {
        window,
        document: {
            documentElement,
            body,
            createElement: element
        },
        URL,
        MutationObserver: function () { this.observe = function () {}; },
        setTimeout: window.setTimeout,
        clearTimeout: window.clearTimeout,
        // Safari's WebExtension API is promise-based, and the script
        // prefers that path (falling back to the callback form for
        // Chrome-style implementations), so the stub must offer it.
        browser: {
            runtime: native === "absent" ? undefined : {
                sendNativeMessage(_id, message) {
                    nativeMessages.push(message);
                    if (native === "silent") {
                        return new Promise(function () {});
                    }
                    return Promise.resolve({ opened: native === "opened" });
                }
            },
            storage: {
                local: {
                    get(key) {
                        return Promise.resolve({ phoebusMode: mode });
                    }
                }
            }
        }
    };
    sandbox.globalThis = sandbox;

    vm.createContext(sandbox);
    vm.runInContext(utils, sandbox);
    vm.runInContext(source, sandbox);
    // Let the storage promise settle before the caller asserts.
    for (let i = 0; i < 6; i += 1) {
        await Promise.resolve();
    }

    return {
        timers,
        nativeMessages,
        appended,
        navigations,
        replacedStates,
        flushTimers() { timers.forEach((t) => t.callback()); }
    };
}

const POST = "https://www.reddit.com/r/swift/comments/abc/title/";

test("ask mode never navigates on its own", async () => {
    const result = await run(POST, "ask");
    result.flushTimers();
    assert.deepEqual(result.navigations, []);
});

test("ask mode shows a real anchor to the app scheme, after a delay", async () => {
    const result = await run(POST, "ask");
    // Nothing before the delay elapses.
    assert.equal(result.appended.length, 0);
    assert.equal(result.timers[0].delay, 750);
    result.flushTimers();
    assert.equal(result.appended.length, 1);
    assert.equal(result.appended[0].tagName, "a");
    assert.equal(
        result.appended[0].href,
        "phoebus://www.reddit.com/r/swift/comments/abc/title/"
    );
});

test("automatic mode navigates to the app scheme", async () => {
    const result = await run(POST, "automatic");
    assert.deepEqual(result.navigations, [
        "phoebus://www.reddit.com/r/swift/comments/abc/title/"
    ]);
    // ...and marks the page first, so a declined prompt cannot loop.
    assert.ok(result.replacedStates[0].includes("phoebus_no_open=1"));
});

test("off mode does nothing", async () => {
    const result = await run(POST, "off");
    result.flushTimers();
    assert.deepEqual(result.navigations, []);
    assert.equal(result.appended.length, 0);
});

test("an ineligible URL is left alone in every mode", async () => {
    for (const mode of ["ask", "automatic"]) {
        // A media host: no post id to route.
        const result = await run("https://i.redd.it/image.jpg", mode);
        result.flushTimers();
        assert.deepEqual(result.navigations, [], mode);
        assert.equal(result.appended.length, 0, mode);
    }
});

test("a marked URL is not handled again", async () => {
    const marked = POST + "?phoebus_no_open=1";
    const result = await run(marked, "automatic");
    assert.deepEqual(result.navigations, []);
});

test("the loop marker is stripped from the address bar", async () => {
    // TWO independent guards stop the loop: `redditURL` treats a marked
    // URL as ineligible, and `consumeFallbackMarker` strips it.
    // The first already blocks navigation, so this asserts the job only
    // the second does: leaving a clean URL behind rather than a
    // permanent `?phoebus_no_open=1` in the address bar.
    const marked = POST + "?phoebus_no_open=1";
    const result = await run(marked, "automatic");
    assert.ok(result.replacedStates.length > 0,
              "expected the marker to be stripped via replaceState");
    assert.ok(!result.replacedStates[0].includes("phoebus_no_open"),
              `marker still present: ${result.replacedStates[0]}`);
});

// --- Handing off without the system prompt ---------------------------
//
// A plain scheme navigation always raises iOS's "Open in Phoebus?"
// confirmation, because Safari is launching a different app. The appex
// is packaged INSIDE the app, so it can ask to open its own container
// via NSExtensionContext.open, which is not a cross-app launch. Whether
// Safari allows that from a web-extension context is undocumented and
// version dependent, so every failure shape below must still end up in
// the app.

test("automatic mode asks the native handler first", async () => {
    const result = await run(POST, "automatic", "opened");
    // Field-by-field, not deepEqual: these objects are created inside
    // the vm sandbox, so they have a different Object prototype and
    // deepStrictEqual rejects them as "not reference-equal" even when
    // every value matches.
    assert.equal(result.nativeMessages.length, 1);
    assert.equal(result.nativeMessages[0].action, "open");
    assert.equal(result.nativeMessages[0].url,
                 "phoebus://www.reddit.com/r/swift/comments/abc/title/");
});

test("a successful native open does not also navigate", async () => {
    // Navigating as well would hand off twice, and the second one is
    // exactly the prompt this path exists to avoid.
    const result = await run(POST, "automatic", "opened");
    assert.deepEqual(result.navigations, []);
});

test("a refused native open falls back to the scheme", async () => {
    const result = await run(POST, "automatic", "refused");
    assert.deepEqual(result.navigations, [
        "phoebus://www.reddit.com/r/swift/comments/abc/title/"
    ]);
});

test("a missing native API falls back to the scheme", async () => {
    const result = await run(POST, "automatic", "absent");
    assert.deepEqual(result.navigations, [
        "phoebus://www.reddit.com/r/swift/comments/abc/title/"
    ]);
});

test("a silent native handler falls back once the timeout fires", async () => {
    const result = await run(POST, "automatic", "silent");
    // Nothing yet: the script is waiting on the native reply.
    assert.deepEqual(result.navigations, []);
    const timer = result.timers.find((t) => t.delay === 400);
    assert.ok(timer, "expected a native-open timeout timer");
    timer.callback();
    assert.deepEqual(result.navigations, [
        "phoebus://www.reddit.com/r/swift/comments/abc/title/"
    ]);
});

test("a late native reply cannot navigate twice", async () => {
    // The timeout has already navigated; a reply arriving afterwards
    // must not fire a second handoff.
    const result = await run(POST, "automatic", "silent");
    result.timers.filter((t) => t.delay === 400).forEach((t) => t.callback());
    result.timers.filter((t) => t.delay === 400).forEach((t) => t.callback());
    assert.equal(result.navigations.length, 1);
});

test("automatic is the default when no mode has been chosen", async () => {
    // Ask mode costs two taps per link (in-page button, then the system
    // prompt), so the default must be automatic.
    const result = await run(POST, undefined);
    assert.deepEqual(result.navigations, [
        "phoebus://www.reddit.com/r/swift/comments/abc/title/"
    ]);
    assert.equal(result.appended.length, 0);
});

test("ask mode never asks the native handler either", async () => {
    const result = await run(POST, "ask", "opened");
    result.flushTimers();
    assert.deepEqual(result.nativeMessages, []);
});
