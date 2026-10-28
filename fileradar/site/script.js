// FileRadar site script: theme toggles + honest pricing logic.
// No analytics, no tracking, no external requests.
(function () {
  "use strict";
  var cfg = window.FileRadarConfig || {};
  var root = document.documentElement;

  // --- Theme: look (modern / elegant / colourful / minimal) + mode (light / dark) ---
  var LOOKS = ["modern", "elegant", "colourful", "minimal"];
  function applyTheme() {
    // Stored values are theme names only; anything else falls back to the
    // defaults instead of being applied to the document.
    var look = localStorage.getItem("fileradar-look");
    if (LOOKS.indexOf(look) < 0) look = "modern";
    var mode = localStorage.getItem("fileradar-mode");
    if (mode !== "light" && mode !== "dark") mode = null;
    if (!mode) {
      mode = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
    }
    root.setAttribute("data-look", look);
    root.setAttribute("data-theme", mode);
    document.querySelectorAll("[data-look-btn]").forEach(function (b) {
      b.setAttribute("aria-pressed", b.getAttribute("data-look-btn") === look ? "true" : "false");
    });
    document.querySelectorAll("[data-mode-btn]").forEach(function (b) {
      b.setAttribute("aria-pressed", b.getAttribute("data-mode-btn") === mode ? "true" : "false");
    });
  }
  document.querySelectorAll("[data-look-btn]").forEach(function (b) {
    b.addEventListener("click", function () {
      localStorage.setItem("fileradar-look", b.getAttribute("data-look-btn"));
      applyTheme();
    });
  });
  document.querySelectorAll("[data-mode-btn]").forEach(function (b) {
    b.addEventListener("click", function () {
      localStorage.setItem("fileradar-mode", b.getAttribute("data-mode-btn"));
      applyTheme();
    });
  });
  applyTheme();

  // --- Pricing: driven entirely by config.js, never hardcoded here ---
  var launchPrice = cfg.LAUNCH_PRICE_USD || 8;
  var regularPrice = cfg.REGULAR_PRICE_USD || 19;
  var windowDays = cfg.LAUNCH_WINDOW_DAYS || 60;
  var launchDate = cfg.LAUNCH_DATE ? new Date(cfg.LAUNCH_DATE + "T00:00:00") : null;
  var statusEl = document.getElementById("price-status");
  var currentEl = document.getElementById("current-price");
  var windowEl = document.getElementById("price-window");
  if (statusEl && currentEl && windowEl) {
    if (!launchDate || isNaN(launchDate.getTime())) {
      currentEl.textContent = "$" + launchPrice + " at launch";
      statusEl.textContent = "Launch date not yet announced. The launch price window has not started. " +
        "When a launch date is set in the site configuration, the $" + launchPrice +
        " price will apply for the first " + windowDays + " days after launch, then the price becomes $" +
        regularPrice + ".";
      windowEl.textContent = "Launch window: first " + windowDays + " days after the launch date (to be announced).";
    } else {
      var now = new Date();
      var end = new Date(launchDate.getTime() + windowDays * 86400000);
      var fmt = { year: "numeric", month: "long", day: "numeric" };
      if (now < launchDate) {
        currentEl.textContent = "$" + launchPrice + " at launch";
        statusEl.textContent = "Launch is set for " + launchDate.toLocaleDateString(undefined, fmt) +
          ". The $" + launchPrice + " launch price will apply for the first " + windowDays +
          " days after launch, then the price becomes $" + regularPrice + ".";
        windowEl.textContent = "Launch window: " + launchDate.toLocaleDateString(undefined, fmt) +
          " to " + end.toLocaleDateString(undefined, fmt) + ".";
      } else if (now < end) {
        var daysLeft = Math.ceil((end - now) / 86400000);
        currentEl.textContent = "$" + launchPrice;
        statusEl.textContent = "Launch price is active. " + daysLeft + " day(s) remain in the " +
          windowDays + "-day launch window; after " + end.toLocaleDateString(undefined, fmt) +
          ", the price becomes $" + regularPrice + ".";
        windowEl.textContent = "Launch window ends " + end.toLocaleDateString(undefined, fmt) + ".";
      } else {
        currentEl.textContent = "$" + regularPrice;
        statusEl.textContent = "The " + windowDays + "-day launch window ended on " +
          end.toLocaleDateString(undefined, fmt) + ". The current price is $" + regularPrice + ".";
        windowEl.textContent = "Launch window ended " + end.toLocaleDateString(undefined, fmt) + ".";
      }
    }
  }

  // --- Buy button: honest placeholder, no payment is taken here ---
  var buyBtn = document.getElementById("buy-btn");
  var buyNotice = document.getElementById("buy-notice");
  if (buyBtn && buyNotice) {
    buyBtn.addEventListener("click", function () {
      buyNotice.hidden = false;
      buyNotice.focus();
    });
  }

  // --- Footer year ---
  var yearEl = document.getElementById("year");
  if (yearEl) yearEl.textContent = String(new Date().getFullYear());
})();
