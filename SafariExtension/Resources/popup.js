// Mode switch for the content script.
//
// Stored in extension storage rather than the app's App Group, because
// a Safari content script cannot read the app's defaults: the two live
// in different sandboxes. The app's own settings screen explains where
// this control lives rather than duplicating it.
(function () {
    "use strict";

    var inputs = document.querySelectorAll('input[name="mode"]');

    function apply(mode) {
        Array.prototype.forEach.call(inputs, function (input) {
            // Must match content.js's DEFAULT_MODE, or the popup would
            // show "Ask" selected while the script behaved
            // automatically.
            input.checked = input.value === (mode || "automatic");
        });
    }

    function save(mode) {
        try {
            browser.storage.local.set({ phoebusMode: mode });
        } catch (error) {
            // Nothing useful to do in a popup; the next load re-reads.
        }
    }

    Array.prototype.forEach.call(inputs, function (input) {
        input.addEventListener("change", function () {
            if (input.checked) {
                save(input.value);
            }
        });
    });

    try {
        var pending = browser.storage.local.get("phoebusMode");
        if (pending && typeof pending.then === "function") {
            pending.then(function (item) { apply(item && item.phoebusMode); },
                         function () { apply("automatic"); });
        } else {
            browser.storage.local.get(function (item) {
                apply(item && item.phoebusMode);
            });
        }
    } catch (error) {
        apply("automatic");
    }
})();
