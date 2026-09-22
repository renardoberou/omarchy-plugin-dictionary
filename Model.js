// Pure logic for the Dictionary plugin: parsing the daemon's JSON lines
// and sdcv's raw text output. No I/O — loads fine in Quickshell and in a
// plain node test runner (`node -e "require('./Model.js').parseLookupLine(...)"`).

// Daemon emits one JSON line per accepted selection:
// {"query":"hello","raw":"<sdcv text>","found":true,"x":10,"y":20}
// or {"error":"no-dictionary"} if sdcv/the dictionary db isn't installed.
function parseLookupLine(line) {
  var fallback = { query: "", raw: "", found: false, error: "", x: 0, y: 0 };
  if (!line) return fallback;
  var parsed;
  try {
    parsed = JSON.parse(line);
  } catch (e) {
    return fallback;
  }
  if (!parsed || typeof parsed !== "object") return fallback;
  return {
    query: typeof parsed.query === "string" ? parsed.query : "",
    raw: typeof parsed.raw === "string" ? parsed.raw : "",
    found: !!parsed.found,
    error: typeof parsed.error === "string" ? parsed.error : "",
    x: Number(parsed.x) || 0,
    y: Number(parsed.y) || 0,
  };
}

// sdcv's non-interactive output is human-formatted text, not JSON. Typical
// shape (verified against `sdcv -n <word>` real output — see bin/omarchy-dict-watch
// header comment for the exact invocation used):
//
//   Found 2 items, similar to hello.
//   -->hello
//   -->WordNet
//   n 1: an expression of greeting
//   ...
//   -->hello
//   -->Some Other Dictionary
//   ...
//
// Strategy: split on lines starting with "-->", treat every *pair* of such
// lines as (word, dictionary-name) followed by body text until the next
// "-->word" pair or end of input. Returns entries grouped by dictionary so
// the card can show "WordNet: ..." style attribution.
function parseSdcvOutput(raw) {
  if (!raw) return [];
  var lines = String(raw).split("\n");
  var entries = [];
  var i = 0;
  // Skip the "Found N items..." / "Nothing similar to..." summary line(s)
  // up to the first "-->" marker.
  while (i < lines.length && lines[i].indexOf("-->") !== 0) i++;

  while (i < lines.length) {
    if (lines[i].indexOf("-->") !== 0) { i++; continue; }
    // word line, then dictionary-name line
    i++; // skip word line (redundant with query, shown separately by the caller)
    if (i >= lines.length || lines[i].indexOf("-->") !== 0) continue;
    var dict = lines[i].slice(3).trim();
    i++;
    var bodyLines = [];
    while (i < lines.length && lines[i].indexOf("-->") !== 0) {
      bodyLines.push(lines[i]);
      i++;
    }
    var body = bodyLines.join("\n").trim();
    if (body) entries.push({ dict: dict, text: body });
  }
  return entries;
}

// True when there's a definition (or a distinct error) worth showing.
function hasContent(lookup) {
  return !!(lookup && (lookup.found || lookup.error));
}

if (typeof module !== "undefined") {
  module.exports = {
    parseLookupLine: parseLookupLine,
    parseSdcvOutput: parseSdcvOutput,
    hasContent: hasContent,
  }
}
