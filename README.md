# Dictionary

An Omarchy shell plugin: toggle it on from the bar, then highlight any
word anywhere on the system — no copy, just select — and a definition
card pops up near the cursor, offline.

## Why

Omarchy already has clipboard history and reminders as overlay-kind
plugins; this adds the same idea for "I don't know this word" without
leaving what you're doing to open a browser tab.

## What it does

- **Bar toggle:** click the bar icon (or its own toggle) to arm/disarm.
  Off by default — nothing watches anything until you turn it on.
- **Auto-lookup on selection:** while on, `bin/omarchy-dict-watch` watches
  the Wayland *primary* selection (`wl-paste --primary --watch`) — the
  buffer populated by plain mouse-drag highlighting, not `Ctrl+C`. Every
  change that passes a couple of sanity guards (not empty, not longer than
  64 characters — a highlighted paragraph isn't a lookup) runs an offline
  `sdcv` query and streams the result to the shell.
- **Card:** appears near where you made the selection, shows the query,
  each matching dictionary's entry, and auto-dismisses after ~6s (or
  sooner if you select something else). It is deliberately **click-through**
  — same layer-shell technique as `omarchy-keycaps` — so it never steals a
  click or blocks whatever you were doing underneath it. That also means
  it has no close button; the timer is the only dismissal.

## Prerequisites (not bundled)

```bash
yay -S sdcv stardict-wikt-en-all
```

- `sdcv` — the offline dictionary CLI this plugin drives.
- `stardict-wikt-en-all` — English Wiktionary (all languages defined in
  English) converted to StarDict format. **CC BY-SA 3.0** — attribution +
  share-alike; this plugin's own code is MIT, but the dictionary *data* is
  not bundled or vendored into this repo for that reason (and because it's
  a full Wiktionary dump — not a small download). Credit:
  [dictinfo.com](https://www.dictinfo.com/), English Wiktionary contributors.

Until both are installed, the card will say "No offline dictionary
installed" instead of failing silently or doing nothing.

## Structure

```
manifest.json           schema + three entry points (service, bar-widget, overlay)
Service.qml               headless: toggle state, owns the watcher process
BarWidget.qml              bar pill toggle
Overlay.qml                 click-through popup card, auto-positions + auto-dismisses
Model.js                    pure: JSON line parsing, sdcv text-output parsing
bin/omarchy-dict-watch  wl-paste --primary --watch -> guards -> sdcv -> JSON
```

## Install / remove

```
omarchy plugin add https://github.com/renardoberou/omarchy-plugin-dictionary --enable
omarchy plugin remove renardoberou.dictionary
```

## Local dev

```
omarchy plugin validate .
ln -sfn "$PWD" ~/.config/omarchy/plugins/renardoberou.dictionary
omarchy plugin enable renardoberou.dictionary
omarchy restart shell
journalctl --user -t omarchy-shell --since "1 minute ago" | grep dict
```

Test the pipeline without touching a mouse at all — `wl-copy --primary`
sets the exact same selection slot a manual highlight would:
```
./bin/omarchy-dict-watch    # in one terminal
wl-copy --primary "hello"   # in another — watch the first terminal for a JSON line
```

`node -e "require('./Model.js').parseSdcvOutput('...')"` exercises the
pure parsing logic without touching sdcv, wl-paste, or the shell at all.

## Known limits

- **Auto-trigger noise, by design.** Any primary-selection change while
  toggled on fires a lookup — renaming a file, selecting code to copy,
  anything. The length/whitespace guards cut down the worst of it; turning
  the toggle off is the real mitigation. This tradeoff was chosen
  deliberately over a keybinding-gated trigger.
- **Wayland primary selection is toolkit-dependent.** Some apps don't
  populate it at all — highlighting text there will silently do nothing.
  That's a platform gap, not a bug here.
- **English only, single dictionary in v1.** No language or dictionary
  picker yet.
- `Model.parseSdcvOutput` was written against sdcv's documented output
  shape, not a live sample on this machine (sdcv wasn't installed at
  authoring time) — re-verify against real output once installed and
  adjust the parser if the format differs.
