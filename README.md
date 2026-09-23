# Dictionary

An offline dictionary for Omarchy. Highlight a word anywhere (or press a key)
and a definition card appears next to the pointer, on the monitor you're
using. Highlight a phrase or a sentence and a small local model explains it.
No browser tab, no cloud.

- **Readable definitions.** Wiktionary's raw markup is rendered into plain
  text: `(lb en obsolete)` becomes "(obsolete)", `(infl of en go  spast)`
  becomes "simple past of **go**", anagram lists and example sentences are
  dropped, and only English sections are shown.
- **Inflected words resolve to what they mean.** "went" shows *simple past of
  go* followed by what **go** means; "cats" shows the noun **cat**; "Stopped,"
  (capitalised, with punctuation) still works.
- **Never confidently wrong.** A word that isn't in the dictionary says so and
  offers close spellings ("serendipty" → *Did you mean: serendipity*). It never
  shows another word's definition as if it were yours.
- **Card that fits.** Capped at 45% of the screen with "+N more senses", placed
  beside the pointer and flipped away from screen edges, on whichever monitor
  the pointer is on. Stays up longer for longer definitions (4–15s).
- **Phrases and sentences, explained by a local model.** Highlight an idiom,
  a sentence or jargon and press the key: a small model running on *your*
  machine (through [Ollama](https://ollama.com)) explains it, streamed into
  the card and labelled **Interpretation · local model** — never presented as
  a dictionary definition. Words the dictionary knows never wake the model.
- **Two ways to use it:**
  - **Auto mode** (bar toggle, α): every word you highlight is looked up in
    the dictionary.
  - **On demand** (a keybinding): define or explain the highlighted text only
    when you ask. Works with auto mode off.

## Install

```bash
yay -S sdcv stardict-wikt-en-all
omarchy plugin add https://github.com/renardoberou/omarchy-plugin-dictionary --enable
```

- `sdcv` — the offline dictionary engine.
- `stardict-wikt-en-all` — English Wiktionary in StarDict format (~8 million
  entries). **CC BY-SA 3.0**, English Wiktionary contributors, converted by
  [dictinfo.com](https://www.dictinfo.com/). The data is not bundled here.

**Recommended:** also install WordNet for cleaner English definitions:

```bash
yay -S stardict-wordnet          # 12 MB; Princeton WordNet, permissive license
```

When WordNet has a word, its senses are shown ("cat: *Feline mammal usually
having thick soft fur…*", with synonyms); Wiktionary fills in everything
WordNet doesn't cover — slang, rare words, other spellings — and supplies
relations like "simple past of **go**". The card's footer says which
dictionary answered. Without sudo, the same files can live in
`~/.stardict/dic/wordnet/` (sdcv reads that folder too).

Until a dictionary is installed the card says "No offline dictionary
installed" instead of failing silently.

## Remove

```bash
omarchy plugin remove renardoberou.dictionary
```

Its only state is `~/.local/state/omarchy-dictionary/active` (the toggle);
delete that folder too if you want no trace.

## Keybinding (on demand)

Add to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + D", "Define selection", "omarchy-shell renardoberou.dictionary defineSelection")
```

**Define selection** sends a single word to the dictionary. A phrase, a
sentence, or a word the dictionary doesn't have goes to the local model
instead (when one is available).

Other IPC commands:

```bash
omarchy-shell renardoberou.dictionary explainSelection   # always the local model
omarchy-shell renardoberou.dictionary lookupSelection    # dictionary only
omarchy-shell renardoberou.dictionary explain "ceteris paribus"
omarchy-shell renardoberou.dictionary lookup serendipity
omarchy-shell renardoberou.dictionary toggle        # or: on / off
omarchy-shell renardoberou.dictionary status | jq
```

## Local model (optional)

Interpretations need [Ollama](https://ollama.com) running with a small chat
model. Without it everything else works; asking for an interpretation just
says the local model isn't available.

```bash
ollama pull qwen2.5:3b-instruct     # ~1.9 GB, good balance for this job
```

The first installed model from a list of small instruct models is used
(qwen2.5 3B, llama3.2 3B, gemma3 4B, phi3.5, then smaller and larger ones).
Measured on an RTX 4050 laptop GPU with qwen2.5 3B: ~0.2–0.4s for an answer
once loaded, ~3s on the first request after the model was unloaded, ~2.2 GB of
VRAM while loaded (Ollama unloads it after 5 idle minutes by default).

Settings (environment of the Omarchy shell):

| Variable | Default | |
|---|---|---|
| `OMARCHY_DICT_MODEL` | first installed small model | e.g. `llama3.2:3b` |
| `OLLAMA_HOST` | `127.0.0.1:11434` | Ollama's address |
| `OMARCHY_DICT_ALLOW_REMOTE` | unset | set to `1` to allow a non-local `OLLAMA_HOST` |
| `OMARCHY_DICT_KEEP_ALIVE` | `5m` | how long Ollama keeps the model loaded |

**Your text stays on your machine.** The highlighted text is sent only to the
Ollama server on this computer; a non-loopback `OLLAMA_HOST` is refused unless
you set `OMARCHY_DICT_ALLOW_REMOTE=1`.

**It is an interpretation, not a definition.** A 3B model is quick and usually
right about idioms, jargon and plain-language meaning, but it can be wrong
with confidence. It only sees what you highlighted, not the paragraph around
it. That's why its answers are labelled and kept apart from dictionary text.

## What triggers a lookup (auto mode)

Only selections that look like a word or a two-word phrase: letters (any
script) with inner apostrophes or hyphens, 2–48 characters. Surrounding
punctuation and quotes are stripped. Ignored:

- anything with digits, slashes, dots, `@`… — code, paths, URLs, and most
  passwords and tokens never reach the dictionary
- more than two words
- the selection that already existed when auto mode was switched on
- intermediate selections while you drag (only the last one is looked up)
- selections in password managers and prompts: 1Password, KeePassXC,
  Bitwarden, Proton Pass, Enpass, pinentry, GNOME/KDE keyring prompts, polkit.
  Extend the list with `OMARCHY_DICT_DENY_CLASSES` (a regex matched against the
  focused window's class) in the shell's environment.

Both auto mode and the keybinding read Wayland's primary selection, which is
filled by the app you select in. A few apps don't fill it; highlighting there
does nothing (use `omarchy-shell renardoberou.dictionary lookup <word>`).
Full-screen terminal programs that capture the mouse (editors, TUIs) only
fill it when you hold Shift while selecting.

## Privacy

Everything runs locally: `wl-paste` reads the selection, `sdcv` looks it up
in files on your disk, and interpretations go only to the Ollama server on
this machine. Nothing is logged or sent anywhere else. Auto mode is off until
you switch it on, and auto mode never uses the model.

## Known limits

- **The Wiktionary conversion lemmatises linked words** inside definitions:
  "commonly *keep* as a housepet" (Wiktionary says "kept"). That's baked into
  the `stardict-wikt-en-all` data; with WordNet installed, most everyday words
  are answered by WordNet instead (199 of 373 words in a 600-word sample).
- English only for now: other languages' sections are hidden, not translated.
- Suggestions come from the dictionary's own headword list, so they can
  include words from other languages when no English spelling is close.

## Structure

```
manifest.json           service + bar-widget + overlay (keepLoaded)
Service.qml             toggle (persisted), watcher process, one-shot lookups, IPC
BarWidget.qml           bar toggle (α)
Overlay.qml             click-through card: placement, cap, dismiss
Model.js                pure: markup rendering, English sections, suggestions, card model
bin/omarchy-dict-watch  selection watcher, trigger guards, lookup ladder, form-of following,
                        local-model interpretation (Ollama, streamed)
tests/                  node unit tests (real samples), watcher guard tests
```

## Local dev

```bash
omarchy plugin validate .
ln -sfn "$PWD" ~/.config/omarchy/plugins/renardoberou.dictionary
omarchy plugin enable renardoberou.dictionary
omarchy restart shell          # edits in a symlinked checkout need a restart
node --test tests/*.test.js
./tests/watch.test.sh
./bin/omarchy-dict-watch --lookup went | jq
```

`wl-paste --watch <command>` re-executes `<command>` once per selection change
with the content on stdin — it is not a continuous pipe. Piping it into a
`while read` loop silently drops every event, so the watcher runs itself in
`--handle` mode per event, like Omarchy's own clipboard plugin.
