import QtQuick
import Quickshell
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "renardoberou.dictionary"

  readonly property var svc: bar && bar.shell ? bar.shell.serviceFor("renardoberou.dictionary") : null
  readonly property bool active: svc ? svc.active : false
  readonly property string tip: active
    ? "Dictionary — on. Highlight a word anywhere to look it up."
    : "Dictionary — off. Click to start looking up highlighted words."

  implicitWidth: pillRow.implicitWidth + Style.space(14)
  implicitHeight: barSize

  Row {
    id: pillRow
    anchors.centerIn: parent
    spacing: Style.space(4)

    Text {
      textFormat: Text.PlainText
      text: "󰀫"
      color: root.active ? (root.bar ? root.bar.urgent : Color.urgent) : root.bar.barForeground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      textFormat: Text.PlainText
      text: "Dictionary"
      visible: !root.bar.vertical
      color: root.active ? (root.bar ? root.bar.urgent : Color.urgent) : root.bar.barForeground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: if (root.svc) root.svc.toggle()
    onEntered: if (root.bar) root.bar.showTooltip(root, root.tip)
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
