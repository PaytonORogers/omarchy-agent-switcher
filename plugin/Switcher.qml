import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// Tab strip shown under the omarchy-agents drop-down. All state comes from the
// omarchy-agents script via `omarchy-shell shell summon <id> <payload>`.
Item {
  id: root
  property bool opened: false
  property var agents: []          // [{ name, icon }]
  property string active: ""
  property string monitorName: ""
  property int stripTop: 0
  property string bin: Quickshell.env("HOME") + "/.local/bin/omarchy-agents"
  property string toggleKey: "SUPER + A"
  property string prevKey: "SUPER + ALT + LEFT"
  property string nextKey: "SUPER + ALT + RIGHT"
  property bool hint: true
  property color accent: Color.accent      // overridden by `accent =` in agents.conf

  readonly property color fg: Color.foreground
  readonly property color bg: Color.background

  function open(payloadJson) {
    try {
      var p = JSON.parse(payloadJson || "{}")
      if (p.agents) agents = p.agents
      if (p.active !== undefined) active = p.active
      if (p.accent) accent = p.accent
      if (p.bin) bin = p.bin
      if (p.monitor !== undefined) monitorName = p.monitor
      if (p.top) stripTop = p.top
      if (p.toggleKey) toggleKey = p.toggleKey
      if (p.prevKey) prevKey = p.prevKey
      if (p.nextKey) nextKey = p.nextKey
      if (p.hint !== undefined) hint = p.hint
      opened = true
    } catch (e) {}
  }
  function close() { opened = false }
  function run(args) { proc.command = [root.bin].concat(args); proc.running = true }
  function screenFor(name) {
    var s = Quickshell.screens
    for (var i = 0; i < s.length; i++) if (s[i].name === name) return s[i]
    return s.length ? s[0] : null
  }
  function prettyKey(k) { return k.replace(/\s*\+\s*/g, "+").replace("SUPER", "Super").replace("SHIFT", "Shift").replace("ALT", "Alt").replace("CTRL", "Ctrl").replace("LEFT", "←").replace("RIGHT", "→") }

  Process { id: proc }

  IpcHandler {
    target: "agentswitcher"
    function show(payloadJson: string): string { root.open(payloadJson); return "ok" }
    function hide(): string { root.close(); return "ok" }
    function state(): string { return root.opened ? "open:" + root.active : "closed" }
    function ping(): string { return "ok" }
    function metrics(): string { return "window=" + win.implicitWidth + " strip=" + strip.width + " hint=" + Math.ceil(hintText.implicitWidth) + " hintVisible=" + root.hint }
  }

  PanelWindow {
    id: win
    visible: root.opened
    screen: root.screenFor(root.monitorName)
    anchors { top: true }
    margins.top: root.stripTop
    // Wide enough for the tab row or the hint, whichever is longer.
    implicitWidth: Math.max(strip.width, root.hint ? hintText.implicitWidth + 24 : 0)
    implicitHeight: 44 + (root.hint ? 18 : 0)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-agent-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    // Focus only when clicked, so the agent keeps the keyboard otherwise.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    Rectangle {
      id: strip
      anchors.horizontalCenter: parent.horizontalCenter
      width: row.implicitWidth + 16
      height: 44
      radius: 22
      color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.78)
      border.width: 2
      border.color: root.accent
      focus: true

      Keys.onLeftPressed: root.run(["prev"])
      Keys.onRightPressed: root.run(["next"])
      Keys.onTabPressed: root.run(["next"])
      Keys.onBacktabPressed: root.run(["prev"])
      Keys.onEscapePressed: root.run(["hide"])
      Keys.onPressed: (e) => { if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9) root.run(["show", String(e.key - Qt.Key_1)]) }

      WheelHandler { onWheel: (e) => root.run([e.angleDelta.y < 0 ? "next" : "prev"]) }

      Row {
        id: row
        anchors.centerIn: parent
        spacing: 4
        Repeater {
          model: root.agents
          Rectangle {
            required property var modelData
            required property int index
            readonly property bool sel: modelData.name === root.active
            width: content.implicitWidth + 30
            height: 32
            radius: 16
            color: sel ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.85)
                       : (ma.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22) : "transparent")
            border.width: (!sel && ma.containsMouse) ? 1 : 0
            border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.6)
            Behavior on color { ColorAnimation { duration: 140 } }
            Row {
              id: content
              anchors.centerIn: parent
              spacing: 7
              Image {
                visible: source != ""
                source: modelData.icon || ""
                width: 16; height: 16
                sourceSize: Qt.size(32, 32)
                anchors.verticalCenter: parent.verticalCenter
                smooth: true
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.name
                color: parent.parent.sel ? "#FFFFFF" : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.78)
                font.family: Style.font.family
                font.weight: parent.parent.sel ? Font.DemiBold : Font.Normal
                font.pixelSize: 13
              }
            }
            MouseArea {
              id: ma
              anchors.fill: parent
              hoverEnabled: true
              onClicked: { strip.forceActiveFocus(); root.run(["show", modelData.name]) }
            }
          }
        }
      }
    }

    Text {
      id: hintText
      visible: root.hint
      anchors.top: strip.bottom
      anchors.topMargin: 3
      anchors.horizontalCenter: strip.horizontalCenter
      text: root.prettyKey(root.toggleKey) + " toggle · " + root.prettyKey(root.prevKey) + " / " + root.prettyKey(root.nextKey).replace(/.*\+/, "") + " switch · scroll"
      color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.45)
      font.family: Style.font.family
      font.pixelSize: 10
    }
  }
}
