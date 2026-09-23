// Pure logic for the Dictionary plugin: parsing the watcher's JSON lines,
// turning raw Wiktionary/StarDict text into readable senses, ranking
// "did you mean" suggestions, and building the card model the overlay draws.
// No I/O -- loads in Quickshell and in plain node (`node --test tests/`).

// ---- low-level text cleanup ----------------------------------------------

function decodeEntities(s) {
  if (!s) return s
  return String(s)
    .replace(/&quot;/g, "\"")
    .replace(/&apos;/g, "'")
    .replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, " ")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&amp;/g, "&")
}

// Wiktionary's grammatical tags as they survive the StarDict conversion
// ("(infl of en go  spast)").
var INFLECTION_TAGS = {
  "spast": "simple past",
  "past": "past tense",
  "ed-form": "past tense and past participle",
  "s-verb-form": "third-person singular",
  "ing-form": "present participle",
  "pres|ptcp": "present participle",
  "past|ptcp": "past participle",
  "comparative": "comparative",
  "superlative": "superlative",
  "comd": "comparative",
  "supd": "superlative",
  "pl": "plural",
  "p": "plural"
}

// Template name -> what to do with its arguments. Arguments arrive
// space-separated (the converter replaced the template's pipes), with a
// double space where an argument was empty and key=value options.
function stripOptions(args) {
  return args.replace(/\s+[a-z]+[0-9]*=[^ )]*/g, "").replace(/\s{2,}.*$/, "").trim()
}

function formOfPhrase(kind, rest) {
  // kind: "plural of", "infl of", "alt form", ...
  var lemma = stripOptions(rest)
  var tags = ""
  var m = rest.match(/\s{2,}([^)]*)$/)
  if (m) tags = m[1].trim()
  var k = kind.replace(/\s+of$/, "")
  if (k === "infl" || k === "inflection") {
    var label = INFLECTION_TAGS[tags] || INFLECTION_TAGS[tags.split(/\s+/)[0]] || "form"
    return label + " of " + lemma
  }
  var names = {
    "alt form": "alternative form", "alt": "alternative form", "alter": "alternative form",
    "alt case": "alternative case form", "clip": "clipping", "abbr": "abbreviation",
    "syn": "synonym"
  }
  return (names[k] || k) + " of " + lemma
}

// Render one innermost "(...)" group. Returns null to keep it as ordinary
// parenthesised text.
function renderGroup(inner) {
  var m
  // labels: (lb en obsolete)  (lb en with  (that + indicative) ...)  (lbl en ...)
  if ((m = inner.match(/^(?:lb|lbl|lab|label) [a-z-]+ (.*)$/))) {
    var labels = m[1].replace(/\s{2,}/g, " ").trim()
    return labels ? "(" + labels + ")" : ""
  }
  // links / mentions: (l en doctor) (m en lawsuit) (l enm ...)
  if ((m = inner.match(/^(?:l|m|ll|l-self) [a-z-]+ (.*)$/))) return stripOptions(m[1])
  // taxonomic names: (taxfmt Nigella sativa species)
  if ((m = inner.match(/^tax(?:fmt|link) (.*?)(?: (?:species|genus|family|order|subspecies|variety|class))?$/))) return m[1]
  // inline qualifiers / glosses -> keep in parentheses
  if ((m = inner.match(/^(?:gl|gloss|q|qual|qualifier|i|sense):\s*(.*)$/))) return "(" + m[1].trim() + ")"
  // plain text wrappers
  if ((m = inner.match(/^(?:ng|w|cap|vern|nb|n-g|non-gloss|non-gloss definition|ngd):?\s+(.*)$/))) return m[1].trim()
  // noise: sense ids, gender, examples, anagram lists, requests
  if (/^(?:senseid|sid|anagrams|ux|uxi|rfex|rfdef|rfv|attn|g|ref|c|C|top|topics|cln|catlangname) /.test(inner) ||
      /^(?:g|rfex|rfdef|sup|refn):/.test(inner)) return ""
  // form-of: (plural of en cat) (infl of en go  spast) (alt form en ...)
  if ((m = inner.match(/^((?:[a-z]+ ){0,3}of) en (.+)$/)) && m[1] !== "of") return formOfPhrase(m[1], m[2])
  if ((m = inner.match(/^(alt form|alt case|alter|alt) en (.+)$/))) return formOfPhrase(m[1], m[2])
  // another language's form-of / label: drop the language code, keep meaning
  if ((m = inner.match(/^((?:[a-z]+ ){0,3}of) [a-z]{2,3}(?:-[a-z]+)? (.+)$/)) && m[1] !== "of") return formOfPhrase(m[1], m[2])
  return null
}

function renderTemplates(text) {
  var s = String(text || "")
  // Innermost groups first, repeatedly, so nested templates resolve.
  for (var pass = 0; pass < 8; pass++) {
    var touched = false
    s = s.replace(/\(([^()]*)\)/g, function(all, inner) {
      touched = true
      var r = renderGroup(inner)
      // keep as plain parentheses, hidden from later passes so the group
      // around it becomes "innermost" next time
      return r === null ? "\u0001" + inner + "\u0002" : r
    })
    if (!touched) break
  }
  return s.replace(/\u0001/g, "(").replace(/\u0002/g, ")")
}

function cleanLine(line) {
  var s = decodeEntities(line)
  s = s.replace(/<ref[^>]*\/>/g, "").replace(/<ref[^>]*>[\s\S]*?<\/ref>/g, "").replace(/<[^>]+>/g, "")
  // raw templates the converter left: keep form-of ones, drop the rest
  s = s.replace(/\{\{([a-z ]+ of)\|[a-z-]+\|([^|{}]+)[^{}]*\}\}/g, "$1 $2")
  s = s.replace(/\{\{[^{}]*\}\}/g, "")
  s = s.replace(/'''([^']*)'''/g, "$1").replace(/''([^']*)''/g, "$1")
  s = s.replace(/\[https?:\/\/\S+\s+([^\]]+)\]/g, "$1").replace(/\[https?:\/\/\S+\]/g, "")
  s = s.replace(/#[A-Z][A-Za-z_0-9]*/g, "")              // #Etymology_2, #Adjective anchors
  s = renderTemplates(s)
  s = s.replace(/\(\s*\)/g, "").replace(/\s+([,;.])/g, "$1").replace(/\s{2,}/g, " ").trim()
  s = s.replace(/^[,;:]\s*/, "")
  return s
}

// ---- entry structure -----------------------------------------------------

var POS = {
  "n": "noun", "vb": "verb", "a": "adjective", "adv": "adverb", "pron": "pronoun",
  "interj": "interjection", "prep": "preposition", "det": "determiner",
  "conj": "conjunction", "num": "numeral", "part.p": "participle", "part": "particle",
  "phr": "phrase", "postp": "postposition", "sym": "symbol", "classif": "classifier",
  "prop": "proper noun", "prov": "proverb", "abbr": "abbreviation", "contr": "contraction",
  "art": "article", "suffix": "suffix", "prefix": "prefix", "infix": "infix",
  "affix": "affix", "idiom": "idiom", "article": "article", "noun": "noun",
  "verb": "verb", "adjective": "adjective", "adverb": "adverb",
  // sections that are not definitions
  "anagr": null, "alt": null, "roman": null
}

var HEADER_RE = /^(?:([A-Z][^ .]*(?: [A-Z][^ .]*){0,2}) )?([a-z][a-z.]*?)\.?$/

// Language codes a raw line's templates carry: "(lb en nautical ...)",
// "(senseid en Q146)", "(plural of en cat)" -> ["en"]; "(lb nl ...)" -> ["nl"].
var CODE_RE = /\((?:lb|lbl|lab|l|m|ll|senseid|sid|synonyms|syn|ux|alt form|alter|alt|[a-z ]+ of) ([a-z]{2,3}(?:-[a-z]+)?) /g

function codesIn(line) {
  var out = [], m
  CODE_RE.lastIndex = 0
  while ((m = CODE_RE.exec(line))) out.push(m[1])
  return out
}

// Raw definition text -> [{lang, pos, senses: [string]}].
// lang: "en", "foreign" or "" (unknown). The converter's language labels
// ("Translingual n.") are sticky -- once an entry has a Translingual
// section every later section is labelled Translingual, English included --
// so the language comes from the template codes inside each section instead.
function parseDefinition(raw) {
  var sections = []
  var cur = null
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var h = line.match(HEADER_RE)
    if (h && POS.hasOwnProperty(h[2])) {
      cur = { lang: "", label: h[1] || "", pos: POS[h[2]], skip: POS[h[2]] === null, senses: [], en: 0, other: 0, sentence: 0, gloss: 0 }
      sections.push(cur)
      continue
    }
    if (!cur) { cur = { lang: "", label: "", pos: "", skip: false, senses: [], en: 0, other: 0, sentence: 0, gloss: 0 }; sections.push(cur) }
    codesIn(line).forEach(function(c) { if (c === "en") cur.en++; else cur.other++ })
    // Writing style, for sections without language codes: English
    // definitions are sentences ("A course; a way, a path."), translations of
    // foreign words are bare lowercase glosses ("blade", "to stop").
    var body = line.replace(/^\d+\s+/, "").replace(/^#+:?\s*/, "")
    if (/^[A-Z("“]/.test(body) && /[.)”]$/.test(body)) cur.sentence++
    else cur.gloss++
    if (cur.skip) continue
    // usage examples (#:, ##:) and quotations (#*, *) are dropped -- the card
    // has room for meanings
    if (/^(?:\d+\s+)?#*[:*]/.test(line)) continue
    var text = cleanLine(line.replace(/^\d+\s+/, "").replace(/^#+\s*/, ""))
    if (!text || text.length < 2) continue
    // category notes, not meanings: "Terms relating to animals."
    if (/^(?:Terms|Senses|Words) (?:relat|refer)/.test(text)) continue
    cur.senses.push(text)
  }
  sections.forEach(function(s) {
    if (s.en > 0 && s.en >= s.other) s.lang = "en"
    else if (s.other > 0) s.lang = "foreign"
    else s.lang = s.sentence >= s.gloss ? "likely-en" : "foreign"
  })
  // Wiktionary's English block is contiguous (after Translingual, before
  // the other languages): once English has been seen, the first foreign
  // section ends it, and nothing after that counts as English.
  var seenEn = false, ended = false
  sections.forEach(function(s) {
    if (ended) { if (s.lang !== "foreign") s.lang = ""; return }
    if (s.lang === "en" || s.lang === "likely-en") { seenEn = true; s.lang = "en"; return }
    if (s.lang === "foreign" && seenEn) ended = true
  })
  return sections.filter(function(s) { return !s.skip && s.senses.length })
}

// English sections; unknown ones if there is no English; foreign last resort.
function englishFirst(sections) {
  var en = sections.filter(function(s) { return s.lang === "en" })
  // "cat" has a Translingual symbol section ("ISO 639 code for Catalan");
  // it is only worth showing when the word has no other English sense.
  var words = en.filter(function(s) { return s.pos !== "symbol" })
  if (words.length) return words
  if (en.length) return en
  var unknown = sections.filter(function(s) { return !s.lang })
  return unknown.length ? unknown : sections
}

function hasEnglish(sections) {
  return sections.some(function(s) { return s.lang === "en" })
}

// The part of speech a form-of relation points at: "plural of cat" -> noun.
function relationPos(relation) {
  var r = String(relation || "")
  if (/plural/.test(r)) return "noun"
  if (/comparative|superlative/.test(r)) return "adjective"
  if (/past|participle|third-person|simple past|verb/.test(r)) return "verb"
  return ""
}

// ---- suggestions -----------------------------------------------------------

// Optimal-string-alignment distance: insert, delete, substitute, and swap of
// adjacent letters each cost 1 ("teh" -> "the" is 1, not 2).
function editDistance(a, b) {
  a = String(a).toLowerCase(); b = String(b).toLowerCase()
  var m = [], i, j
  for (i = 0; i <= a.length; i++) { m[i] = [i]; for (j = 1; j <= b.length; j++) m[i][j] = i ? 0 : j }
  for (i = 1; i <= a.length; i++) {
    for (j = 1; j <= b.length; j++) {
      var cost = a[i - 1] === b[j - 1] ? 0 : 1
      m[i][j] = Math.min(m[i - 1][j] + 1, m[i][j - 1] + 1, m[i - 1][j - 1] + cost)
      if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1])
        m[i][j] = Math.min(m[i][j], m[i - 2][j - 2] + 1)
    }
  }
  return m[a.length][b.length]
}

function rankSuggestions(query, words, max) {
  var q = String(query || "").toLowerCase()
  var limit = q.length <= 6 ? 1 : 2
  var seen = {}
  var scored = []
  ;(words || []).forEach(function(w) {
    var lw = String(w).toLowerCase()
    if (!lw || lw === q || seen[lw]) return
    seen[lw] = true
    var d = editDistance(q, lw)
    if (d > limit) return
    scored.push({ w: String(w), d: d,
      // tie-breaks: same length, plain lowercase ASCII (likely English), shorter
      len: Math.abs(lw.length - q.length), plain: /^[a-z' -]+$/.test(String(w)) ? 0 : 1 })
  })
  scored.sort(function(x, y) {
    return x.d - y.d || x.plain - y.plain || x.len - y.len || x.w.length - y.w.length
  })
  return scored.slice(0, max || 3).map(function(s) { return s.w })
}

// ---- watcher line -> lookup ---------------------------------------------

function emptyLookup() {
  return { query: "", word: "", via: "", entries: [], lemma: null, suggestions: [],
           parts: [], canExplain: false, found: false, error: "", x: 0, y: 0 }
}

function parseEntries(list) {
  var out = []
  if (!Array.isArray(list)) return out
  for (var i = 0; i < list.length; i++) {
    var e = list[i] || {}
    out.push({
      dict: decodeEntities(e.dict || e.dictionary || ""),
      word: decodeEntities(e.word || ""),
      text: String(e.definition || e.text || "")
    })
  }
  return out
}

function parseLookupLine(line) {
  var fallback = emptyLookup()
  if (!line) return fallback
  var p
  try { p = JSON.parse(line) } catch (e) { return fallback }
  if (!p || typeof p !== "object") return fallback
  var lemma = null
  if (p.lemma && typeof p.lemma === "object" && p.lemma.word) {
    lemma = {
      word: String(p.lemma.word),
      relation: p.lemma.relation ? cleanLine(String(p.lemma.relation)) : "",
      entries: parseEntries(p.lemma.entries)
    }
  }
  return {
    query: typeof p.query === "string" ? p.query : "",
    word: typeof p.word === "string" ? p.word : "",
    via: typeof p.via === "string" ? p.via : "",
    entries: parseEntries(p.entries),
    lemma: lemma,
    suggestions: Array.isArray(p.suggestions) ? p.suggestions.map(String) : [],
    // A phrase with no entry of its own: its words, looked up one by one.
    parts: Array.isArray(p.parts) ? p.parts.map(function(x) { return parseLookupLine(JSON.stringify(x)) })
                                           .filter(function(x) { return x.found }) : [],
    canExplain: !!p.canExplain,
    found: !!p.found,
    error: typeof p.error === "string" ? p.error : "",
    x: Number(p.x) || 0,
    y: Number(p.y) || 0
  }
}

// True when there's a definition, a suggestion, a miss or a distinct error
// worth showing. "denied-window" and "no-word" stay silent.
function hasContent(lookup) {
  if (!lookup) return false
  if (lookup.error) return lookup.error === "no-dictionary"
  return !!lookup.query
}

// ---- card model ------------------------------------------------------------

// Everything the overlay draws, already cleaned and trimmed:
//   {title, note, lemmaTitle, lemmaBlocks, blocks: [{heading, senses}],
//    suggestions, empty, error, hidden}
// For an inflected form ("went") the base word's meaning comes first -- that
// is what the reader wants -- followed by the word's own other senses.
function buildCard(lookup, opts) {
  opts = opts || {}
  var maxSenses = opts.maxSenses || 6
  var perSection = opts.perSection || 3
  var card = { title: "", note: "", blocks: [], lemmaTitle: "", lemmaBlocks: [],
               suggestions: [], parts: [], hint: "", empty: "", error: "", hidden: 0 }
  if (!lookup) return card
  if (lookup.error === "no-dictionary") {
    card.title = "Dictionary"
    card.error = "No offline dictionary installed — see the plugin README."
    return card
  }
  card.title = lookup.word || lookup.query
  if (lookup.via === "stem" && lookup.word) card.note = "from “" + lookup.query + "”"

  var budget = maxSenses
  function sectionsOf(entries) {
    var all = []
    entries.forEach(function(e) { all = all.concat(parseDefinition(e.text)) })
    return all
  }
  function take(sections, limit, dropFormOf) {
    var blocks = []
    sections.forEach(function(s) {
      var senses = s.senses
      if (dropFormOf) senses = senses.filter(function(t) { return !/^(\([^)]*\) )?[a-z -]+ of \S+( \S+)?\.?$/.test(t) })
      if (!senses.length) return
      var n = Math.max(0, Math.min(perSection, limit, budget))
      var shown = senses.slice(0, n)
      card.hidden += senses.length - shown.length
      budget -= shown.length; limit -= shown.length
      if (shown.length) blocks.push({ heading: (s.lang === "foreign" && s.label ? s.label + " " : "") + (s.pos || ""), senses: shown })
    })
    return blocks
  }

  if (!lookup.found) {
    var parts = lookup.parts || []
    if (parts.length) {
      // "premium subscribers": no entry for the phrase, so say what each
      // word means -- briefly, the card has to hold all of them.
      card.empty = "No entry for the whole phrase. Its words:"
      card.parts = parts.map(function(pt) {
        var c = buildCard(pt, { maxSenses: 2, perSection: 2 })
        card.hidden += c.hidden
        return { title: c.title, note: c.lemmaTitle, blocks: c.lemmaBlocks.concat(c.blocks) }
      })
    } else {
      card.suggestions = rankSuggestions(lookup.query, lookup.suggestions, 3)
      card.empty = "No definition found."
    }
    if (lookup.canExplain)
      card.hint = "Press your Define key (Super+Alt+D in the README) to have the local model explain it."
    return card
  }

  var own = sectionsOf(lookup.entries)
  if (!hasEnglish(own)) {
    // Exact hit, but only as a word in other languages ("teh"): say so, and
    // offer the English near-misses the watcher collected.
    card.note = "not an English word"
    card.suggestions = rankSuggestions(lookup.query, lookup.suggestions, 3)
  }

  if (lookup.lemma && lookup.lemma.entries.length) {
    card.lemmaTitle = lookup.lemma.relation || ("see " + lookup.lemma.word)
    var ls = englishFirst(sectionsOf(lookup.lemma.entries))
    var pos = relationPos(card.lemmaTitle)
    var matching = pos ? ls.filter(function(s) { return s.pos === pos }) : []
    card.lemmaBlocks = take(matching.length ? matching : ls, Math.ceil(maxSenses * 2 / 3), false)
    card.blocks = take(englishFirst(own), budget, true)
  } else {
    card.blocks = take(englishFirst(own), budget, false)
  }
  if (!card.blocks.length && !card.lemmaBlocks.length) card.empty = "No readable definition in this dictionary."
  return card
}

// How long a card stays up: long enough to read, never forever.
function dismissMs(card) {
  var chars = 0
  ;(card.blocks || []).concat(card.lemmaBlocks || []).forEach(function(b) {
    b.senses.forEach(function(s) { chars += s.length })
  })
  return Math.max(4000, Math.min(15000, 3000 + chars * 35))
}

// ---- model interpretation --------------------------------------------------

function emptyExplanation() {
  return { active: false, query: "", model: "", text: "", done: false, error: "", message: "", x: 0, y: 0 }
}

// {"kind":"explain",...} line -> explanation, or null if it isn't one.
function parseExplainLine(line) {
  var p
  try { p = JSON.parse(line) } catch (e) { return null }
  if (!p || p.kind !== "explain") return null
  return {
    active: true,
    query: typeof p.query === "string" ? p.query : "",
    model: typeof p.model === "string" ? p.model : "",
    text: typeof p.text === "string" ? p.text.trim() : "",
    done: !!p.done || !!p.error,
    error: typeof p.error === "string" ? p.error : "",
    message: typeof p.message === "string" ? p.message : "",
    x: Number(p.x) || 0,
    y: Number(p.y) || 0
  }
}

// Card title for an explained selection: the selection itself, shortened.
function explainTitle(query, max) {
  var q = String(query || "").replace(/\s+/g, " ").trim()
  max = max || 60
  return q.length > max ? q.slice(0, max - 1).replace(/\s+\S*$/, "") + "…" : q
}

// "qwen2.5:3b-instruct" -> "qwen2.5 3b"
function modelLabel(model) {
  return String(model || "").replace(/:latest$/, "").replace(/-instruct$/, "").replace(":", " ")
}

function explainDismissMs(ex) {
  return Math.max(5000, Math.min(20000, 3500 + String(ex && ex.text || "").length * 45))
}

// ---- screen placement -------------------------------------------------------

// Hyprland reports the cursor in global layout coordinates; each screen
// has its own origin. Returns {screen, x, y} with x/y local to that screen.
// v0.1 used global coordinates on whichever monitor was focused, so on a
// multi-monitor layout the card was clamped into a corner.
function screenAt(screens, gx, gy) {
  var list = screens || []
  for (var i = 0; i < list.length; i++) {
    var s = list[i]
    if (gx >= s.x && gx < s.x + s.width && gy >= s.y && gy < s.y + s.height)
      return { screen: s, x: gx - s.x, y: gy - s.y }
  }
  return list.length ? { screen: list[0], x: 0, y: 0 } : { screen: null, x: 0, y: 0 }
}

// Top-left for a card of w x h near local point (px, py) on an area of
// aw x ah: below-right of the pointer, flipped to the other side if it
// wouldn't fit, then clamped inside the margin.
function placeCard(px, py, w, h, aw, ah, gap, margin) {
  var x = px + gap, y = py + gap
  if (x + w > aw - margin) x = px - gap - w
  if (y + h > ah - margin) y = py - gap - h
  x = Math.max(margin, Math.min(x, aw - w - margin))
  y = Math.max(margin, Math.min(y, ah - h - margin))
  return { x: x, y: y }
}

if (typeof module !== "undefined") {
  module.exports = {
    decodeEntities: decodeEntities,
    renderTemplates: renderTemplates,
    cleanLine: cleanLine,
    parseDefinition: parseDefinition,
    relationPos: relationPos,
    editDistance: editDistance,
    rankSuggestions: rankSuggestions,
    parseLookupLine: parseLookupLine,
    hasContent: hasContent,
    buildCard: buildCard,
    dismissMs: dismissMs,
    screenAt: screenAt,
    emptyExplanation: emptyExplanation,
    parseExplainLine: parseExplainLine,
    explainTitle: explainTitle,
    modelLabel: modelLabel,
    explainDismissMs: explainDismissMs,
    placeCard: placeCard
  }
}
