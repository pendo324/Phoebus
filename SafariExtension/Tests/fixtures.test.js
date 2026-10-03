// Half of the extension->app handoff contract.
//
// The extension's only real output is the phoebus:// URL it hands
// to iOS; everything after that is Swift. These two halves are built,
// tested and even RUN in different processes, so nothing else would
// notice if toAppURL started emitting a shape the app no longer parses.
// app-url-fixtures.json pins the exact strings: this file asserts the
// extension still produces them, and PhoebusCoreSmokeTest asserts the
// app still resolves them.
const test = require("node:test");
const assert = require("node:assert");
const fs = require("node:fs");
const path = require("node:path");
const { toAppURL } = require("../Resources/link-utils.js");

const fixtures = JSON.parse(
  fs.readFileSync(path.join(__dirname, "app-url-fixtures.json"), "utf8")
);

test("every fixture page still produces its recorded app URL", () => {
  assert.ok(fixtures.cases.length >= 5);
  for (const c of fixtures.cases) {
    assert.strictEqual(toAppURL(c.page), c.appURL, `for page ${c.page}`);
  }
});

// The popup and the content script store their default separately, and
// neither reads the other. A mismatch is invisible in normal use: the
// popup would show "Ask" ticked while the script opened automatically,
// and a user trying to turn automatic ON would appear to change
// nothing, because it was never off.
test("the popup's default mode matches the content script's", () => {
  const content = fs.readFileSync(
    path.join(__dirname, "..", "Resources", "content.js"), "utf8");
  const popup = fs.readFileSync(
    path.join(__dirname, "..", "Resources", "popup.js"), "utf8");

  const scriptDefault = content.match(/DEFAULT_MODE = "([a-z]+)"/);
  assert.ok(scriptDefault, "content.js should declare DEFAULT_MODE");

  // Every fallback in the popup, not just the first: the storage API
  // has a promise path, a callback path and a throwing path, and an
  // inconsistency between them would only show on a device where that
  // particular path is taken.
  const popupDefaults = [...popup.matchAll(/apply\("([a-z]+)"\)/g)].map((m) => m[1]);
  const popupInline = popup.match(/mode \|\| "([a-z]+)"/);
  assert.ok(popupInline, "popup.js should have an inline default");
  const all = popupDefaults.concat(popupInline[1]);
  assert.ok(all.length >= 3, `expected several popup defaults, saw ${all.length}`);
  for (const value of all) {
    assert.strictEqual(value, scriptDefault[1]);
  }
});
