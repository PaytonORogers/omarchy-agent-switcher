import QtQuick
import qs.Commons as Commons

Rectangle {
  id: root
  property string text: ""
  property color background: Commons.Color.background
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  signal clicked()
  implicitWidth: label.implicitWidth + 24
  implicitHeight: 30
  radius: 8
  color: background
  border.width: (hover.containsMouse || activeFocus) ? 2 : 1
  border.color: accent
  opacity: enabled ? 1 : 0.55
  Accessible.role: Accessible.Button
  Accessible.name: text
  activeFocusOnTab: true
  Keys.onReturnPressed: clicked()
  Keys.onSpacePressed: clicked()
  Text { id: label; anchors.centerIn: parent; text: root.text; color: root.foreground; font.family: Commons.Style.font.family; font.pixelSize: 12 }
  MouseArea { id: hover; anchors.fill: parent; hoverEnabled: true; onClicked: root.clicked() }
}
