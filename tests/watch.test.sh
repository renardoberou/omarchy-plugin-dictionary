#!/usr/bin/env bash
# Exercises bin/omarchy-gloss's trigger guards and lookup ladder through
# its real --handle path (what wl-paste --watch runs per selection change).
# Needs sdcv and stardict-wikt-en-all; skips otherwise. Touches no shell state.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
w="$here/../bin/omarchy-gloss"
command -v sdcv >/dev/null && [[ -n "$(sdcv -l 2>/dev/null | tail -n +2)" ]] || { echo "skip: no sdcv dictionary"; exit 0; }
export OMARCHY_GLOSS_RUNTIME="$(mktemp -d)"
fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }
# Tests that write to the REAL primary selection must not pop cards on the
# user's screen: pause the plugin's auto mode (and wait until its watcher
# process is really gone), and restore both the mode and the selection after.
paused=""; saved_sel=""
pause_auto() {
  saved_sel="$(wl-paste --primary --no-newline --type text 2>/dev/null)"
  if [[ "$(omarchy-shell renardoberou.gloss status 2>/dev/null | jq -r '.active // false' 2>/dev/null)" == true ]]; then
    paused=1
    omarchy-shell -q renardoberou.gloss off >/dev/null
  fi
  local i
  for (( i = 0; i < 30; i++ )); do
    pgrep -f 'wl-paste --primary --type text --watch .*omarchy-gloss' >/dev/null || break
    sleep 0.1
  done
}
resume_auto() {
  if [[ -n "$saved_sel" ]]; then printf '%s' "$saved_sel" | wl-copy --primary; else wl-copy --primary --clear; fi
  sleep 0.5
  if [[ -n "$paused" ]]; then paused=""; omarchy-shell -q renardoberou.gloss on >/dev/null; fi
}
trap 'resume_auto 2>/dev/null; rm -rf "$OMARCHY_GLOSS_RUNTIME"' EXIT

handle() { printf '%s' "$1" | GLOSS_WATCH_STARTED=0 OMARCHY_GLOSS_DENY_CLASSES="${DENY:-no-such-window-class}" "$w" --handle; }

for s in "https://example.com/a" "rm -rf /tmp/x" "hunter2" "The quick brown fox jumps" "a" "" "   " "foo@bar.com" "v0.2.0"; do
  check "ignored: '$s'" "[[ -z \"\$(handle \"$s\")\" ]]"
done
check "word looked up"              "handle quixotic | jq -e '.found and .word == \"quixotic\"' >/dev/null"
check "punctuation stripped"        "handle '“Stopped,”' | jq -e '.query == \"Stopped\"' >/dev/null"
check "capitalised falls back"      "handle Hello | jq -e '.via == \"lowercase\" and .word == \"hello\"' >/dev/null"
check "two-word phrase"             "handle 'ice cream' | jq -e '.found' >/dev/null"
check "phrase without entry lists its words" \
  "handle 'Premium subscribers' | jq -e '(.found | not) and ([.parts[].word] == [\"premium\", \"subscribers\"])' >/dev/null"
check "inflection follows to lemma" "handle went | jq -e '.lemma.word == \"go\"' >/dev/null"
check "miss has suggestions, no entries" \
  "handle serendipty | jq -e '(.found | not) and (.entries | length == 0) and (.suggestions | index(\"serendipity\"))' >/dev/null"
check "startup grace skips the old selection" \
  "[[ -z \"\$(printf quixotic | GLOSS_WATCH_STARTED=\${EPOCHREALTIME/./} \"$w\" --handle)\" ]]"
check "denied window is skipped" \
  "[[ -z \"\$(DENY=. handle quixotic)\" ]]"
check "debounce: only the last of a burst" \
  "[[ \$( { handle absur & sleep 0.05; handle absurd; wait; } | grep -c . ) == 1 ]]"
# ---- what's in the selection (uses the real primary selection) ------------
if command -v wl-copy >/dev/null && [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
  pause_auto
  printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR' | wl-copy --primary --type image/png
  check "an image in the selection is not text (was: PNG bytes sent to the model)" \
    "\"$w\" --define | jq -e '.error == \"no-word\"' >/dev/null"
  printf 'abc\x01\x02def' | wl-copy --primary --type text/plain
  check "binary labelled as text is refused" \
    "\"$w\" --define | jq -e '.error == \"not-text\"' >/dev/null"
  wl-copy --primary --clear
  check "empty selection shows nothing" \
    "\"$w\" --define | jq -e '.error == \"no-word\"' >/dev/null"
  check "binary on the watcher path is ignored" \
    "[[ -z \"\$(printf 'ab\x01cd' | GLOSS_WATCH_STARTED=0 OMARCHY_GLOSS_DENY_CLASSES=no-such-window-class \"$w\" --handle)\" ]]"
  resume_auto
else
  echo "skip - selection tests (no Wayland session)"
fi

# ---- local model (Ollama) -------------------------------------------------
check "explain: Ollama down gives no-ollama" \
  "OLLAMA_HOST=127.0.0.1:9 \"$w\" --explain 'break a leg' | jq -e '.error == \"no-ollama\"' >/dev/null"
check "explain: remote host refused by default" \
  "OLLAMA_HOST=gpu-box.example.com:11434 \"$w\" --explain 'break a leg' | jq -e '.error == \"remote-host\"' >/dev/null"
if curl -s -m 1 "http://${OLLAMA_HOST:-127.0.0.1:11434}/api/tags" | jq -e '.models | length > 0' >/dev/null 2>&1; then
  pause_auto
  check "explain: configured model missing names it" \
    "OMARCHY_GLOSS_MODEL=nope:1b \"$w\" --explain 'x y' | jq -e '.error == \"no-model\" and (.message | test(\"nope:1b\"))' >/dev/null"
  check "explain: streams and finishes with text" \
    "\"$w\" --explain 'break a leg' | tail -1 | jq -e '.kind == \"explain\" and .done and (.text | length > 10)' >/dev/null"
  check "define: a dictionary word never wakes the model" \
    "wl-copy --primary quixotic && [[ \$(\"$w\" --define | jq -r '.kind // \"lookup\"') == lookup ]]"
  check "define: a phrase goes to the model" \
    "wl-copy --primary 'the devil is in the details' && \"$w\" --define | tail -1 | jq -e '.kind == \"explain\"' >/dev/null"
  resume_auto
else
  echo "skip - live model tests (Ollama with a model not reachable)"
fi
exit $fail
