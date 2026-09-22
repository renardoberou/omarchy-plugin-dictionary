import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Click-through, always-on-top card that pops up near the cursor when a
// lookup arrives, and auto-dismisses. Same layer-shell technique as
// omarchy-keycaps/Panel.qml: an empty `mask` makes the whole full-screen
// window pass every input event through to whatever's underneath, so
// this can never be clicked, dragged, or focused -- only looked at.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var bar: null

  readonly property var svc: bar && bar.shell ? bar.shell.serviceFor("renardoberou.dictionary") : null
  readonly property var lookup: svc ? svc.lookup : ({ query: "", raw: "", found: false, error: "", x: 0, y: 0 })
  readonly property var entries: Model.parseSdcvOutput(lookup.raw)

  property bool cardVisible: false

  Timer {
    id: dismissTimer
    interval: 6000
    onTriggered: root.cardVisible = false
  }

  Connections {
    target: root.svc
    function onLookupSeqChanged() {
      root.cardVisible = true
      dismissTimer.restart()
    }
  }

  onSvcChanged: if (!svc || !svc.active) cardVisible = false

  readonly property var targetScreen: {
    var monitor = Hyprland.focusedMonitor
    var name = monitor ? String(monitor.name || "") : ""
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; i++) {
      if (String(screens[i].name || "") === name) return screens[i]
    }
    return screens.length > 0 ? screens[0] : null
  }

  readonly property bool showing: !!(svc && svc.active && cardVisible && Model.hasContent(lookup))

  PanelWindow {
    id: panel
    screen: root.targetScreen
    visible: root.showing || card.opacity > 0.001
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-dictionary"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}

    readonly property int cardWidth: Style.space(320)
    readonly property int margin: Style.space(16)

    Item {
      id: card
      width: panel.cardWidth
      height: column.implicitHeight + Style.space(20)

      // Follow the point the selection was made at, offset down-right,
      // clamped so the card never runs off the target monitor.
      x: Math.max(panel.margin, Math.min(root.lookup.x + Style.space(16), panel.width - width - panel.margin))
      y: Math.max(panel.margin, Math.min(root.lookup.y + Style.space(16), panel.height - height - panel.margin))

      opacity: root.showing ? 1.0 : 0.0
      scale: root.showing ? 1.0 : 0.96
      Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

      Rectangle {
        anchors.fill: parent
        radius: Style.cornerRadius
        color: Color.popups.background
        border.width: Style.normalBorderWidth
        border.color: Color.popups.border
      }

      Column {
        id: column
        x: Style.space(14)
        y: Style.space(10)
        width: parent.width - Style.space(28)
        spacing: Style.space(6)

        Text {
          textFormat: Text.PlainText
          text: root.lookup.query
          width: parent.width
          elide: Text.ElideRight
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Text {
          visible: !!root.lookup.error
          text: root.lookup.error === "no-dictionary"
            ? "No offline dictionary installed — see README."
            : root.lookup.error
          width: parent.width
          wrapMode: Text.Wrap
          color: Qt.darker(Color.popups.text, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          visible: !root.lookup.error && !root.lookup.found
          text: "No definition found."
          width: parent.width
          color: Qt.darker(Color.popups.text, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Repeater {
          model: root.lookup.found ? root.entries : []

          delegate: Column {
            required property var modelData
            width: column.width
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: modelData.dict
              width: parent.width
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              text: modelData.text
              width: parent.width
              wrapMode: Text.Wrap
              maximumLineCount: 8
              elide: Text.ElideRight
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }
    }
  }
}
