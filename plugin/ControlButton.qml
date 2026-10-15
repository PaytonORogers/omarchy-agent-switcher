import QtQuick
import qs.Commons as Commons

Rectangle {
  id: root
  property string text: ""
  property color background: Commons.Color.background
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property bool highlighted: false
  signal clicked()
  implicitWidth: label.implicitWidth + 24
  implicitHeight: 30
  radius: 8
  color: background
  border.width: (highlighted || hover.containsMouse || activeFocus) ? 2 : 1
  border.color: accent
  opacity: enabled ? 1 : 0.55
  Accessible.role: Accessible.Button
  Accessible.name: text
  activeFocusOnTab: true
  Keys.onReturnPressed: clicked()
  Keys.onSpacePressed: clicked()
  Text { id: label; anchors.centerIn: parent; width: parent.width - 24; text: root.text; color: root.foreground; font.family: Commons.Style.font.family; font.pixelSize: 12; font.weight: root.highlighted ? Font.DemiBold : Font.Normal; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight }
  MouseArea { id: hover; anchors.fill: parent; hoverEnabled: true; onClicked: root.clicked() }
}
