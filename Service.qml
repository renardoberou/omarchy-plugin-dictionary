import QtQuick
import Quickshell.Io
import "Model.js" as Model

// Headless. Owns the toggle, the selection watcher (only while the toggle is
// on) and one-shot lookups. BarWidget.qml and Overlay.qml read this service's
// state; neither talks to wl-paste or sdcv directly.
//
// IPC -- bind these to keys in Hyprland if you like:
//   omarchy-shell renardoberou.gloss defineSelection   # word -> dictionary, else local model
//   omarchy-shell renardoberou.gloss explainSelection  # always the local model
//   omarchy-shell renardoberou.gloss lookupSelection   # dictionary only
//   omarchy-shell renardoberou.gloss lookup serendipity
//   omarchy-shell renardoberou.gloss toggle            # auto-lookup on highlight
//   omarchy-shell renardoberou.gloss status | jq
Item {
  id: root
  property var shell: null

  readonly property string helperDir: Qt.resolvedUrl("bin").toString().replace(/^file:\/\//, "")
  readonly property string watcherPath: helperDir + "/omarchy-gloss"

  // Auto mode: look up whatever gets highlighted. Persisted across restarts.
  property bool active: false
  property bool stateLoaded: false
  property var lookup: Model.parseLookupLine("")
  // Bumped on every lookup worth showing, so the overlay can tell "a new
  // lookup arrived" from "the same lookup re-rendered".
  property int lookupSeq: 0
  // The local model's interpretation of the current selection, streamed in.
  property var explanation: Model.emptyExplanation()
  property string lastError: ""

  function setActive(on) {
    if (root.active === on) return
    root.active = on
    stateWriter.command = [root.watcherPath, "--state", on ? "on" : "off"]
    stateWriter.running = true
  }
  function toggle() { setActive(!root.active) }

  function handleLine(line) {
    var ex = Model.parseExplainLine(line)
    if (ex) {
      // Errors like "Ollama isn't running" are worth a card only when the
      // user explicitly asked for an interpretation (always the case here).
      var first = !root.explanation.active || root.explanation.query !== ex.query
      root.explanation = ex
      if (first) {
        root.lookup = Model.parseLookupLine("")
        root.lookupSeq++
      }
      return
    }
    var parsed = Model.parseLookupLine(line)
    root.lastError = parsed.error
    if (!Model.hasContent(parsed)) return
    root.explanation = Model.emptyExplanation()
    root.lookup = parsed
    root.lookupSeq++
  }

  // One-shot lookups (IPC / keybinding). Work whether or not auto mode is on.
  function runOnce(args) {
    if (oneShot.running) oneShot.running = false
    oneShot.command = [root.watcherPath].concat(args)
    oneShot.running = true
  }
  function lookupWord(word) { if (word) runOnce(["--lookup", String(word)]) }
  function lookupSelection() { runOnce(["--selection"]) }
  function defineSelection() { runOnce(["--define"]) }
  function explainSelection() { runOnce(["--explain"]) }
  function explainText(text) { if (text) runOnce(["--explain", String(text)]) }

  Component.onCompleted: {
    stateReader.command = [root.watcherPath, "--state"]
    stateReader.running = true
  }

  Process {
    id: stateReader
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.active = text.trim() === "on"
        root.stateLoaded = true
      }
    }
  }

  Process { id: stateWriter }

  Process {
    id: watcher
    command: [root.watcherPath]
    running: root.active && root.stateLoaded
    stdout: SplitParser {
      onRead: function(line) { root.handleLine(line) }
    }
    onExited: function(exitCode, exitStatus) {
      // The watcher runs until stopped. If it dies while we're still on,
      // force the false->true transition Process needs to start it again
      // (the `running` binding alone won't re-fire).
      if (root.active) {
        watcher.running = false
        restartTimer.restart()
      }
    }
  }

  // Back off a little so a watcher that can't start doesn't spin.
  Timer {
    id: restartTimer
    interval: 1500
    onTriggered: if (root.active) watcher.running = true
  }

  Process {
    id: oneShot
    stdout: SplitParser {
      onRead: function(line) { root.handleLine(line) }
    }
  }

  IpcHandler {
    target: "renardoberou.gloss"
    function toggle(): string { root.toggle(); return root.active ? "on" : "off" }
    function on(): string { root.setActive(true); return "on" }
    function off(): string { root.setActive(false); return "off" }
    function lookup(word: string): string { root.lookupWord(word); return "looking up" }
    function lookupSelection(): string { root.lookupSelection(); return "looking up" }
    function defineSelection(): string { root.defineSelection(); return "defining" }
    function explainSelection(): string { root.explainSelection(); return "explaining" }
    function explain(text: string): string { root.explainText(text); return "explaining" }
    function status(): string {
      return JSON.stringify({
        active: root.active,
        lastError: root.lastError,
        lookupSeq: root.lookupSeq,
        lookup: { query: root.lookup.query, word: root.lookup.word, via: root.lookup.via,
                  found: root.lookup.found, suggestions: root.lookup.suggestions.length,
                  lemma: root.lookup.lemma ? root.lookup.lemma.word : "" },
        card: Model.buildCard(root.lookup),
        explanation: root.explanation
      })
    }
  }
}
