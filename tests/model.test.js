// node --test tests/*.test.js
const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const M = require("../Model.js")

const sample = name => M.parseLookupLine(fs.readFileSync(path.join(__dirname, "samples", name + ".json"), "utf8").trim())
const card = name => M.buildCard(sample(name))
const allText = c => JSON.stringify(c)

test("templates render to readable text", () => {
  assert.equal(M.cleanLine("(lb en obsolete) A course; a way."), "(obsolete) A course; a way.")
  assert.equal(M.cleanLine("(infl of en go  spast)"), "simple past of go")
  assert.equal(M.cleanLine("(plural of en cat)"), "plural of cat")
  assert.equal(M.cleanLine("hero (w: Don Quixote); noble"), "hero Don Quixote; noble")
  assert.equal(M.cleanLine("(senseid en Q146) A cat."), "A cat.")
  assert.equal(M.cleanLine("(l en doctor)"), "doctor")
  assert.equal(M.cleanLine("belt (gl: used for transport)"), "belt (used for transport)")
  assert.equal(M.cleanLine("(anagrams en a=acst acts cast)"), "")
})

test("nested templates resolve", () => {
  assert.equal(M.cleanLine("(ng A greeting (salutation) said when meeting.)"), "A greeting (salutation) said when meeting.")
  assert.equal(M.cleanLine("(lb en with  (that + indicative) or intransitive) To hold."), "(with (that + indicative) or intransitive) To hold.")
})

test("wiki markup, anchors, refs and raw templates are stripped", () => {
  assert.equal(M.cleanLine("to hang#Verb at the '''cathead'''"), "to hang at the cathead")
  assert.equal(M.cleanLine("cannot&lt;ref&gt;Zwicky&lt;/ref&gt;"), "cannot")
  assert.equal(M.cleanLine("(lb en Internet slang) {{deliberate misspelling of|en|the|addl=x}}."),
    "(Internet slang) deliberate misspelling of the.")
})

test("inflected forms lead with the base word's meaning (went -> go, verb)", () => {
  const c = card("went")
  assert.equal(c.lemmaTitle, "simple past of go")
  assert.equal(c.lemmaBlocks[0].heading, "verb")
  assert.match(c.lemmaBlocks[0].senses[0], /move/i)
})

test("plural follows to the noun (cats -> cat)", () => {
  const c = card("cats")
  assert.equal(c.lemmaTitle, "plural of cat")
  assert.ok(c.lemmaBlocks.every(b => b.heading === "noun"))
  assert.match(allText(c.lemmaBlocks), /Felidae/)
})

test("only English sections: no Translingual symbol, no foreign glosses", () => {
  const c = card("cat")
  const t = allText(c)
  assert.doesNotMatch(t, /ISO 639/)
  assert.doesNotMatch(t, /Translingual/)
  assert.equal(c.blocks[0].heading, "noun")
})

test("teh is a deliberate misspelling of the, not a foreign verb", () => {
  const c = card("teh")
  assert.equal(c.lemmaTitle, "deliberate misspelling of the")
  assert.doesNotMatch(allText(c), /to be like, resemble/)
})

test("no raw markup reaches any card", () => {
  for (const w of ["cat", "went", "teh", "quixotic", "hello", "cats", "stopped"]) {
    const t = allText(card(w))
    assert.doesNotMatch(t, /\((?:lb|l|m|senseid|sid|anagrams|infl of|ng|w|gl) /, w)
    assert.doesNotMatch(t, /\{\{|\}\}|'''|#[A-Z][a-z]|&[a-z]+;/, w)
    assert.doesNotMatch(t, /anagr/, w)
  }
})

test("a nonsense word gets no definitions and no far-fetched suggestions", () => {
  const c = card("asdkjh")
  assert.equal(c.blocks.length, 0)
  assert.equal(c.empty, "No definition found.")
  assert.deepEqual(c.suggestions, [])
})

test("a typo gets the right suggestion first", () => {
  assert.equal(card("serendipty").suggestions[0], "serendipity")
  assert.deepEqual(M.rankSuggestions("recieve", ["receive", "recarve", "recieved"], 1), ["receive"])
  assert.deepEqual(M.rankSuggestions("teh", ["the", "tech", "tea"], 1), ["the"])
})

test("edit distance counts an adjacent swap as one edit", () => {
  assert.equal(M.editDistance("teh", "the"), 1)
  assert.equal(M.editDistance("recieve", "receive"), 1)
  assert.equal(M.editDistance("kitten", "sitting"), 3)
})

test("the card is capped and says how much is hidden", () => {
  const c = M.buildCard(sample("cat"), { maxSenses: 4, perSection: 3 })
  const shown = c.blocks.reduce((n, b) => n + b.senses.length, 0)
  assert.ok(shown <= 4)
  assert.ok(c.hidden > 0)
})

test("stem matches say where they came from", () => {
  const c = M.buildCard({ query: "cattish", word: "cat", via: "stem", found: true,
    entries: [{ dict: "d", word: "cat", text: "n.\nA small feline animal." }], lemma: null, suggestions: [] })
  assert.equal(c.note, "from “cattish”")
})

test("missing dictionary gives an actionable error", () => {
  const c = M.buildCard(M.parseLookupLine('{"error":"no-dictionary"}'))
  assert.match(c.error, /No offline dictionary/)
  assert.equal(M.hasContent(M.parseLookupLine('{"error":"denied-window"}')), false)
})

test("screenAt converts global cursor coordinates to the screen under it", () => {
  // this machine's layout: HDMI-A-1 at 1536,0; eDP-1 at 1474,768 (logical 1536x864)
  const screens = [{ name: "HDMI-A-1", x: 1536, y: 0, width: 1360, height: 768 },
                   { name: "eDP-1", x: 1474, y: 768, width: 1536, height: 864 }]
  const r = M.screenAt(screens, 1900, 1000)
  assert.equal(r.screen.name, "eDP-1")
  assert.deepEqual([r.x, r.y], [426, 232])
  assert.equal(M.screenAt(screens, 2000, 100).screen.name, "HDMI-A-1")
})

test("placeCard flips away from edges instead of covering the pointer", () => {
  assert.deepEqual(M.placeCard(100, 100, 300, 200, 1536, 864, 16, 16), { x: 116, y: 116 })
  const p = M.placeCard(1500, 800, 300, 200, 1536, 864, 16, 16)
  assert.ok(p.x + 300 <= 1500 && p.y + 200 <= 800, "card sits above-left of a pointer near the corner")
})

test("dismiss time scales with length, within bounds", () => {
  assert.equal(M.dismissMs({ blocks: [], lemmaBlocks: [] }), 4000)
  assert.ok(M.dismissMs(card("went")) <= 15000)
})

test("explain lines parse; other lines are not explanations", () => {
  const e = M.parseExplainLine('{"kind":"explain","query":"break a leg","model":"qwen2.5:3b-instruct","text":" Good luck. ","done":true,"x":5,"y":6}')
  assert.equal(e.active, true)
  assert.equal(e.text, "Good luck.")
  assert.equal(e.done, true)
  assert.equal(M.parseExplainLine('{"query":"cat","found":true}'), null)
  assert.equal(M.parseExplainLine("garbage"), null)
})

test("explain errors count as done and carry a message", () => {
  const e = M.parseExplainLine('{"kind":"explain","error":"no-ollama","message":"Local model not available"}')
  assert.equal(e.done, true)
  assert.equal(e.error, "no-ollama")
  assert.match(e.message, /Local model/)
})

test("explain titles are shortened at a word boundary", () => {
  assert.equal(M.explainTitle("break a leg"), "break a leg")
  const t = M.explainTitle("Ceteris paribus, demand falls as price rises and supply grows", 30)
  assert.ok(t.length <= 30 && t.endsWith("…"))
  assert.doesNotMatch(t, /\s…$/)
})

test("model label and dismiss time", () => {
  assert.equal(M.modelLabel("qwen2.5:3b-instruct"), "qwen2.5 3b")
  assert.equal(M.modelLabel("llama3.2:latest"), "llama3.2")
  assert.equal(M.explainDismissMs({ text: "" }), 5000)
  assert.ok(M.explainDismissMs({ text: "x".repeat(2000) }) <= 20000)
})
