/* FileRadar demo logic — plain JS, no dependencies, no network.
   Everything runs locally on the sample library in sample-data.js. */
(function () {
  "use strict";
  var ALL = window.FILERADAR_SAMPLES.slice();
  // Demo "today" is anchored to the newest sample date so relative
  // searches ("last week") behave the same whenever the demo is opened.
  var ANCHOR = new Date("2026-10-25T12:00:00");
  var state = {
    view: "home", filter: null, // {label, test} or null
    query: "", chips: [], // {label, test, removable}
    sort: "date", layout: "grid", size: "M",
    selected: new Set(), trashed: [], moved: {}, // id -> location
    previewId: null,
    dualPane: false, paneLeft: "Documents", paneRight: "Downloads", paneActive: "left",
    tabs: ["Home"], closedTabs: [],
    dropStack: [], folderSizes: {}, // location -> MB number, or "..." while calculating
    favorites: [], // file ids
    savedSearches: [] // {name, query}
  };

  var $ = function (id) { return document.getElementById(id); };
  var main = $("main"), inspector = $("inspector");

  function fmtSize(mb) {
    if (mb >= 1000) return (mb / 1000).toFixed(2).replace(/\.?0+$/, "") + " GB";
    if (mb >= 1) return (mb % 1 === 0 ? mb : mb.toFixed(1)) + " MB";
    return Math.round(mb * 1000) + " KB";
  }
  function fmtDate(d) {
    return new Date(d + "T12:00:00").toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" });
  }
  function hash(s) { var h = 0; for (var i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0; return h; }
  function kindColor(f) {
    var m = { Images: "#e86a3c", Videos: "#7c5cd6", Music: "#d63384", Documents: "#2f7d6b", Archives: "#b7791f", Apps: "#2b7cd3" };
    return m[f.kind] || "#666";
  }
  function esc(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;"); }

  // Abstract, generated thumbnail art — never copied from anywhere.
  function thumbSVG(f) {
    var h = hash(f.id + f.name), c1 = kindColor(f), c2 = "#" + ((h >> 8) & 0xffffff).toString(16).padStart(6, "0");
    var x = 20 + (h % 60), y = 20 + ((h >> 4) % 40);
    var common = '<svg viewBox="0 0 200 150" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Preview art for ' + esc(f.name) + '">'
      + '<defs><linearGradient id="g' + esc(f.id) + '" x1="0" y1="0" x2="1" y2="1">'
      + '<stop offset="0" stop-color="' + c1 + '"/><stop offset="1" stop-color="' + c2 + '"/></linearGradient></defs>'
      + '<rect width="200" height="150" fill="url(#g' + esc(f.id) + ')"/>';
    if (f.kind === "Videos") return common + '<circle cx="100" cy="75" r="28" fill="rgba(255,255,255,.9)"/><polygon points="92,60 122,75 92,90" fill="' + c1 + '"/></svg>';
    if (f.kind === "Music") {
      var bars = ""; for (var i = 0; i < 9; i++) { var bh = 18 + ((h >> i) % 42); bars += '<rect x="' + (22 + i * 20) + '" y="' + (75 - bh / 2) + '" width="10" height="' + bh + '" rx="5" fill="rgba(255,255,255,.9)"/>'; }
      return common + bars + "</svg>";
    }
    if (f.kind === "Documents") return common + '<rect x="30" y="18" width="140" height="114" rx="8" fill="rgba(255,255,255,.95)"/><rect x="45" y="36" width="100" height="8" rx="4" fill="' + c1 + '"/><rect x="45" y="54" width="110" height="6" rx="3" fill="#bbb"/><rect x="45" y="68" width="110" height="6" rx="3" fill="#bbb"/><rect x="45" y="82" width="70" height="6" rx="3" fill="#bbb"/></svg>';
    if (f.kind === "Archives") return common + '<rect x="55" y="35" width="90" height="80" rx="8" fill="rgba(255,255,255,.9)"/><rect x="55" y="60" width="90" height="12" fill="' + c1 + '"/><rect x="95" y="25" width="18" height="18" rx="4" fill="rgba(255,255,255,.9)"/></svg>';
    if (f.kind === "Apps") return common + '<rect x="62" y="28" width="76" height="76" rx="20" fill="rgba(255,255,255,.95)"/><text x="100" y="82" font-size="44" text-anchor="middle" fill="' + c1 + '" font-family="Arial">' + esc(f.name.charAt(0)) + "</text></svg>";
    return common + '<circle cx="' + x + '" cy="' + (y - 10) + '" r="18" fill="rgba(255,255,255,.85)"/><polygon points="0,150 70,70 120,120 160,80 200,130 200,150" fill="rgba(255,255,255,.55)"/></svg>';
  }

  function live() { return ALL.filter(function (f) { return state.trashed.indexOf(f.id) < 0; }); }
  function fileById(id) { return ALL.filter(function (f) { return f.id === id; })[0]; }
  function locationOf(f) { return state.moved[f.id] || f.location; }

  // ---- Search parsing: plain-language input -> visible sentence chips ----
  function parseSearch(q) {
    var s = " " + q.toLowerCase() + " ", chips = [], rest = q;
    function take(pattern, label, test) {
      if (pattern.test(rest.toLowerCase())) { chips.push({ label: label, test: test }); rest = rest.replace(new RegExp(pattern.source, "ig"), " ").replace(/\s+/g, " ").trim(); }
    }
    var kindMap = [["images", "Images"], ["image", "Images"], ["photos", "Images"], ["photo", "Images"], ["pictures", "Images"],
      ["videos", "Videos"], ["video", "Videos"], ["movies", "Videos"],
      ["music", "Music"], ["audio", "Music"], ["songs", "Music"], ["podcast", "Music"],
      ["documents", "Documents"], ["document", "Documents"], ["pdf", "Documents"],
      ["archives", "Archives"], ["archive", "Archives"], ["zip", "Archives"],
      ["apps", "Apps"], ["app", "Apps"]];
    kindMap.forEach(function (pair) {
      var re = new RegExp("\\b" + pair[0] + "\\b", "i");
      if (re.test(rest)) { var k = pair[1]; take(re, k, (function (kk) { return function (f) { return f.kind === kk; }; })(k)); }
    });
    take(/\blast week\b/i, "from last week", function (f) { var d = new Date(f.date + "T12:00:00"); return d >= new Date(ANCHOR - 7 * 864e5) && d <= ANCHOR; });
    take(/\blast month\b/i, "from last month", function (f) { var d = new Date(f.date + "T12:00:00"); return d >= new Date(ANCHOR - 30 * 864e5) && d <= ANCHOR; });
    take(/\byesterday\b/i, "from yesterday", function (f) { return f.date === "2026-10-24"; });
    var m = rest.match(/over\s+(\d+(?:\.\d+)?)\s*(gb|mb)/i);
    if (m) { var mb = parseFloat(m[1]) * (m[2].toLowerCase() === "gb" ? 1000 : 1); take(/over\s+\d+(?:\.\d+)?\s*(gb|mb)/i, "over " + fmtSize(mb), (function (v) { return function (f) { return f.sizeMB > v; }; })(mb)); }
    m = rest.match(/under\s+(\d+(?:\.\d+)?)\s*(gb|mb)/i);
    if (m) { var mb2 = parseFloat(m[1]) * (m[2].toLowerCase() === "gb" ? 1000 : 1); take(/under\s+\d+(?:\.\d+)?\s*(gb|mb)/i, "under " + fmtSize(mb2), (function (v) { return function (f) { return f.sizeMB < v; }; })(mb2)); }
    take(/\blarge\b/i, "large files (over 100 MB)", function (f) { return f.sizeMB > 100; });
    var src = rest.match(/from\s+(safari|mail|iphone|screenshot|app store)/i);
    if (src) { var sv = src[1].toLowerCase(); take(/from\s+(safari|mail|iphone|screenshot|app store)/i, "from " + src[1], (function (v) { return function (f) { return (f.source || "").toLowerCase().indexOf(v) >= 0 || (v === "screenshot" && f.tags.indexOf("screenshot") >= 0); }; })(sv)); }
    take(/\bscreenshots?\b/i, "screenshots", function (f) { return f.tags.indexOf("screenshot") >= 0; });
    take(/\breceipts?\b/i, "receipts", function (f) { return f.tags.indexOf("receipt") >= 0; });
    take(/\bdrafts?\b/i, "drafts", function (f) { return f.tags.indexOf("draft") >= 0; });
    // Remaining words match name, tags, or embedded text.
    var words = rest.split(/\s+/).filter(Boolean);
    words.forEach(function (w) {
      if (w.length < 2) return;
      chips.push({ label: "matching “" + w + "”", test: (function (ww) { return function (f) { var hay = (f.name + " " + f.tags.join(" ") + " " + (f.text || "")).toLowerCase(); return hay.indexOf(ww.toLowerCase()) >= 0; }; })(w) });
    });
    return chips;
  }
  function sentence(chips) {
    if (!chips.length) return "";
    var parts = chips.map(function (c) { return c.label; });
    return "Showing " + parts.join(" · ") + ".";
  }

  function sortFiles(list) {
    var l = list.slice();
    if (state.sort === "name") l.sort(function (a, b) { return a.name.localeCompare(b.name); });
    if (state.sort === "date") l.sort(function (a, b) { return b.date.localeCompare(a.date); });
    if (state.sort === "size") l.sort(function (a, b) { return b.sizeMB - a.sizeMB; });
    if (state.sort === "kind") l.sort(function (a, b) { return a.kind.localeCompare(b.kind) || a.name.localeCompare(b.name); });
    // The sample library records a single date per file, so in this demo
    // both "date added" and "date modified" sort on that date. The full
    // app keeps the two dates separately.
    if (state.sort === "date-added" || state.sort === "date-modified") l.sort(function (a, b) { return b.date.localeCompare(a.date); });
    return l;
  }
  function applyFilters(list) {
    var l = list;
    if (state.filter) l = l.filter(state.filter.test);
    state.chips.forEach(function (c) { l = l.filter(c.test); });
    return sortFiles(l);
  }

  function cardHTML(f) {
    var sel = state.selected.has(f.id) ? " selected" : "";
    return '<button class="card' + sel + '" draggable="true" data-id="' + esc(f.id) + '" aria-label="' + esc(f.name) + ", " + esc(f.kind) + ", " + fmtSize(f.sizeMB) + '" aria-pressed="' + state.selected.has(f.id) + '">'
      + '<span class="thumb">' + thumbSVG(f) + "</span>"
      + '<span class="card-body"><span class="card-name">' + esc(f.name) + '</span><br>'
      + '<span class="card-meta">' + esc(f.kind) + " · " + fmtSize(f.sizeMB) + " · " + fmtDate(f.date) + " · " + esc(locationOf(f)) + "</span></span></button>";
  }
  function bindCards(root) {
    root.querySelectorAll(".card").forEach(function (el) {
      el.addEventListener("click", function (ev) {
        if (ev.metaKey || ev.ctrlKey) { toggleSelect(el.dataset.id); return; }
        showPreview(el.dataset.id);
      });
      el.addEventListener("dragstart", function (ev) {
        var ids = state.selected.has(el.dataset.id) ? Array.from(state.selected) : [el.dataset.id];
        ev.dataTransfer.setData("text/plain", ids.join(","));
        ev.dataTransfer.effectAllowed = "move";
      });
      el.addEventListener("keydown", function (ev) {
        if (ev.key === " " || ev.key === "Enter") { ev.preventDefault(); showPreview(el.dataset.id); }
        if (ev.key === "ArrowRight" || ev.key === "ArrowDown") { ev.preventDefault(); moveFocus(el, 1); }
        if (ev.key === "ArrowLeft" || ev.key === "ArrowUp") { ev.preventDefault(); moveFocus(el, -1); }
      });
    });
    root.querySelectorAll("[data-file]").forEach(function (el) {
      el.addEventListener("click", function () {
        state.selected = new Set([el.dataset.file]);
        showPreview(el.dataset.file);
        root.querySelectorAll("[data-file]").forEach(function (b) {
          b.classList.toggle("active", b.dataset.file === el.dataset.file);
        });
      });
    });
  }
  function moveFocus(el, dir) {
    var cards = Array.from(document.querySelectorAll(".card"));
    var i = cards.indexOf(el) + dir;
    if (cards[i]) cards[i].focus();
  }
  function toggleSelect(id) {
    if (state.selected.has(id)) state.selected.delete(id); else state.selected.add(id);
    render(false);
  }
  function showPreview(id) {
    state.previewId = id; renderInspector();
  }

  function renderInspector() {
    var f = state.previewId ? fileById(state.previewId) : null;
    if (!f) {
      inspector.innerHTML = "<h2>Inspector</h2><p class='subtitle'>Select a file to see its details here. Press Space on a focused file to preview it — the same shortcut as Quick Look on a Mac.</p>"
        + "<p>Tip: try searching <em>images from last week over 100 MB</em> or <em>screenshots</em> in the search box above, or press Cmd/Ctrl + K for every demo action.</p>";
      return;
    }
    var tags = f.tags.map(function (t) { return '<span class="tag">' + esc(t) + "</span>"; }).join("");
    var explain = f.tags.indexOf("screenshot") >= 0 ? "Tagged “screenshot” because this file was captured on screen, not with a camera."
      : f.tags.indexOf("receipt") >= 0 ? "Tagged “receipt” because its text mentions a purchase total."
      : f.tags.indexOf("draft") >= 0 ? "Tagged “draft” because the file name marks it unfinished."
      : "Tags come from the file name and its contents — in plain words, not codes.";
    // Permissions are demo-illustrative only: the sample library carries no
    // real macOS permissions, so the module shows the shape of the panel,
    // not real access data. The full app shows the file's real permissions.
    var isApp = f.kind === "Apps";
    inspector.innerHTML = "<h2>Inspector</h2>"
      + "<details open><summary>Preview</summary><div class='thumb'>" + thumbSVG(f) + "</div><p><b>" + esc(f.name) + "</b></p></details>"
      + "<details open><summary>Info</summary><dl>"
      + "<dt>Kind</dt><dd>" + esc(f.kind) + "</dd>"
      + "<dt>Size</dt><dd>" + fmtSize(f.sizeMB) + "</dd>"
      + "<dt>Date</dt><dd>" + fmtDate(f.date) + "</dd>"
      + "<dt>Location</dt><dd>" + esc(locationOf(f)) + "</dd>"
      + (f.dimensions ? "<dt>Dimensions</dt><dd>" + esc(f.dimensions) + "</dd>" : "")
      + (f.duration ? "<dt>Duration</dt><dd>" + esc(f.duration) + "</dd>" : "")
      + (f.camera ? "<dt>Camera</dt><dd>" + esc(f.camera) + "</dd>" : "")
      + "<dt>Download source</dt><dd>" + esc(f.source || "Local") + "</dd></dl></details>"
      + "<details open><summary>Tags</summary><p>" + tags + "</p><p class='subtitle'>" + explain + "</p></details>"
      + "<details><summary>Permissions</summary><dl>"
      + "<dt>Owner</dt><dd>You (demo sample)</dd>"
      + "<dt>Your access</dt><dd>Read &amp; write</dd>"
      + "<dt>Others</dt><dd>Read-only</dd>"
      + "<dt>Executable</dt><dd>" + (isApp ? "Yes" : "No") + "</dd></dl>"
      + "<p class='subtitle'>Demo sample only — the full Mac app shows this file's real macOS permissions here.</p></details>"
      + "<p><button class='pill' id='favToggle'>" + (state.favorites.indexOf(f.id) >= 0 ? "★ Favorited" : "☆ Favorite") + "</button> "
      + "<button class='pill' id='trashOne'>Move to Trash (demo)</button> "
      + "<button class='pill' id='closePrev'>Close inspector</button></p>";
    $("favToggle").onclick = function () { toggleFavorite(f.id); };
    $("trashOne").onclick = function () { trashFiles([f.id]); };
    $("closePrev").onclick = function () { state.previewId = null; renderInspector(); };
  }

  // Titles are escaped (filter labels derive from sidebar button text).
  // Subtitles are static literals written in this file only — never search
  // input or sample data — so they are intentionally not re-escaped here.
  function toolbarHTML(title, subtitle) {
    return "<h1>" + esc(title) + "</h1><p class='subtitle'>" + subtitle + "</p>"
      + "<div class='toolbar' role='group' aria-label='View controls'>"
      + "<label>Sort <select id='sortSel' aria-label='Sort files'><option value='date'>Date</option><option value='name'>Name</option><option value='size'>Size</option><option value='kind'>Kind</option><option value='date-added'>Date added</option><option value='date-modified'>Date modified</option></select></label>"
      + "<button class='viewbtn' id='gridBtn' aria-pressed='" + (state.layout === "grid") + "'>Grid</button>"
      + "<button class='viewbtn' id='listBtn' aria-pressed='" + (state.layout === "list") + "'>List</button>"
      + "<button class='viewbtn' id='colsBtn' aria-pressed='" + (state.layout === "columns") + "'>Columns</button>"
      + "<label>Card size <input type='range' id='sizeRange' min='0' max='2' step='1' value='" + (state.size === "S" ? 0 : state.size === "L" ? 2 : 1) + "' aria-label='Card size'></label>"
      + (state.selected.size ? "<span><b>" + state.selected.size + " selected.</b> Drag them to a folder or to Trash, or <button class='pill' id='clearSel'>Clear selection</button></span>" : "<span>Tip: hold Cmd (or Ctrl) and click to multi-select. Drag files to a pinned folder or to Trash.</span>")
      + "</div>";
  }
  function bindToolbar() {
    $("sortSel").value = state.sort;
    $("sortSel").onchange = function (e) { state.sort = e.target.value; render(false); };
    $("gridBtn").onclick = function () { state.layout = "grid"; render(false); };
    $("listBtn").onclick = function () { state.layout = "list"; render(false); };
    $("colsBtn").onclick = function () { state.layout = "columns"; render(false); };
    $("sizeRange").oninput = function (e) {
      state.size = ["S", "M", "L"][+e.target.value];
      document.documentElement.style.setProperty("--card", state.size === "S" ? "110px" : state.size === "L" ? "200px" : "150px");
    };
    var cs = $("clearSel"); if (cs) cs.onclick = function () { state.selected.clear(); render(false); };
  }
  function chipsHTML() {
    if (!state.chips.length) return "";
    return '<div class="chips" aria-live="polite">' + state.chips.map(function (c, i) {
      return '<span class="chip">' + esc(c.label) + ' <button aria-label="Remove filter ' + esc(c.label) + '" data-chip="' + i + '">×</button></span>';
    }).join("") + "</div><p class='chip-explain'>" + esc(sentence(state.chips)) + " Each chip is one plain-language filter. Remove one to widen the results.</p>";
  }
  function bindChips() {
    document.querySelectorAll("[data-chip]").forEach(function (b) {
      b.onclick = function () { state.chips.splice(+b.dataset.chip, 1); render(false); };
    });
  }
  function resultsHTML(list) {
    if (!list.length) return "<div class='empty'><p><b>Nothing here yet — and that's fine.</b></p><p>No files match these filters. Try removing a chip, or search for something broader like <em>images</em>.</p></div>";
    if (state.layout === "columns") return columnsHTML(list);
    return "<div class='grid " + state.layout + "' role='list'>" + list.map(cardHTML).join("") + "</div>";
  }

  function columnsHTML(list) {
    var byLoc = {};
    list.forEach(function (f) {
      var loc = locationOf(f);
      if (!byLoc[loc]) byLoc[loc] = [];
      byLoc[loc].push(f);
    });
    var locs = Object.keys(byLoc).sort();
    if (!locs.length) return "<p class='subtitle'>Nothing to show in columns.</p>";
    return "<div class='columns-layout' role='list'>" + locs.map(function (loc) {
      return "<div class='column'><h3 style='font-size:12px;padding:4px 12px;color:var(--muted);margin:0'>" + esc(loc) + "</h3>"
        + byLoc[loc].map(function (f) {
          var fav = state.favorites.indexOf(f.id) >= 0 ? " ★" : "";
          return "<button data-file='" + esc(f.id) + "' class='" + (state.selected.has(f.id) ? "active" : "") + "'>"
            + "<span>" + esc(f.name) + fav + "</span><span class='chev'>›</span></button>";
        }).join("") + "</div>";
    }).join("") + "</div>";
  }

  function renderHome() {
    var files = live();
    var recents = sortFiles(files).slice(0, 8);
    var kinds = ["Images", "Videos", "Music", "Documents", "Archives", "Apps"];
    var totalMB = files.reduce(function (a, f) { return a + f.sizeMB; }, 0);
    var html = "<h1>Home</h1><p class='subtitle'>" + files.length + " sample files · " + fmtSize(totalMB) + " in total · " + state.trashed.length + " in demo Trash. Pick a shelf, or search above.</p>"
      + "<div class='shelf'><h2>Recent files</h2><div class='shelf-row'>" + recents.map(cardHTML).join("") + "</div></div>";
    kinds.forEach(function (k) {
      var items = files.filter(function (f) { return f.kind === k; }).slice(0, 8);
      if (!items.length) return;
      html += "<div class='shelf'><h2>" + esc(k) + " <span class='subtitle'>(" + files.filter(function (f) { return f.kind === k; }).length + ")</span></h2>"
        + "<div class='shelf-row' data-shelf='" + esc(k) + "'>" + items.map(cardHTML).join("") + "</div>"
        + "<p><button class='pill' data-kind='" + esc(k) + "'>See all " + esc(k) + "</button></p></div>";
    });
    main.innerHTML = html;
    document.querySelectorAll("[data-kind]").forEach(function (b) {
      b.onclick = function () { setFilter(b.dataset.kind + " library", function (f) { return f.kind === b.dataset.kind; }); };
    });
    bindCards(main);
  }

  function renderBrowse(title, subtitle) {
    var list = applyFilters(live());
    main.innerHTML = toolbarHTML(title, subtitle) + chipsHTML() + resultsHTML(list);
    bindToolbar(); bindChips(); bindCards(main);
  }

  function renderSearch() {
    var list = applyFilters(live());
    var intro = state.chips.length ? "Results update as you type. Chips below explain, in plain words, what is being filtered."
      : "Try: <em>images from last week over 100 MB</em> · <em>screenshots</em> · <em>receipts</em> · <em>videos over 500 MB</em> · <em>drafts</em>";
    main.innerHTML = toolbarHTML("Search", intro) + chipsHTML() + resultsHTML(list);
    bindToolbar(); bindChips(); bindCards(main);
  }

  function renderTimeline() {
    var files = sortFiles(live());
    var groups = {};
    files.forEach(function (f) { var k = f.date.slice(0, 7); (groups[k] = groups[k] || []).push(f); });
    var html = "<h1>Timeline</h1><p class='subtitle'>Browse by when things happened — the same files, arranged as a story instead of a folder list.</p>";
    Object.keys(groups).sort().reverse().forEach(function (k) {
      var label = new Date(k + "-01T12:00:00").toLocaleDateString(undefined, { year: "numeric", month: "long" });
      html += "<div class='timeline-month'><h2>" + esc(label) + " (" + groups[k].length + ")</h2><div class='grid'>" + groups[k].map(cardHTML).join("") + "</div></div>";
    });
    main.innerHTML = html; bindCards(main);
  }

  function renderDiskMap() {
    var files = live();
    var total = files.reduce(function (a, f) { return a + f.sizeMB; }, 0);
    var sorted = sortFiles(files).sort(function (a, b) { return b.sizeMB - a.sizeMB; });
    var html = "<h1>Disk Map</h1><p class='subtitle'>Each block is sized by file size — big blocks are the files worth deciding about first. " + fmtSize(total) + " in this sample library. Click a block for its details.</p><div class='treemap'>";
    sorted.forEach(function (f) {
      var pct = Math.max(3, Math.round(f.sizeMB / total * 100));
      html += "<button style='flex:1 1 " + pct + "%;background:" + kindColor(f) + "' data-id='" + esc(f.id) + "' aria-label='" + esc(f.name) + ", " + fmtSize(f.sizeMB) + "'><b>" + esc(f.name) + "</b><br>" + fmtSize(f.sizeMB) + "</button>";
    });
    html += "</div><p class='subtitle' style='margin-top:14px'>In the full app, this map covers your real disk. Here it only maps the sample library.</p>";
    main.innerHTML = html;
    main.querySelectorAll(".treemap button").forEach(function (b) { b.onclick = function () { showPreview(b.dataset.id); }; });
  }

  function renderCollections(which) {
    var defs = {
      receipts: { title: "Receipts & Invoices", test: function (f) { return f.tags.indexOf("receipt") >= 0 || f.tags.indexOf("invoice") >= 0; }, note: "Found by reading file names and contents — receipts and invoices grouped together, so tax time is one folder instead of a hunt." },
      drafts: { title: "Unfinished Drafts", test: function (f) { return f.tags.indexOf("draft") >= 0; }, note: "Files marked as drafts. A kind place to pick up where you left off — nothing here is finished, and nothing is judged for it." },
      screenshots: { title: "Screenshots with Text", test: function (f) { return f.tags.indexOf("screenshot") >= 0 && f.hasText; }, note: "Screenshots whose on-screen text was recognised, so you can search what was in the picture, not just its file name." }
    };
    var d = defs[which];
    var list = sortFiles(live().filter(d.test));
    main.innerHTML = toolbarHTML(d.title, esc(d.note)) + resultsHTML(list);
    bindToolbar(); bindCards(main);
  }

  function lockedHTML(title, body, btnLabel) {
    return "<h1>" + esc(title) + "</h1><div class='locked'><p><b>🔒 Locked in this demo.</b></p><p>" + esc(body) + "</p>"
      + "<p><button class='pill' disabled>" + esc(btnLabel || "Requires a paid licence") + "</button></p>"
      + "<p class='subtitle'>This is an honest lock, not a checkout: there is no purchase form in this demo, and nothing here will charge you. In the full Mac app, a paid licence unlocks these tools. Questions: support@metaphasic.net</p></div>";
  }

  function renderMuse() {
    var exampleAction = "Move to Trash";
    var exampleFile = "Example document — tour only";
    main.innerHTML = "<h1>" + esc("Muse — not connected") + "</h1>"
      + "<p class='subtitle'>In the full Mac app, Muse chat lets you ask about your files in plain words and act on them, with your approval, from inside FileRadar. Chat is powered by Muse Spark through Meta's Model API and requires a Meta developer configuration. This demo has no live connection, no account, and no chat session.</p>"
      + "<div class='locked'><p><b>Not connected.</b></p>"
      + "<p>This demo cannot connect to Muse. Connecting requires a Meta developer configuration (see the FileRadar README), and that configuration is not part of this demo. Nothing is sent anywhere from this page.</p>"
      + "<p><button class='pill' id='museConnectBtn'>Connect Muse</button></p>"
      + "<p class='subtitle' id='museConnectNotice' hidden>Connecting requires a Meta developer configuration (see the FileRadar README), and this demo cannot connect. This panel stays not connected — no session has been started and nothing has changed.</p>"
      + "<p class='subtitle'>Your personal Muse app history and memory do not carry over into FileRadar. FileRadar is not affiliated with or endorsed by Meta.</p></div>"
      + "<h2 style='margin-top:22px'>Guided tour — examples only</h2>"
      + "<p class='subtitle'>The two cards below are static examples of what tool cards look like. They are not a live conversation, and neither card does anything in this demo.</p>"
      + "<div class='muse-tour'>"
      + "<div class='tour-card'><p><b>" + esc("Guided tour — example only") + "</b></p>"
      + "<p>Example tool card: <b>" + esc(exampleAction) + "</b></p>"
      + "<p class='subtitle'>File: " + esc(exampleFile) + ". In the full app, a card like this asks for your approval before anything moves, and approved moves go to the Trash, never straight to permanent deletion.</p>"
      + "<p><button class='pill' disabled>Approve (example only)</button> <button class='pill' disabled>Deny (example only)</button></p></div>"
      + "<div class='tour-card'><p><b>" + esc("Guided tour — example only") + "</b></p>"
      + "<p>Example preview card (read-only)</p>"
      + "<p class='subtitle'>File: " + esc(exampleFile) + ". A preview card shows file details for you to read. It changes nothing and moves nothing.</p></div>"
      + "</div>";
    var btn = $("museConnectBtn");
    if (btn) btn.onclick = function () {
      var notice = $("museConnectNotice");
      if (notice) { notice.hidden = false; notice.focus(); }
    };
  }

  function renderFavorites() {
    var wrap = $("favoritesList"); if (!wrap) return;
    if (!state.favorites.length) {
      wrap.innerHTML = "<p style='font-size:12px;color:var(--muted);padding:0 8px'>No favorites yet.</p>";
      return;
    }
    wrap.innerHTML = state.favorites.map(function (id) {
      var f = fileById(id); if (!f) return "";
      return "<button class='navbtn' data-fav='" + esc(id) + "'>⭐ " + esc(f.name) + "</button>";
    }).join("");
    wrap.querySelectorAll("[data-fav]").forEach(function (b) {
      b.onclick = function () {
        state.selected = new Set([b.dataset.fav]);
        state.previewId = b.dataset.fav;
        setFilter("Favorites", function (f) { return state.favorites.indexOf(f.id) >= 0; });
      };
    });
  }
  function renderSavedSearches() {
    var wrap = $("savedSearchesList"); if (!wrap) return;
    if (!state.savedSearches.length) {
      wrap.innerHTML = "<p style='font-size:12px;color:var(--muted);padding:0 8px'>None saved yet.</p>";
      return;
    }
    wrap.innerHTML = state.savedSearches.map(function (s, i) {
      return "<button class='navbtn' data-saved='" + i + "'>🔖 " + esc(s.name) + "</button>";
    }).join("");
    wrap.querySelectorAll("[data-saved]").forEach(function (b) {
      b.onclick = function () {
        var s = state.savedSearches[+b.dataset.saved];
        if (!s) return;
        $("search").value = s.query;
        state.query = s.query;
        state.chips = parseSearch(s.query);
        state.view = "search"; state.filter = null;
        render(false);
      };
    });
  }
  function toggleFavorite(id) {
    var i = state.favorites.indexOf(id);
    if (i >= 0) state.favorites.splice(i, 1); else state.favorites.unshift(id);
    renderFavorites(); render(true);
  }

  function render(keepPreview) {
    if (state.dualPane) {
      renderDualPane();
      if (!keepPreview) renderInspector();
      renderTabs(); renderDropStack(); updateDualPaneBtn();
      return;
    }
    // Sidebar active state + counts are static; views re-render main only.
    if (state.view === "home") renderHome();
    else if (state.view === "search") renderSearch();
    else if (state.view === "timeline") renderTimeline();
    else if (state.view === "diskmap") renderDiskMap();
    else if (state.view === "collections-receipts") renderCollections("receipts");
    else if (state.view === "collections-drafts") renderCollections("drafts");
    else if (state.view === "collections-screenshots") renderCollections("screenshots");
    else if (state.view === "muse") renderMuse();
    else if (state.view === "duplicates") main.innerHTML = lockedHTML("Duplicates", "In the full app, this view groups files that look identical or near-identical so you can keep one copy with confidence. It is intentionally disabled here: the demo never deletes or merges anything for real.", "Duplicates (requires a paid licence)");
    else if (state.view === "cleanup") main.innerHTML = lockedHTML("Clean Up", "In the full app, Clean Up suggests safe decisions — large forgotten downloads, old installers, empty folders — and shows you exactly where each file would go before anything moves. It is intentionally disabled here.", "Clean Up (requires a paid licence)");
    else if (state.view === "sync") main.innerHTML = lockedHTML("Folder Sync & Compare", "In the full app, folder sync compares two folders side by side, previews every change, and only ever moves unwanted files to Trash — never deletes outright. It is intentionally disabled here: the demo never syncs or changes anything for real.", "Folder sync & compare (requires a paid licence)");
    else if (state.view === "archive-browse") main.innerHTML = lockedHTML("Browse Archives as Folders", "In the full app, archives open like folders, so you can browse inside a ZIP or TAR file and extract only what you need. It is intentionally disabled here: the demo lists archives as files and never extracts anything.", "Browse archives (requires a paid licence)");
    else if (state.view === "workspaces") main.innerHTML = lockedHTML("Workspaces", "In the full app, a workspace saves a named layout — sidebar, panes, and tabs — so a project restores in one click. It is intentionally disabled here: the demo keeps one layout per session and nothing is saved.", "Workspaces (requires a paid licence)");
    else if (state.view === "trash") {
      var list = ALL.filter(function (f) { return state.trashed.indexOf(f.id) >= 0; });
      var html = "<h1>Demo Trash</h1><p class='subtitle'>Demo-local only. Nothing on your real Mac is touched. Everything here can be undone.</p>";
      if (!list.length) html += "<div class='empty'><p><b>Trash is empty. Nicely tidy.</b></p><p>Drag a file here to try it — you can always put it back.</p></div>";
      else html += "<div class='grid'>" + list.map(cardHTML).join("") + "</div><p style='margin-top:14px'><button class='pill' id='restoreAll'>Restore all</button></p>";
      main.innerHTML = html; bindCards(main);
      var ra = $("restoreAll"); if (ra) ra.onclick = function () { state.trashed = []; toast("Trash restored."); render(false); };
    }
    else renderBrowse(state.filter ? state.filter.label : "Library", "Everything in the sample library, filtered by your sidebar choice.");
    if (!keepPreview) renderInspector();
    renderTabs(); renderDropStack(); updateDualPaneBtn();
  }

  function setView(v) {
    exitDualPane();
    state.view = v; state.filter = null;
    if (v === "home") state.activeTab = "Home";
    document.querySelectorAll(".navbtn").forEach(function (b) { b.classList.toggle("active", b.dataset.view === v); });
    render(false);
  }
  function setFilter(label, test, location) {
    exitDualPane();
    state.view = "browse"; state.filter = { label: label, test: test, location: location || null };
    document.querySelectorAll(".navbtn").forEach(function (b) { b.classList.remove("active"); });
    render(false);
  }
  function toast(msg, undoFn) {
    var old = document.querySelector(".toast"); if (old) old.remove();
    var t = document.createElement("div"); t.className = "toast"; t.setAttribute("role", "status");
    t.innerHTML = "<span>" + esc(msg) + "</span>" + (undoFn ? "<button>Undo</button>" : "");
    document.body.appendChild(t);
    if (undoFn) t.querySelector("button").onclick = function () { undoFn(); t.remove(); };
    setTimeout(function () { t.remove(); }, 6000);
  }
  function trashFiles(ids) {
    var before = state.trashed.slice();
    ids.forEach(function (id) { if (state.trashed.indexOf(id) < 0) state.trashed.push(id); state.selected.delete(id); });
    toast(ids.length + " file(s) moved to demo Trash.", function () { state.trashed = before; render(false); });
    render(false);
  }

  // Sidebar wiring
  document.querySelectorAll(".navbtn[data-view]").forEach(function (b) {
    b.onclick = function () { setView(b.dataset.view); };
  });
  document.querySelectorAll(".navbtn[data-filter]").forEach(function (b) {
    b.onclick = function () {
      var k = b.dataset.filter;
      if (k === "recents") setFilter("Recents", function (f) { return new Date(f.date + "T12:00:00") >= new Date(ANCHOR - 30 * 864e5); });
      else if (k === "all") setFilter("All Files", function () { return true; });
      else if (k === "large") setFilter("Large Files (over 100 MB)", function (f) { return f.sizeMB > 100; });
      else if (k === "screenshots") setFilter("Screenshots", function (f) { return f.tags.indexOf("screenshot") >= 0; });
      else if (k === "kind") setFilter(b.textContent.trim(), function (f) { return f.kind === b.dataset.kind; });
      else if (k === "pinned") {
        if (state.dualPane) {
          state.paneLeft = b.dataset.kind; openTab(b.dataset.kind); render(false);
        } else {
          setFilter(b.textContent.trim(), function (f) { return locationOf(f) === b.dataset.kind; }, b.dataset.kind);
          openTab(b.dataset.kind);
        }
      }
    };
  });

  // Drop targets: pinned folders, Trash zone, Drop Stack tray, tabs, panes.
  // One handler for every zone: Trash trashes, the tray holds, anything
  // else moves the files to that zone's folder. Stack files dropped on a
  // folder leave the stack once they have landed.
  function clearStackIds(ids) {
    state.dropStack = state.dropStack.filter(function (id) { return ids.indexOf(id) < 0; });
  }
  function handleDrop(zone, ids) {
    if (!ids.length) return;
    var dest = zone.dataset.drop;
    if (dest === "trash") {
      trashFiles(ids); clearStackIds(ids); renderDropStack();
      return;
    }
    if (dest === "dropstack") {
      var added = 0;
      ids.forEach(function (id) { if (state.dropStack.indexOf(id) < 0) { state.dropStack.push(id); added++; } });
      if (added) toast(added + " file(s) held in the Drop Stack. Drag the tray onto a folder to move them all.");
      renderDropStack();
      return;
    }
    var before = {};
    ids.forEach(function (id) { before[id] = state.moved[id]; state.moved[id] = dest; });
    state.selected.clear(); clearStackIds(ids);
    toast(ids.length + " file(s) moved to " + dest + " (demo only).", function () {
      ids.forEach(function (id) { if (before[id] === undefined) delete state.moved[id]; else state.moved[id] = before[id]; });
      render(false);
    });
    render(false);
  }
  function bindDropZone(zone) {
    if (zone.dataset.dropBound) return;
    zone.dataset.dropBound = "1";
    zone.addEventListener("dragover", function (e) { e.preventDefault(); zone.classList.add("drop-target"); });
    zone.addEventListener("dragleave", function () { zone.classList.remove("drop-target"); });
    zone.addEventListener("drop", function (e) {
      e.preventDefault(); zone.classList.remove("drop-target");
      handleDrop(zone, e.dataTransfer.getData("text/plain").split(",").filter(Boolean));
    });
  }
  document.querySelectorAll("[data-drop]").forEach(bindDropZone);

  // Search + keyboard
  var search = $("search");
  search.addEventListener("input", function () {
    exitDualPane();
    state.chips = parseSearch(search.value); state.view = "search"; render(true); renderInspector();
  });
  document.addEventListener("keydown", function (e) {
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") { e.preventDefault(); openPalette(); return; }
    if (e.key === "Escape" && paletteOpen()) { closePalette(); return; }
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "f") { e.preventDefault(); search.focus(); }
    if (e.key === "Escape") { state.previewId = null; renderInspector(); }
    if (state.dualPane && e.altKey && e.key === "1") { e.preventDefault(); focusPane("left"); }
    if (state.dualPane && e.altKey && e.key === "2") { e.preventDefault(); focusPane("right"); }
  });

  // Look + theme toggles
  function setLook(look) {
    document.body.dataset.look = look;
    document.querySelectorAll("[data-look-btn]").forEach(function (b) { b.setAttribute("aria-pressed", b.dataset.lookBtn === look); });
  }
  function setTheme(theme) {
    document.body.dataset.theme = theme;
    document.querySelectorAll("[data-theme-btn]").forEach(function (b) { b.setAttribute("aria-pressed", b.dataset.themeBtn === theme); });
  }
  document.querySelectorAll("[data-look-btn]").forEach(function (b) { b.onclick = function () { setLook(b.dataset.lookBtn); }; });
  document.querySelectorAll("[data-theme-btn]").forEach(function (b) { b.onclick = function () { setTheme(b.dataset.themeBtn); }; });

  // ---- Iteration 1: dual pane, tabs, Drop Stack, folder sizes, palette ----
  var FOLDERS = [];
  ALL.forEach(function (f) { if (FOLDERS.indexOf(f.location) < 0) FOLDERS.push(f.location); });
  FOLDERS.sort();

  function updateDualPaneBtn() {
    var b = $("dualPaneBtn"); if (!b) return;
    b.setAttribute("aria-pressed", state.dualPane ? "true" : "false");
    b.textContent = state.dualPane ? "Dual pane: on" : "Dual pane";
  }
  function exitDualPane() {
    if (state.dualPane) { state.dualPane = false; updateDualPaneBtn(); }
  }
  function toggleDualPane() { state.dualPane = !state.dualPane; render(false); }
  $("dualPaneBtn").onclick = toggleDualPane;

  function paneSizeText(folder) {
    var v = state.folderSizes[folder];
    if (v === "...") return "Size: calculating…";
    if (typeof v === "number") return "Size: " + fmtSize(v);
    return "Size: not calculated yet";
  }
  function renderDualPane() {
    var html = "<h1>Dual pane</h1><p class='subtitle'>Two sample folders side by side. Drag files between panes, or drag the Drop Stack onto a pane. Jump panes with Alt + 1 (left) and Alt + 2 (right). Turn dual pane off to return to your previous view.</p><div class='dualpanes'>";
    [["left", state.paneLeft], ["right", state.paneRight]].forEach(function (pair) {
      var side = pair[0], folder = pair[1];
      var files = sortFiles(live().filter(function (f) { return locationOf(f) === folder; }));
      var opts = FOLDERS.map(function (loc) { return "<option value='" + esc(loc) + "'" + (loc === folder ? " selected" : "") + ">" + esc(loc) + "</option>"; }).join("");
      html += "<div class='pane" + (state.paneActive === side ? " active" : "") + "' data-pane='" + side + "' data-drop='" + esc(folder) + "' tabindex='-1'>"
        + "<div class='pane-head'><label>" + (side === "left" ? "Left pane" : "Right pane") + " <select data-pane-sel='" + side + "' aria-label='" + side + " pane folder'>" + opts + "</select></label>"
        + "<span>" + files.length + " files · <span data-pane-size='" + esc(folder) + "'>" + paneSizeText(folder) + "</span></span>"
        + "<button class='pill' data-pane-focus='" + side + "'>Focus this pane</button></div>"
        + (files.length ? "<div class='grid'>" + files.map(cardHTML).join("") + "</div>"
          : "<div class='empty'><p><b>Nothing in " + esc(folder) + " right now.</b></p><p>Drag files here from the other pane.</p></div>")
        + "</div>";
    });
    html += "</div>";
    main.innerHTML = html;
    bindCards(main);
    document.querySelectorAll("[data-pane-sel]").forEach(function (sel) {
      sel.onchange = function () {
        if (sel.dataset.paneSel === "left") state.paneLeft = sel.value; else state.paneRight = sel.value;
        render(false);
      };
    });
    document.querySelectorAll("[data-pane-focus]").forEach(function (b) {
      b.onclick = function () { focusPane(b.dataset.paneFocus); };
    });
    document.querySelectorAll(".pane[data-drop]").forEach(bindDropZone);
  }
  function focusPane(side) {
    state.paneActive = side;
    document.querySelectorAll(".pane").forEach(function (p) { p.classList.toggle("active", p.dataset.pane === side); });
    var pane = document.querySelector('[data-pane="' + side + '"]');
    if (!pane) return;
    var card = pane.querySelector(".card");
    if (card) card.focus(); else pane.focus();
  }

  // Tabs: one tab per open sample folder, plus Home. Tabs live in memory
  // for the session only — like everything else in this demo, they are
  // lost on reload. Closed tabs can be reopened from the tab bar.
  function currentTab() {
    if (state.dualPane) return state.paneLeft;
    if (state.view === "home") return "Home";
    if (state.view === "browse" && state.filter && state.filter.location) return state.filter.location;
    return null;
  }
  function openTab(label) {
    if (state.tabs.indexOf(label) < 0) state.tabs.push(label);
    renderTabs();
  }
  function activateTab(label) {
    if (label === "Home") { setView("home"); return; }
    if (state.dualPane) { state.paneLeft = label; openTab(label); render(false); return; }
    exitDualPane();
    state.view = "browse";
    state.filter = { label: label, test: (function (loc) { return function (f) { return locationOf(f) === loc; }; })(label), location: label };
    document.querySelectorAll(".navbtn").forEach(function (b) { b.classList.remove("active"); });
    render(false);
  }
  function closeTab(label) {
    var wasCurrent = currentTab() === label;
    state.tabs = state.tabs.filter(function (t) { return t !== label; });
    if (state.closedTabs.indexOf(label) < 0) state.closedTabs.push(label);
    if (!state.tabs.length) state.tabs = ["Home"];
    if (wasCurrent) activateTab(state.tabs[state.tabs.length - 1]);
    else renderTabs();
  }
  function reopenClosedTab() {
    var label = state.closedTabs.pop();
    if (!label) return;
    openTab(label); activateTab(label);
  }
  function renderTabs() {
    var bar = $("tabbar"); if (!bar) return;
    var cur = currentTab();
    var html = state.tabs.map(function (t) {
      return "<span class='tab" + (t === cur ? " active" : "") + "' data-drop='" + esc(t) + "'>"
        + "<button class='tab-btn' data-tab='" + esc(t) + "'>" + esc(t) + "</button>"
        + "<button class='tab-close' data-close='" + esc(t) + "' aria-label='Close tab " + esc(t) + "'>×</button></span>";
    }).join("");
    // The Home tab is not a folder, so it must not accept drops.
    html += "<button class='pill' id='newTabBtn'>＋ New tab</button>";
    if (state.closedTabs.length) html += "<button class='pill' id='reopenTabBtn'>↩ Reopen closed tab (" + state.closedTabs.length + ")</button>";
    bar.innerHTML = html;
    bar.querySelectorAll("[data-tab]").forEach(function (b) { b.onclick = function () { activateTab(b.dataset.tab); }; });
    bar.querySelectorAll("[data-close]").forEach(function (b) { b.onclick = function (e) { e.stopPropagation(); closeTab(b.dataset.close); }; });
    bar.querySelectorAll(".tab[data-drop]").forEach(function (tab) {
      if (tab.querySelector("[data-tab]").dataset.tab === "Home") return;
      bindDropZone(tab);
    });
    var nt = $("newTabBtn");
    if (nt) nt.onclick = function () {
      var next = FOLDERS.filter(function (loc) { return state.tabs.indexOf(loc) < 0; })[0];
      if (!next) { toast("All sample folders are already open as tabs."); return; }
      openTab(next); activateTab(next);
    };
    var rt = $("reopenTabBtn");
    if (rt) rt.onclick = reopenClosedTab;
  }

  // Drop Stack tray: holds files until the whole stack is dropped elsewhere.
  function renderDropStack() {
    var body = $("dropstackBody"); if (!body) return;
    var tray = $("dropstack");
    if (tray) tray.setAttribute("aria-label", "Drop Stack tray, " + state.dropStack.length + " file(s)");
    if (!state.dropStack.length) {
      body.innerHTML = "<p><b>Drop Stack (0)</b></p><p class='subtitle' style='margin:0'>Drag files here to hold them, then drag the tray onto a folder.</p>";
      return;
    }
    var names = state.dropStack.map(function (id) { var f = fileById(id); return f ? esc(f.name) : esc(id); });
    body.innerHTML = "<p><b>Drop Stack (" + state.dropStack.length + ")</b></p><p style='font-size:12px'>" + names.join("<br>") + "</p>"
      + "<p><button class='pill' id='clearStack'>Clear stack</button></p><p class='subtitle' style='margin:0'>Drag this tray onto a pinned folder, a tab, or a dual pane.</p>";
    $("clearStack").onclick = function () { state.dropStack = []; renderDropStack(); toast("Drop Stack cleared."); };
  }
  $("dropstack").addEventListener("dragstart", function (e) {
    if (!state.dropStack.length) { e.preventDefault(); return; }
    e.dataTransfer.setData("text/plain", state.dropStack.join(","));
    e.dataTransfer.effectAllowed = "move";
  });

  // Folder sizes: computed asynchronously, never blocking the UI.
  function renderFolderSizes() {
    var wrap = $("foldersizes"); if (!wrap) return;
    wrap.innerHTML = FOLDERS.map(function (loc) {
      var v = state.folderSizes[loc];
      var txt = v === "..." ? "Calculating…" : (typeof v === "number" ? fmtSize(v) : "—");
      return "<div class='fsize-row'><span>" + esc(loc) + "</span><span>" + txt + "</span><button class='pill' data-calc='" + esc(loc) + "'>Calculate</button></div>";
    }).join("");
    wrap.querySelectorAll("[data-calc]").forEach(function (b) { b.onclick = function () { calcFolderSize(b.dataset.calc); }; });
  }
  function calcFolderSize(loc) {
    if (state.folderSizes[loc] === "...") return;
    state.folderSizes[loc] = "..."; renderFolderSizes();
    // Simulated background work: the total is summed after a short delay
    // so the page stays responsive while it "counts".
    setTimeout(function () {
      var total = live().filter(function (f) { return locationOf(f) === loc; }).reduce(function (a, f) { return a + f.sizeMB; }, 0);
      state.folderSizes[loc] = total; renderFolderSizes();
      document.querySelectorAll("[data-pane-size]").forEach(function (sp) {
        if (sp.dataset.paneSize === loc) sp.textContent = paneSizeText(loc);
      });
    }, 600);
  }
  function calcAllFolderSizes() { FOLDERS.forEach(function (loc, i) { setTimeout(function () { calcFolderSize(loc); }, i * 150); }); }
  $("calcAllSizes").onclick = calcAllFolderSizes;

  // Command palette: every demo action, keyboard-navigable.
  var paletteState = { open: false, query: "", index: 0, shown: [] };
  function paletteOpen() { return paletteState.open; }
  function paletteActions() {
    var acts = [];
    function add(label, hint, run) { acts.push({ label: label, hint: hint, run: run }); }
    add("Go to Home", "view", function () { setView("home"); });
    add("View Timeline", "view", function () { setView("timeline"); });
    add("View Disk Map", "view", function () { setView("diskmap"); });
    add("View Demo Trash", "view", function () { setView("trash"); });
    add("Open Muse (not connected)", "muse", function () { setView("muse"); });
    add("View Recents", "view", function () { setFilter("Recents", function (f) { return new Date(f.date + "T12:00:00") >= new Date(ANCHOR - 30 * 864e5); }); });
    add("View All Files", "view", function () { setFilter("All Files", function () { return true; }); });
    ["Images", "Videos", "Music", "Documents", "Archives", "Apps"].forEach(function (k) {
      add("View " + k, "kind", (function (kk) { return function () { setFilter(kk + " library", function (f) { return f.kind === kk; }); }; })(k));
    });
    add("View Receipts & Invoices", "collection", function () { setView("collections-receipts"); });
    add("View Unfinished Drafts", "collection", function () { setView("collections-drafts"); });
    add("View Screenshots with Text", "collection", function () { setView("collections-screenshots"); });
    FOLDERS.forEach(function (loc) {
      add("Open folder: " + loc, "tab", (function (l) { return function () { openTab(l); activateTab(l); }; })(loc));
    });
    add("Toggle dual pane", "panes", toggleDualPane);
    add("Jump to other pane", "panes", function () {
      if (!state.dualPane) state.dualPane = true;
      render(false); focusPane(state.paneActive === "left" ? "right" : "left");
    });
    add("Focus left pane", "panes", function () { if (!state.dualPane) state.dualPane = true; render(false); focusPane("left"); });
    add("Focus right pane", "panes", function () { if (!state.dualPane) state.dualPane = true; render(false); focusPane("right"); });
    add("Calculate folder sizes", "folders", calcAllFolderSizes);
    add("Clear Drop Stack", "stack", function () { state.dropStack = []; renderDropStack(); toast("Drop Stack cleared."); });
    add("New tab", "tabs", function () { var next = FOLDERS.filter(function (loc) { return state.tabs.indexOf(loc) < 0; })[0]; if (!next) { toast("All sample folders are already open as tabs."); return; } openTab(next); activateTab(next); });
    add("Reopen closed tab", "tabs", reopenClosedTab);
    add("Toggle Colourful look", "appearance", function () { setLook("colourful"); });
    add("Toggle Minimal look", "appearance", function () { setLook("minimal"); });
    add("Switch to Light theme", "appearance", function () { setTheme("light"); });
    add("Switch to Dark theme", "appearance", function () { setTheme("dark"); });
    add("View as Grid", "view", function () { state.layout = "grid"; render(false); });
    add("View as List", "view", function () { state.layout = "list"; render(false); });
    [["Name", "name"], ["Size", "size"], ["Kind", "kind"], ["Date", "date"], ["Date added", "date-added"], ["Date modified", "date-modified"]].forEach(function (pair) {
      add("Sort by " + pair[0], "sort", (function (v) { return function () { state.sort = v; render(false); }; })(pair[1]));
    });
    add("Focus search", "search", function () { search.focus(); });
    add("Clear selection", "selection", function () { state.selected.clear(); render(false); });
    add("Restore all from Trash", "trash", function () { state.trashed = []; toast("Trash restored."); render(false); });
    add("Open Duplicates (locked)", "locked", function () { setView("duplicates"); });
    add("Open Clean Up (locked)", "locked", function () { setView("cleanup"); });
    add("Open Folder Sync & Compare (locked)", "locked", function () { setView("sync"); });
    add("Open Browse Archives (locked)", "locked", function () { setView("archive-browse"); });
    add("Open Workspaces (locked)", "locked", function () { setView("workspaces"); });
    return acts;
  }
  function renderPalette() {
    var q = paletteState.query.toLowerCase();
    var all = paletteActions();
    paletteState.shown = all.filter(function (a) { return !q || a.label.toLowerCase().indexOf(q) >= 0; });
    if (paletteState.index >= paletteState.shown.length) paletteState.index = Math.max(0, paletteState.shown.length - 1);
    var list = $("paletteList");
    if (!paletteState.shown.length) { list.innerHTML = "<p class='subtitle' style='margin:12px 0 0'>No commands match.</p>"; return; }
    list.innerHTML = paletteState.shown.map(function (a, i) {
      return "<button class='palette-item" + (i === paletteState.index ? " active" : "") + "' data-palette='" + i + "'>" + esc(a.label) + "<span>" + esc(a.hint) + "</span></button>";
    }).join("");
    list.querySelectorAll("[data-palette]").forEach(function (b) {
      b.onclick = function () { var a = paletteState.shown[+b.dataset.palette]; closePalette(); if (a) a.run(); };
    });
  }
  function openPalette() {
    paletteState.open = true; paletteState.query = ""; paletteState.index = 0;
    $("palette").hidden = false; renderPalette();
    $("paletteInput").value = ""; $("paletteInput").focus();
  }
  function closePalette() { paletteState.open = false; $("palette").hidden = true; }
  $("paletteBtn").onclick = openPalette;
  $("palette").addEventListener("click", function (e) { if (e.target === $("palette")) closePalette(); });
  $("paletteInput").addEventListener("input", function (e) { paletteState.query = e.target.value; paletteState.index = 0; renderPalette(); });
  $("paletteInput").addEventListener("keydown", function (e) {
    if (e.key === "ArrowDown") { e.preventDefault(); if (paletteState.index < paletteState.shown.length - 1) paletteState.index++; renderPalette(); }
    else if (e.key === "ArrowUp") { e.preventDefault(); if (paletteState.index > 0) paletteState.index--; renderPalette(); }
    else if (e.key === "Enter") { e.preventDefault(); var a = paletteState.shown[paletteState.index]; closePalette(); if (a) a.run(); }
    else if (e.key === "Escape") { e.preventDefault(); closePalette(); }
  });

  // Columns / save-search toolbar buttons (ship-ready demo polish).
  var columnsBtn = $("columnsBtn");
  if (columnsBtn) columnsBtn.onclick = function () {
    state.layout = state.layout === "columns" ? "grid" : "columns";
    columnsBtn.setAttribute("aria-pressed", state.layout === "columns" ? "true" : "false");
    render(false);
  };
  var saveSearchBtn = $("saveSearchBtn");
  if (saveSearchBtn) saveSearchBtn.onclick = function () {
    var q = ($("search").value || "").trim();
    if (!q) { toast("Type a search first, then save it."); return; }
    var name = window.prompt("Name this search", q.slice(0, 40));
    if (!name) return;
    state.savedSearches.unshift({ name: name, query: q });
    renderSavedSearches();
    toast("Saved search “" + name + "” (demo-local only).");
  };

  // Trial banner (mirrors Mac app trial messaging; demo-local, no purchase).
  (function () {
    var bar = document.createElement("div");
    bar.className = "trial-banner";
    bar.innerHTML = "<span><strong>14-day trial</strong> — paid features unlock in the Mac app during trial or after purchase. This page is a sample-library demo only.</span>"
      + "<a class='pill' href='../site/index.html'>Sales site</a>";
    var banner = document.querySelector(".banner");
    if (banner && banner.parentNode) banner.parentNode.insertBefore(bar, banner.nextSibling);
  })();

  setLook("colourful"); setTheme("light");
  render(false);
  renderFolderSizes();
  renderFavorites();
  renderSavedSearches();
})();
