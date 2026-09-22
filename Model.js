// Pure logic for the Dictionary plugin: parsing the daemon's JSON lines.
// No I/O — loads fine in Quickshell and in a plain node test runner
// (`node -e "require('./Model.js').parseLookupLine(...)"`).

// Daemon emits one JSON line per accepted selection:
// {"query":"hello","entries":[{"dict":"...","word":"...","definition":"..."}],"found":true,"x":10,"y":20}
// or {"error":"no-dictionary"} if sdcv/the dictionary db isn't installed.
// `entries` is sdcv's own --json-output passed straight through -- no
// text parsing needed, just HTML-entity decoding (sdcv's stardict source
// data embeds a handful of these, e.g. &quot;) for display.
function decodeEntities(s) {
  if (!s) return s;
  return String(s)
    .replace(/&quot;/g, "\"")
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">");
}

function parseLookupLine(line) {
  var fallback = { query: "", entries: [], found: false, error: "", x: 0, y: 0 };
  if (!line) return fallback;
  var parsed;
  try {
    parsed = JSON.parse(line);
  } catch (e) {
    return fallback;
  }
  if (!parsed || typeof parsed !== "object") return fallback;

  var entries = [];
  if (Array.isArray(parsed.entries)) {
    for (var i = 0; i < parsed.entries.length; i++) {
      var e = parsed.entries[i] || {};
      entries.push({
        dict: decodeEntities(e.dict || e.dictionary || ""),
        text: decodeEntities(e.definition || e.text || ""),
      });
    }
  }

  return {
    query: typeof parsed.query === "string" ? parsed.query : "",
    entries: entries,
    found: !!parsed.found,
    error: typeof parsed.error === "string" ? parsed.error : "",
    x: Number(parsed.x) || 0,
    y: Number(parsed.y) || 0,
  };
}

// True when there's a definition (or a distinct error) worth showing.
function hasContent(lookup) {
  return !!(lookup && (lookup.found || lookup.error));
}

if (typeof module !== "undefined") {
  module.exports = {
    parseLookupLine: parseLookupLine,
    decodeEntities: decodeEntities,
    hasContent: hasContent,
  }
}
