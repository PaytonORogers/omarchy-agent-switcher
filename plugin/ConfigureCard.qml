import QtQuick
import QtQuick.Controls
import qs.Commons as Commons

Rectangle {
  id: root
  property string mode: ""
  property string agent: ""
  property var catalog: ({agents: [], enabled: [], settings: {}})
  property var shortcuts: []
  property real maximumContentHeight: 740
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
  function opacityValue() {
    var parts = String(root.catalog.settings.opacity || "1").trim().split(/\s+/)
    return parseFloat(parts[0]) + " " + parseFloat(parts[1] || parts[0])
  }
  function opacityChoices() {
    var choices = [{label:"75%",value:"0.75 0.75"},{label:"85%",value:"0.85 0.85"},{label:"100%",value:"1 1"}]
    var current = opacityValue()
    if (!choices.some(function(c) { return c.value === current })) {
      var parts = current.split(" ")
      var active = Math.round(parseFloat(parts[0]) * 100), inactive = Math.round(parseFloat(parts[1]) * 100)
      choices.unshift({label: active === inactive ? active + "%" : active + "% active / " + inactive + "% inactive", value: current})
    }
    return choices
  }

  Column {
    id: content
    x: 14; y: 14; width: parent.width - 28; spacing: 8
    Row {
      width: parent.width; spacing: 8
      Text { id: title; width: parent.width - closeButton.width - 8; text: root.mode === "add" ? "Add an installed agent" : root.mode === "tab" ? root.agent : "Agent settings"; color: root.foreground; font.family: Commons.Style.font.family; font.pixelSize: 14; font.bold: true; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
      CloseButton { id: closeButton; background: root.background; foreground: root.foreground; accent: root.accent; onClicked: root.dismissed() }
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
    Flickable {
      id: settingsViewport
      visible: root.mode === "settings"
      width: parent.width; implicitHeight: Math.min(settingsContent.implicitHeight, root.maximumContentHeight)
      contentHeight: settingsContent.implicitHeight; contentWidth: width
      clip: true; boundsBehavior: Flickable.StopAtBounds; flickableDirection: Flickable.VerticalFlick
      ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AsNeeded
        contentItem: Rectangle { implicitWidth: 3; implicitHeight: 24; radius: 1.5; color: root.accent }
        background: Rectangle { color: "transparent" }
      }
      Column {
      id: settingsContent
      width: parent.width; spacing: 12
      ControlButton { width: content.width; text: "Arrange tabs · Super+Shift+←/→"; enabled: (root.catalog.enabled || []).length > 1; background: root.background; foreground: root.foreground; accent: root.accent; onClicked: root.arrangeRequested("") }
      SettingChoices {
        width: content.width; title: "Opening target"; value: root.catalog.settings.open_on || "last"
        choices: [{label:"Last used",value:"last"},{label:"First tab",value:"first"}].concat((root.catalog.enabled || []).map(function(n) { return {label:n,value:n} }))
        background: root.background; foreground: root.foreground; accent: root.accent
        onChosen: (value) => root.settingRequested("open_on", value)
      }
      SettingChoices {
        width: content.width; title: "Hints"; value: root.catalog.settings.show_hint ? "true" : "false"
        choices: [{label:"On",value:"true"},{label:"Off",value:"false"}]
        background: root.background; foreground: root.foreground; accent: root.accent
        onChosen: (value) => root.settingRequested("show_hint", value)
      }
      SettingChoices {
        width: content.width; title: "Usage display"; value: root.catalog.settings.usage_display || "fill"
        choices: [{label:"Fill",value:"fill"},{label:"Percent",value:"percent"},{label:"Off",value:"off"}]
        background: root.background; foreground: root.foreground; accent: root.accent
        onChosen: (value) => root.settingRequested("usage_display", value)
      }
      SettingChoices {
        width: content.width; title: "Agent window opacity"; value: root.opacityValue(); choices: root.opacityChoices()
        background: root.background; foreground: root.foreground; accent: root.accent
        onChosen: (value) => root.settingRequested("opacity", value)
      }
      ShortcutsList { width: content.width - 8; entries: root.shortcuts; foreground: root.foreground }
      }
    }
  }
}
