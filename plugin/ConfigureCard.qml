import QtQuick
import qs.Commons as Commons

Rectangle {
  id: root
  property string mode: ""
  property string agent: ""
  property var catalog: ({agents: [], enabled: [], settings: {}})
  property string error: ""
  property color background: Commons.Color.background
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  signal addRequested(string name)
  signal commandRequested(string command, string argument)
  signal settingRequested(string key, string value)
  signal arrangeRequested(string name)
  signal dismissed()
  width: 390
  height: content.implicitHeight + 28
  radius: 14
  color: background
  border.width: 2; border.color: accent
  Keys.onEscapePressed: dismissed()
  Accessible.role: Accessible.Dialog
  Accessible.name: title.text
  function cycle(values, value) { return values[(values.indexOf(value) + 1) % values.length] }

  Column {
    id: content
    x: 14; y: 14; width: parent.width - 28; spacing: 8
    Row {
      width: parent.width
      Text { id: title; width: parent.width - 65; text: root.mode === "add" ? "Add an installed agent" : root.mode === "tab" ? root.agent : "Agent settings"; color: root.foreground; font.family: Commons.Style.font.family; font.pixelSize: 14; font.bold: true; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
      ControlButton { text: "Done"; background: root.background; foreground: root.foreground; accent: root.accent; onClicked: root.dismissed() }
    }
    Text { visible: root.error !== ""; width: parent.width; wrapMode: Text.WordWrap; text: root.error; color: root.foreground; font.family: Commons.Style.font.family; font.pixelSize: 12 }
    Flickable {
      visible: root.mode === "add"
      width: parent.width; implicitHeight: Math.min(360, agentRows.implicitHeight)
      contentHeight: agentRows.implicitHeight; clip: true
      Column {
      id: agentRows
      width: parent.width; spacing: 6
      Repeater {
        model: root.catalog.agents || []
        ControlButton {
          required property var modelData
          width: content.width
          text: modelData.name + (modelData.enabled ? " · added" : "")
          enabled: !modelData.enabled
          background: root.background; foreground: root.foreground; accent: root.accent
          onClicked: root.addRequested(modelData.name)
        }
      }
      Text { visible: !(root.catalog.agents || []).length; width: parent.width; wrapMode: Text.WordWrap; text: "No installed agents found. Install an agent, then reopen Add agent."; color: root.foreground; font.family: Commons.Style.font.family; font.pixelSize: 12 }
    }
      }
    Column {
      visible: root.mode === "tab"
      width: parent.width; spacing: 6
      Repeater {
        model: [{text:"Move left",cmd:"left"},{text:"Move right",cmd:"right"},{text:"Close window",cmd:"close"},{text:"Restart",cmd:"restart"},{text:"Disable agent",cmd:"disable"}]
        ControlButton {
          required property var modelData
          width: content.width; text: modelData.text
          enabled: modelData.cmd !== "left" && modelData.cmd !== "right" || ((root.catalog.enabled || []).indexOf(root.agent) + (modelData.cmd === "left" ? -1 : 1) >= 0 && (root.catalog.enabled || []).indexOf(root.agent) + (modelData.cmd === "left" ? -1 : 1) < (root.catalog.enabled || []).length)
          background: root.background; foreground: root.foreground; accent: root.accent
          onClicked: root.commandRequested(modelData.cmd, root.agent)
        }
      }
      ControlButton { width: content.width; text: "Arrange tabs · Super+Shift+←/→"; background: root.background; foreground: root.foreground; accent: root.accent; onClicked: root.arrangeRequested(root.agent) }
    }
    Column {
      visible: root.mode === "settings"
      width: parent.width; spacing: 6
      ControlButton { width: content.width; text: "Arrange tabs · Super+Shift+←/→"; enabled: (root.catalog.enabled || []).length > 1; background: root.background; foreground: root.foreground; accent: root.accent; onClicked: root.arrangeRequested("") }
      ControlButton {
        width: content.width; text: "Open: " + (root.catalog.settings.open_on || "last")
        background: root.background; foreground: root.foreground; accent: root.accent
        onClicked: root.settingRequested("open_on", root.cycle(["last", "first"].concat(root.catalog.enabled || []), root.catalog.settings.open_on || "last"))
      }
      ControlButton { width: content.width; text: "Hints: " + (root.catalog.settings.show_hint ? "on" : "off"); background: root.background; foreground: root.foreground; accent: root.accent; onClicked: root.settingRequested("show_hint", root.catalog.settings.show_hint ? "false" : "true") }
      ControlButton { width: content.width; text: "Usage display: " + (root.catalog.settings.usage_display || "fill"); background: root.background; foreground: root.foreground; accent: root.accent; onClicked: root.settingRequested("usage_display", root.cycle(["fill", "percent", "off"], root.catalog.settings.usage_display || "fill")) }
      ControlButton {
        width: content.width; text: "Window opacity: " + Math.round(parseFloat(root.catalog.settings.opacity || "1") * 100) + "%"
        background: root.background; foreground: root.foreground; accent: root.accent
        onClicked: { var v = parseFloat(root.catalog.settings.opacity || "1"); var n = v < 0.85 ? "0.85 0.85" : v < 1 ? "1.0 1.0" : "0.75 0.75"; root.settingRequested("opacity", n) }
      }
      Text { width: parent.width; wrapMode: Text.WordWrap; text: "Changes save immediately. Click an option to cycle it. Colours follow your Omarchy theme."; color: root.foreground; font.family: Commons.Style.font.family; font.pixelSize: 11 }
    }
  }
}
