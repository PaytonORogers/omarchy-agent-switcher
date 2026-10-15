import QtQuick
import qs.Commons as Commons

Column {
  id: root
  property var entries: []
  property color foreground: Commons.Color.foreground
  spacing: 8
  Text { text: "Keyboard shortcuts"; color: root.foreground; font.family: Commons.Style.font.family; font.pixelSize: 12; font.weight: Font.DemiBold }
  Repeater {
    model: root.entries
    Row {
      required property var modelData
      width: root.width; spacing: 10
      Text { width: root.width * 0.42; text: modelData.keys; wrapMode: Text.Wrap; color: root.foreground; font.family: Commons.Style.font.family; font.pixelSize: 11; font.weight: Font.DemiBold }
      Text { width: root.width * 0.58 - 10; text: modelData.action; wrapMode: Text.Wrap; color: root.foreground; font.family: Commons.Style.font.family; font.pixelSize: 11 }
    }
  }
}
