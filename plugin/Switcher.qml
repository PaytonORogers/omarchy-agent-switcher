import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons

// Tab strip shown under the omarchy-agents drop-down. All state comes from the
// omarchy-agents script via `omarchy-shell shell summon <id> <payload>`.
Item {
  id: root
  property bool opened: false
  property var agents: []          // [{ name, icon, state: running|starting|stopped }]
  property string active: ""
  property string monitorName: ""
  property int stripTop: 0
  property double lastSeq: 0
  property string bin: Quickshell.env("HOME") + "/.local/bin/omarchy-agents"
  property string toggleKey: "SUPER + A"
  property string prevKey: "SUPER + ALT + LEFT"
  property string nextKey: "SUPER + ALT + RIGHT"
  property bool hint: true
  property color accent: Color.accent      // overridden by `accent =` in agents.conf
  property string menuFor: ""              // agent whose right-click menu is open
  property var shortcuts: []               // [{ keys, action }] generated from the live config
  property bool sheet: false               // cheat-sheet overlay

  readonly property color fg: Color.foreground
  readonly property color bg: Color.background

  function open(payloadJson) {
    try {
      var p = JSON.parse(payloadJson || "{}")
      // Updates are sent in the background; drop any that arrive out of order.
      if (p.seq !== undefined) { if (p.seq < lastSeq) return; lastSeq = p.seq }
      if (p.agents) agents = p.agents
      if (p.active !== undefined) active = p.active
      if (p.accent) accent = p.accent
      if (p.bin) bin = p.bin
      if (p.monitor !== undefined) monitorName = p.monitor
      if (p.top) stripTop = p.top
      if (p.toggleKey) toggleKey = p.toggleKey
      if (p.prevKey !== undefined) prevKey = p.prevKey
      if (p.nextKey !== undefined) nextKey = p.nextKey
      if (p.hint !== undefined) hint = p.hint
      if (p.shortcuts) shortcuts = p.shortcuts
      sheet = p.sheet === true
      opened = true
      lastShow = Date.now()
    } catch (e) {}
  }
  function close() { opened = false; menuFor = ""; sheet = false }
  // One process per call, so quick clicks/scrolls are never dropped.
  Component { id: runner; Process { onExited: destroy() } }
  function run(args) { var p = runner.createObject(root, { command: [root.bin].concat(args) }); p.running = true }
  function screenFor(name) {
    var s = Quickshell.screens
    for (var i = 0; i < s.length; i++) if (s[i].name === name) return s[i]
    return s.length ? s[0] : null
  }
  function prettyKey(k) { return (k || "").replace(/\s*\+\s*/g, "+").replace("SUPER", "Super").replace("SHIFT", "Shift").replace("ALT", "Alt").replace("CTRL", "Ctrl").replace("LEFT", "←").replace("RIGHT", "→") }

  // Auto-hide: when focus leaves special:agents (link opened a browser, user
  // clicked another app or workspace) the script hides panel + strip together.
  property double lastShow: 0
  Process { id: autohideProc; command: [root.bin, "autohide"] }
  Timer { id: autohideTimer; interval: 180; onTriggered: if (root.opened && !autohideProc.running) autohideProc.running = true }
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!root.opened || !event || !event.name) return
      var n = String(event.name)
      if (n !== "activewindowv2" && n !== "activespecial" && n !== "workspace" && n !== "workspacev2" && n !== "focusedmon" && n !== "openwindow" && n !== "closewindow") return
      if (Date.now() - root.lastShow < 400) return
      root.sheet = false   // click-away / focus change closes the cheat sheet
      autohideTimer.restart()
    }
  }

  IpcHandler {
    target: "agentswitcher"
    function show(payloadJson: string): string { root.open(payloadJson); return "ok" }
    function hide(): string { root.close(); return "ok" }
    function refresh(): string { if (root.opened) root.run(["show", root.active]); return "ok" }
    function state(): string { return root.opened ? "open:" + root.active : "closed" }
    function ping(): string { return "ok" }
    function metrics(): string { return "window=" + win.implicitWidth + "x" + win.implicitHeight + " strip=" + strip.width + " sheet=" + root.sheet }
    function shortcuts(): string { if (!root.opened) return "closed"; root.sheet = !root.sheet; return root.sheet ? "shown" : "hidden" }
  }

  // Touchpads send many small wheel steps: switch once per full notch, at most every 150 ms.
  property real wheelAcc: 0
  property double lastWheel: 0
  function wheel(dy) {
    wheelAcc += dy
    if (Math.abs(wheelAcc) < 120 || Date.now() - lastWheel < 150) return
    run([wheelAcc < 0 ? "next" : "prev"]); wheelAcc = 0; lastWheel = Date.now()
  }

  PanelWindow {
    id: win
    visible: root.opened
    screen: root.screenFor(root.monitorName)
    anchors { top: true }
    // The cheat sheet sits above the strip, so the window grows upward.
    margins.top: Math.max(0, root.stripTop - (sheetBox.visible ? sheetBox.height + 8 : 0))
    implicitWidth: Math.max(strip.width, menu.visible ? menu.width + 16 : 0, sheetBox.visible ? sheetBox.width + 8 : 0)
    implicitHeight: (sheetBox.visible ? sheetBox.height + 8 : 0) + 44 + (menu.visible ? 20 : 0)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-agent-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    // Focus only when clicked, so the agent keeps the keyboard otherwise.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    Rectangle {
      id: sheetBox
      visible: root.sheet
      anchors.top: parent.top
      anchors.horizontalCenter: parent.horizontalCenter
      width: grid.implicitWidth + 28
      height: grid.implicitHeight + sheetTitle.implicitHeight + 30
      radius: 14
      color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.94)
      border.width: 2
      border.color: root.accent
      Accessible.role: Accessible.Dialog
      Accessible.name: "Agent switcher shortcuts"
      MouseArea { anchors.fill: parent; onClicked: root.sheet = false }
      Text { id: sheetTitle; x: 14; y: 10; text: "Agent switcher shortcuts"; color: root.accent; font.family: Style.font.family; font.pixelSize: 12; font.weight: Font.DemiBold }
      Grid {
        id: grid
        x: 14; anchors.top: sheetTitle.bottom; anchors.topMargin: 8
        columns: 2; columnSpacing: 18; rowSpacing: 4
        Repeater {
          model: root.shortcuts.length * 2
          Text {
            required property int index
            readonly property var e: root.shortcuts[Math.floor(index / 2)]
            text: index % 2 === 0 ? e.keys : e.action
            color: index % 2 === 0 ? root.fg : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.7)
            font.family: Style.font.family; font.pixelSize: 11
            font.weight: index % 2 === 0 ? Font.DemiBold : Font.Normal
          }
        }
      }
    }

    Rectangle {
      id: strip
      anchors.top: sheetBox.visible ? sheetBox.bottom : parent.top
      anchors.topMargin: sheetBox.visible ? 8 : 0
      anchors.horizontalCenter: parent.horizontalCenter
      width: row.implicitWidth + 16
      height: 44
      radius: 22
      color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.78)
      border.width: 2
      border.color: root.accent
      focus: true
      Accessible.role: Accessible.PageTabList
      Accessible.name: "Agent switcher"

      Keys.onLeftPressed: root.run(["prev"])
      Keys.onRightPressed: root.run(["next"])
      Keys.onTabPressed: root.run(["next"])
      Keys.onBacktabPressed: root.run(["prev"])
      Keys.onEscapePressed: { if (root.sheet) root.sheet = false; else if (root.menuFor !== "") root.menuFor = ""; else root.run(["hide"]) }
      Keys.onPressed: (e) => { if (e.key === Qt.Key_Question || e.text === "?") { root.sheet = !root.sheet; e.accepted = true } else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9) root.run(["show", String(e.key - Qt.Key_1)]) }

      WheelHandler { onWheel: (e) => root.wheel(e.angleDelta.y) }

      Row {
        id: row
        anchors.centerIn: parent
        spacing: 4
        Repeater {
          model: root.agents
          Rectangle {
            id: tab
            required property var modelData
            required property int index
            readonly property bool sel: modelData.name === root.active
            readonly property string st: modelData.state || "running"
            width: content.implicitWidth + 30
            height: 32
            radius: 16
            opacity: st === "stopped" && !sel ? 0.6 : 1.0
            color: sel ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.85)
                       : (ma.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22) : "transparent")
            // keyboard focus ring on the active tab
            border.width: (sel && strip.activeFocus) ? 2 : ((!sel && ma.containsMouse) ? 1 : 0)
            border.color: (sel && strip.activeFocus) ? root.fg : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.6)
            Behavior on color { ColorAnimation { duration: 140 } }
            Accessible.role: Accessible.PageTab
            Accessible.name: modelData.name + (st === "starting" ? ", starting" : st === "stopped" ? ", not started" : "")
            Accessible.selected: sel
            Row {
              id: content
              anchors.centerIn: parent
              spacing: 7
              Image {
                visible: source != ""
                source: tab.modelData.icon || ""
                width: 16; height: 16
                sourceSize: Qt.size(32, 32)
                anchors.verticalCenter: parent.verticalCenter
                smooth: true
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: tab.modelData.name + (tab.st === "starting" ? " …" : "")
                color: tab.sel ? "#FFFFFF" : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.78)
                font.family: Style.font.family
                font.weight: tab.sel ? Font.DemiBold : Font.Normal
                font.pixelSize: 13
              }
            }
            MouseArea {
              id: ma
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
              onClicked: (m) => {
                strip.forceActiveFocus()
                if (m.button === Qt.RightButton) root.menuFor = (root.menuFor === tab.modelData.name ? "" : tab.modelData.name)
                else if (m.button === Qt.MiddleButton) root.run(["close", tab.modelData.name])
                else { root.menuFor = ""; root.run(["show", tab.modelData.name]) }
              }
            }
          }
        }
        // Compact shortcuts affordance (show_hint controls it).
        Rectangle {
          visible: root.hint
          width: qlbl.implicitWidth + 16; height: 24; radius: 12
          anchors.verticalCenter: parent.verticalCenter
          color: (qma.containsMouse || root.sheet) ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.3) : "transparent"
          border.width: 1; border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.6)
          Accessible.role: Accessible.Button
          Accessible.name: "Show shortcuts"
          Text { id: qlbl; anchors.centerIn: parent; text: "? shortcuts"; color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.7); font.family: Style.font.family; font.pixelSize: 10 }
          MouseArea { id: qma; anchors.fill: parent; hoverEnabled: true; onClicked: { strip.forceActiveFocus(); root.sheet = !root.sheet } }
        }
      }
    }

    // Right-click menu (replaces the hint line while open).
    Row {
      id: menu
      visible: root.menuFor !== ""
      anchors.top: strip.bottom
      anchors.topMargin: 3
      anchors.horizontalCenter: strip.horizontalCenter
      spacing: 6
      Repeater {
        model: [ { label: "Restart", cmd: "restart" }, { label: "Close", cmd: "close" } ]
        Rectangle {
          required property var modelData
          width: lbl.implicitWidth + 18; height: 18; radius: 9
          color: mma.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.5) : Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.85)
          border.width: 1; border.color: root.accent
          Accessible.role: Accessible.Button
          Accessible.name: modelData.label + " " + root.menuFor
          Text { id: lbl; anchors.centerIn: parent; text: modelData.label + " " + root.menuFor; color: root.fg; font.family: Style.font.family; font.pixelSize: 10 }
          MouseArea { id: mma; anchors.fill: parent; hoverEnabled: true; onClicked: { root.run([modelData.cmd, root.menuFor]); root.menuFor = "" } }
        }
      }
    }

  }
}
