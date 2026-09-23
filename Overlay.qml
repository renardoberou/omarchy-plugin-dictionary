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

  readonly property var svc: service || (shell ? shell.serviceFor("renardoberou.gloss") : null)
  readonly property var lookup: svc ? svc.lookup : Model.parseLookupLine("")
  readonly property var cardModel: Model.buildCard(lookup, { maxSenses: 6, perSection: 3 })
  readonly property var explanation: svc ? svc.explanation : Model.emptyExplanation()
  // Showing the local model's interpretation instead of dictionary senses.
  readonly property bool explaining: explanation.active

  property bool cardVisible: false

  Timer {
    id: dismissTimer
    onTriggered: root.cardVisible = false
  }

  Connections {
    target: root.svc
    function onLookupSeqChanged() {
      root.cardVisible = true
      if (root.explaining && !root.explanation.done) { dismissTimer.stop(); return }
      dismissTimer.interval = root.explaining ? Model.explainDismissMs(root.explanation)
                                              : Model.dismissMs(root.cardModel)
      dismissTimer.restart()
    }
    // Streaming: keep the card up while the model writes, then give the
    // reader time proportional to what it wrote.
    function onExplanationChanged() {
      if (!root.explaining || !root.cardVisible) return
      if (root.explanation.done) {
        dismissTimer.interval = Model.explainDismissMs(root.explanation)
        dismissTimer.restart()
      } else {
        dismissTimer.stop()
      }
    }
  }

  // The monitor under the pointer, and the pointer relative to it.
  readonly property var where: explaining
    ? Model.screenAt(Quickshell.screens, explanation.x, explanation.y)
    : Model.screenAt(Quickshell.screens, lookup.x, lookup.y)

  readonly property bool showing: cardVisible && (explaining || Model.hasContent(lookup))

  PanelWindow {
    id: panel
    screen: root.where.screen
    visible: root.showing || card.opacity > 0.001
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-gloss"
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
            text: root.explaining
              ? (Model.explainTitle(root.explanation.query, 60) || "Gloss")
              : root.cardModel.title
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
            visible: !root.explaining && !!root.cardModel.note
            text: root.cardModel.note
            anchors.baseline: titleText.baseline
            color: Qt.darker(Color.popups.text, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        // ---- local model interpretation ------------------------------------
        Text {
          visible: root.explaining
          textFormat: Text.PlainText
          text: "Interpretation" + (root.explanation.model ? " · " + Model.modelLabel(root.explanation.model) : "") + " · local model"
          width: parent.width
          elide: Text.ElideRight
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.italic: true
        }

        Text {
          visible: root.explaining
          textFormat: Text.PlainText
          text: root.explanation.error
            ? root.explanation.message || "The local model couldn't answer."
            : (root.explanation.text || "Interpreting…") + (root.explanation.done || !root.explanation.text ? "" : " ▍")
          width: parent.width
          wrapMode: Text.Wrap
          color: root.explanation.error || !root.explanation.text ? Qt.darker(Color.popups.text, 1.3) : Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        // ---- dictionary --------------------------------------------------
        Text {
          visible: !root.explaining && (!!root.cardModel.error || !!root.cardModel.empty)
          textFormat: Text.PlainText
          text: root.cardModel.error || root.cardModel.empty
          width: parent.width
          wrapMode: Text.Wrap
          color: Qt.darker(Color.popups.text, 1.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          visible: !root.explaining && root.cardModel.suggestions.length > 0
          textFormat: Text.PlainText
          text: "Did you mean: " + root.cardModel.suggestions.join(", ")
          width: parent.width
          wrapMode: Text.Wrap
          color: Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        // A phrase with no entry: each of its words, briefly.
        Repeater {
          model: root.explaining ? [] : root.cardModel.parts

          delegate: Column {
            required property var modelData
            width: column.width
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: modelData.title + (modelData.note ? "  ·  " + modelData.note : "")
              width: parent.width
              elide: Text.ElideRight
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            Repeater {
              model: modelData.blocks
              delegate: Text {
                required property var modelData
                textFormat: Text.PlainText
                text: (modelData.heading ? modelData.heading + " · " : "") + modelData.senses.join(" · ")
                width: column.width
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: Color.popups.text
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }

        Text {
          visible: !root.explaining && !!root.cardModel.hint
          textFormat: Text.PlainText
          text: root.cardModel.hint
          width: parent.width
          wrapMode: Text.Wrap
          color: Qt.darker(Color.popups.text, 1.5)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.italic: true
        }

        // "simple past of go" -- then what "go" means
        Text {
          visible: !root.explaining && !!root.cardModel.lemmaTitle
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
          model: root.explaining ? [] : root.cardModel.lemmaBlocks.concat(root.cardModel.blocks)

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

            Text {
              visible: !!modelData.synonyms && modelData.synonyms.length > 0
              textFormat: Text.PlainText
              text: "also: " + (modelData.synonyms || []).join(", ")
              width: parent.width
              elide: Text.ElideRight
              color: Qt.darker(Color.popups.text, 1.4)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.italic: true
            }
          }
        }

        Text {
          visible: !root.explaining && (root.cardModel.hidden > 0 || !!root.cardModel.source)
          textFormat: Text.PlainText
          text: (root.cardModel.hidden > 0 ? "+" + root.cardModel.hidden + " more senses" : "") +
                (root.cardModel.hidden > 0 && root.cardModel.source ? " · " : "") + root.cardModel.source
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
