import QtQuick
import qs.Commons as Commons

Column {
  id: root
  property string title: ""
  property string value: ""
  property var choices: []
  property color background: Commons.Color.background
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  signal chosen(string value)
  spacing: 6
  Text { text: root.title; color: root.foreground; font.family: Commons.Style.font.family; font.pixelSize: 12; font.weight: Font.DemiBold }
  Flow {
    width: parent.width; spacing: 6
    Repeater {
      model: root.choices
      ControlButton {
        required property var modelData
        readonly property bool selected: modelData.value === root.value
        width: Math.min(implicitWidth, root.width)
        text: (selected ? "● " : "○ ") + modelData.label
        highlighted: selected
        background: root.background; foreground: root.foreground; accent: root.accent
        Accessible.role: Accessible.RadioButton
        Accessible.name: modelData.label
        Accessible.checkable: true
        Accessible.checked: selected
        onClicked: if (!selected) root.chosen(modelData.value)
      }
    }
  }
}
