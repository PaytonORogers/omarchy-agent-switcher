import QtQuick
import qs.Commons as Commons

Rectangle {
  id: root
  property string glyph: "+"
  property string label: ""
  property color background: Commons.Color.background
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property bool ring: true
  signal clicked()
  signal hovered(bool over)
  width: 26; height: 26; radius: 13
  color: background
  border.width: ring || pointer.containsMouse || activeFocus ? 1 : 0
  border.color: accent
  Accessible.role: Accessible.Button
  Accessible.name: label
  activeFocusOnTab: true
  Keys.onReturnPressed: clicked()
  Keys.onSpacePressed: clicked()
  Text { anchors.centerIn: parent; text: root.glyph; color: root.foreground; font.family: Commons.Style.font.family; font.pixelSize: 17 }
  MouseArea { id: pointer; anchors.fill: parent; hoverEnabled: true; onContainsMouseChanged: root.hovered(containsMouse); onClicked: root.clicked() }
}
