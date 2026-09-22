import QtQuick
import Quickshell.Io
import "Model.js" as Model

// Headless. Owns the toggle state and the bin/omarchy-dict-watch process
// (only runs while active). BarWidget.qml and Overlay.qml both read this
// service's state via bar.shell.serviceFor("renardoberou.dictionary") and
// never talk to wl-paste/sdcv directly themselves.
Item {
  id: root
  property var shell: null

  readonly property string helperDir: Qt.resolvedUrl("bin").toString().replace(/^file:\/\//, "")
  readonly property string watcherPath: helperDir + "/omarchy-dict-watch"

  property bool active: false
  property var lookup: ({ query: "", entries: [], found: false, error: "", x: 0, y: 0 })
  // Bumped on every accepted lookup so Overlay.qml's auto-dismiss timer can
  // tell "a new lookup arrived" apart from "the same lookup re-rendered".
  property int lookupSeq: 0

  function toggle() { root.active = !root.active }

  function handleLine(line) {
    var parsed = Model.parseLookupLine(line)
    if (!parsed.query && !parsed.error) return
    root.lookup = parsed
    root.lookupSeq++
  }

  onActiveChanged: {
    if (!root.active) {
      root.lookup = { query: "", entries: [], found: false, error: "", x: 0, y: 0 }
    }
  }

  Process {
    id: watcher
    command: [root.watcherPath]
    running: root.active
    stdout: SplitParser {
      onRead: function(line) { root.handleLine(line) }
    }
    onExited: function(exitCode, exitStatus) {
      // The watcher shouldn't normally exit while active (it's a wl-paste
      // --watch loop) — if it dies unexpectedly and we're still toggled
      // on, QML's own `running: root.active` binding won't restart it
      // (Process only reacts to `running` transitioning false->true), so
      // force that transition here.
      if (root.active) {
        watcher.running = false
        Qt.callLater(function() { watcher.running = true })
      }
    }
  }
}
