import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Click-through, always-on-top definition card. It appears on the monitor
// the pointer is on, next to the pointer, and dismisses itself after a time
// that scales with how much there is to read. Same layer-shell technique as
// omarchy-keycaps: an empty `mask` passes every input event through, so the
// card can never steal a click or focus -- only be looked at.
Item {
  id: root

  property var shell: null
  property var manifest: null
  // The shell hands overlays their plugin's service directly (and a scoped
  // `shell`), never a `bar` -- v0.1 read `bar.shell`, which is always null
  // here, so the card could never appear.
  property var service: null

  readonly property var svc: service || (shell ? shell.serviceFor("renardoberou.dictionary") : null)
  readonly property var lookup: svc ? svc.lookup : Model.parseLookupLine("")
  readonly property var cardModel: Model.buildCard(lookup, { maxSenses: 6, perSection: 3 })
  readonly property string dictName: lookup.entries.length ? lookup.entries[0].dict : ""

  property bool cardVisible: false

  Timer {
    id: dismissTimer
    onTriggered: root.cardVisible = false
  }

  Connections {
    target: root.svc
    function onLookupSeqChanged() {
      dismissTimer.interval = Model.dismissMs(root.cardModel)
      root.cardVisible = true
      dismissTimer.restart()
    }
  }

  // The monitor under the pointer, and the pointer relative to it.
  readonly property var where: Model.screenAt(Quickshell.screens, lookup.x, lookup.y)

  readonly property bool showing: cardVisible && Model.hasContent(lookup)

  PanelWindow {
    id: panel
    screen: root.where.screen
    visible: root.showing || card.opacity > 0.001
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-dictionary"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}

    readonly property int cardWidth: Math.min(Style.space(360), width - 2 * margin)
    readonly property int margin: Style.space(16)
    readonly property int gap: Style.space(18)
    readonly property int maxCardHeight: Math.round(height * 0.45)

    Item {
      id: card
      width: panel.cardWidth
      height: Math.min(column.implicitHeight + Style.space(20), panel.maxCardHeight)
      clip: true

      readonly property var spot: Model.placeCard(root.where.x, root.where.y, width, height,
                                                  panel.width, panel.height, panel.gap, panel.margin)
      x: spot.x
      y: spot.y

      opacity: root.showing ? 1.0 : 0.0
      scale: root.showing ? 1.0 : 0.97
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

        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            id: titleText
            textFormat: Text.PlainText
            text: root.cardModel.title
            width: Math.min(implicitWidth, parent.width - noteText.width - parent.spacing)
            elide: Text.ElideRight
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            id: noteText
            textFormat: Text.PlainText
            visible: !!root.cardModel.note
            text: root.cardModel.note
            anchors.baseline: titleText.baseline
            color: Qt.darker(Color.popups.text, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          visible: !!root.cardModel.error || !!root.cardModel.empty
          textFormat: Text.PlainText
          text: root.cardModel.error || root.cardModel.empty
          width: parent.width
          wrapMode: Text.Wrap
          color: Qt.darker(Color.popups.text, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          visible: root.cardModel.suggestions.length > 0
          textFormat: Text.PlainText
          text: "Did you mean: " + root.cardModel.suggestions.join(", ")
          width: parent.width
          wrapMode: Text.Wrap
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        // "simple past of go" -- then what "go" means
        Text {
          visible: !!root.cardModel.lemmaTitle
          textFormat: Text.PlainText
          text: root.cardModel.lemmaTitle
          width: parent.width
          wrapMode: Text.Wrap
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.italic: true
        }

        Repeater {
          model: root.cardModel.lemmaBlocks.concat(root.cardModel.blocks)

          delegate: Column {
            required property var modelData
            width: column.width
            spacing: Style.space(2)

            Text {
              visible: !!modelData.heading
              textFormat: Text.PlainText
              text: modelData.heading
              width: parent.width
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Repeater {
              model: modelData.senses
              delegate: Text {
                required property var modelData
                textFormat: Text.PlainText
                text: "• " + modelData
                width: column.width
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }

        Text {
          visible: root.cardModel.hidden > 0 || !!root.dictName
          textFormat: Text.PlainText
          text: (root.cardModel.hidden > 0 ? "+" + root.cardModel.hidden + " more senses" : "") +
                (root.cardModel.hidden > 0 && root.dictName ? " · " : "") + root.dictName
          width: parent.width
          elide: Text.ElideRight
          color: Qt.darker(Color.popups.text, 1.6)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
