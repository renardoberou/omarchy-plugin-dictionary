#!/usr/bin/env bash
# Exercises bin/omarchy-dict-watch's trigger guards and lookup ladder through
# its real --handle path (what wl-paste --watch runs per selection change).
# Needs sdcv and stardict-wikt-en-all; skips otherwise. Touches no shell state.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
w="$here/../bin/omarchy-dict-watch"
command -v sdcv >/dev/null && [[ -n "$(sdcv -l 2>/dev/null | tail -n +2)" ]] || { echo "skip: no sdcv dictionary"; exit 0; }
export OMARCHY_DICT_RUNTIME="$(mktemp -d)"; trap 'rm -rf "$OMARCHY_DICT_RUNTIME"' EXIT
fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }
handle() { printf '%s' "$1" | DICT_WATCH_STARTED=0 OMARCHY_DICT_DENY_CLASSES="${DENY:-no-such-window-class}" "$w" --handle; }

for s in "https://example.com/a" "rm -rf /tmp/x" "hunter2" "The quick brown fox jumps" "a" "" "   " "foo@bar.com" "v0.2.0"; do
  check "ignored: '$s'" "[[ -z \"\$(handle \"$s\")\" ]]"
done
check "word looked up"              "handle quixotic | jq -e '.found and .word == \"quixotic\"' >/dev/null"
check "punctuation stripped"        "handle '“Stopped,”' | jq -e '.query == \"Stopped\"' >/dev/null"
check "capitalised falls back"      "handle Hello | jq -e '.via == \"lowercase\" and .word == \"hello\"' >/dev/null"
check "two-word phrase"             "handle 'ice cream' | jq -e '.found' >/dev/null"
check "inflection follows to lemma" "handle went | jq -e '.lemma.word == \"go\"' >/dev/null"
check "miss has suggestions, no entries" \
  "handle serendipty | jq -e '(.found | not) and (.entries | length == 0) and (.suggestions | index(\"serendipity\"))' >/dev/null"
check "startup grace skips the old selection" \
  "[[ -z \"\$(printf quixotic | DICT_WATCH_STARTED=\${EPOCHREALTIME/./} \"$w\" --handle)\" ]]"
check "denied window is skipped" \
  "[[ -z \"\$(DENY=. handle quixotic)\" ]]"
check "debounce: only the last of a burst" \
  "[[ \$( { handle absur & sleep 0.05; handle absurd; wait; } | grep -c . ) == 1 ]]"
# ---- local model (Ollama) -------------------------------------------------
check "explain: Ollama down gives no-ollama" \
  "OLLAMA_HOST=127.0.0.1:9 \"$w\" --explain 'break a leg' | jq -e '.error == \"no-ollama\"' >/dev/null"
check "explain: remote host refused by default" \
  "OLLAMA_HOST=gpu-box.example.com:11434 \"$w\" --explain 'break a leg' | jq -e '.error == \"remote-host\"' >/dev/null"
if curl -s -m 1 "http://${OLLAMA_HOST:-127.0.0.1:11434}/api/tags" | jq -e '.models | length > 0' >/dev/null 2>&1; then
  check "explain: configured model missing names it" \
    "OMARCHY_DICT_MODEL=nope:1b \"$w\" --explain 'x y' | jq -e '.error == \"no-model\" and (.message | test(\"nope:1b\"))' >/dev/null"
  check "explain: streams and finishes with text" \
    "\"$w\" --explain 'break a leg' | tail -1 | jq -e '.kind == \"explain\" and .done and (.text | length > 10)' >/dev/null"
  check "define: a dictionary word never wakes the model" \
    "wl-copy --primary quixotic && [[ \$(\"$w\" --define | jq -r '.kind // \"lookup\"') == lookup ]]"
  check "define: a phrase goes to the model" \
    "wl-copy --primary 'the devil is in the details' && \"$w\" --define | tail -1 | jq -e '.kind == \"explain\"' >/dev/null"
else
  echo "skip - live model tests (Ollama with a model not reachable)"
fi
exit $fail
