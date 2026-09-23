# Dictionary

An offline dictionary for Omarchy. Highlight a word anywhere (or press a key)
and a definition card appears next to the pointer, on the monitor you're
using. No browser tab, no network.

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
- **Two ways to use it:**
  - **Auto mode** (bar toggle, α): every word you highlight is looked up.
  - **On demand** (a keybinding): look up the highlighted word only when you
    ask. Works with auto mode off.

## Install

```bash
yay -S sdcv stardict-wikt-en-all
omarchy plugin add https://github.com/renardoberou/omarchy-plugin-dictionary --enable
```

- `sdcv` — the offline dictionary engine.
- `stardict-wikt-en-all` — English Wiktionary in StarDict format (~8 million
  entries). **CC BY-SA 3.0**, English Wiktionary contributors, converted by
  [dictinfo.com](https://www.dictinfo.com/). The data is not bundled here.

Any other StarDict dictionary `sdcv` can see also works; results from every
installed dictionary are shown, first one first.

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
o.bind("SUPER + ALT + D", "Define highlighted word", "omarchy-shell renardoberou.dictionary lookupSelection")
```

Other IPC commands:

```bash
omarchy-shell renardoberou.dictionary lookup serendipity
omarchy-shell renardoberou.dictionary toggle        # or: on / off
omarchy-shell renardoberou.dictionary status | jq
```

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
in files on your disk. Nothing is logged or sent anywhere. Auto mode is off
until you switch it on.

## Known limits

- **The Wiktionary conversion lemmatises linked words** inside definitions:
  "commonly *keep* as a housepet" (Wiktionary says "kept"). That's baked into
  the `stardict-wikt-en-all` data. `stardict-wordnet` (AUR) is a cleaner, smaller
  English source and works alongside it.
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
bin/omarchy-dict-watch  selection watcher, trigger guards, lookup ladder, form-of following
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
