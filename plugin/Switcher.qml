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
  property string edge: "bottom"           // top: strip under the bar, panel below; sheet opens downward
  property double lastSeq: 0
  property string bin: Quickshell.env("HOME") + "/.local/bin/omarchy-agents"
  property string toggleKey: "SUPER + A"
  property string shortcutsKey: ""
  property string prevKey: "SUPER + ALT + LEFT"
  property string nextKey: "SUPER + ALT + RIGHT"
  property bool hint: true
  property color accent: Color.accent      // overridden by `accent =` in agents.conf
  property string menuFor: ""              // agent whose right-click menu is open
  property var shortcuts: []               // [{ keys, action }] generated from the live config
  property string hoverInfo: ""             // usage detail for the hovered tab, shown in the hint line
  property bool sheet: false               // cheat-sheet overlay
  property string usageDisplay: "fill"     // fill | percent | off
  property real usageWarn: 0.7
  property real usageCrit: 0.9
  property real usageRefreshMin: 10

  // Popup roles follow shell.toml overrides; typed properties convert role strings to colors.
  readonly property color surfaceBackground: Color.popups ? Color.popups.background : Color.background
  readonly property color themeText: Color.popups ? Color.popups.text : Color.foreground
  // Keep the strip opaque for readability, retaining the popup palette.
  readonly property color bg: Qt.rgba(surfaceBackground.r, surfaceBackground.g, surfaceBackground.b, 1)
  readonly property color fg: readableText(bg, themeText)

  function luminance(c) {
    function linear(v) { return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
  }
  function contrast(a, b) {
    var x = luminance(a), y = luminance(b)
    return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05)
  }
  function readableText(background, preferred) {
    if (contrast(background, preferred) >= 4.5) return preferred
    // The theme surface is often the right ink on a light accent pill.
    if (contrast(background, bg) >= 4.5) return bg
    return luminance(background) > 0.179 ? "#000000" : "#FFFFFF"
  }

  function open(payloadJson) {
    try {
      var p = JSON.parse(payloadJson || "{}")
      // Updates are sent in the background; drop any that arrive out of order.
      if (p.seq !== undefined) { if (p.seq < lastSeq) return; lastSeq = p.seq }
      if (p.agents) agents = p.agents
      // Only a real open or tab switch starts the "our own action" grace period; passive
      // refreshes (usage, status) must not swallow the focus change from a newly opened window.
      if (!opened || (p.active !== undefined && p.active !== active)) lastShow = Date.now()
      if (p.active !== undefined) active = p.active
      if (p.accent) accent = p.accent
      if (p.bin) bin = p.bin
      if (p.monitor !== undefined) monitorName = p.monitor
      if (p.top) stripTop = p.top
      if (p.edge) edge = p.edge
      if (p.toggleKey) toggleKey = p.toggleKey
      if (p.shortcutsKey !== undefined) shortcutsKey = p.shortcutsKey
      if (p.prevKey !== undefined) prevKey = p.prevKey
      if (p.nextKey !== undefined) nextKey = p.nextKey
      if (p.hint !== undefined) hint = p.hint
      if (p.shortcuts) shortcuts = p.shortcuts
      sheet = p.sheet === true
      if (p.usageDisplay) usageDisplay = p.usageDisplay
      if (p.usageWarn !== undefined) usageWarn = p.usageWarn
      if (p.usageCrit !== undefined) usageCrit = p.usageCrit
      if (p.usageRefreshMin) usageRefreshMin = p.usageRefreshMin
      opened = true
    } catch (e) {}
  }
  // Closing the sheet on purpose (key, click, Esc) hands the keyboard back to the agent:
  // the strip is an on-demand layer surface and otherwise keeps keyboard focus.
  function hideSheet() { if (!sheet) return; sheet = false; if (opened) run(["refocus"]) }
  onSheetChanged: run(["sheet-keys", sheet ? "on" : "off"])   // Esc bind only while the sheet is up
  function toggleSheet() { if (sheet) hideSheet(); else sheet = true }
  function close() { opened = false; menuFor = ""; sheet = false }
  // One process per call, so quick clicks/scrolls are never dropped.
  Component { id: runner; Process { onExited: destroy() } }
  function run(args) { var p = runner.createObject(root, { command: [root.bin].concat(args) }); p.running = true }
  function screenFor(name) {
    var s = Quickshell.screens
    for (var i = 0; i < s.length; i++) if (s[i].name === name) return s[i]
    return s.length ? s[0] : null
  }
  function prettyKey(k) { return (k || "").replace(/\s*\+\s*/g, "+").replace("SUPER", "Super").replace("SHIFT", "Shift").replace("ALT", "Alt").replace("CTRL", "Ctrl").replace("LEFT", "←").replace("RIGHT", "→").replace("SLASH", "/") }

  // `omarchy plugin add` clones the repo as the plugin but runs no install hook, so on
  // load we run ../install.sh --from-shell. It is a no-op once installed (marker file);
  // copies made by install.sh have no install.sh next to them, so this does nothing there.
  // (Approach from TheronRogers' PR #1.)
  Process { id: finishInstall }
  Component.onCompleted: {
    var script = decodeURIComponent(String(Qt.resolvedUrl("../install.sh")).replace(/^file:\/\//, ""))
    finishInstall.command = ["bash", "-c", 'if [ -f "$1" ]; then exec "$1" --from-shell; fi', "agent-switcher", script]
    finishInstall.running = true
  }

  // Usage meter colour: accent below usage_warn, amber to usage_crit, red above.
  // Agent status dots: working pulses in violet, approval amber, error red, done (waiting on you) green.
  function statusColor(s) { return s === "approval" ? "#E3A23B" : s === "error" ? "#E5534B" : s === "done" ? "#57AB5A" : "#9B7BD4" }
  // Grok Bot has no hooks: watch desktop notifications for its replies (restarts if it exits).
  Process { id: notifWatch; command: [root.bin, "notif-watch"]; running: root.bin !== "" }
  Timer { interval: 30000; repeat: true; running: root.bin !== ""; onTriggered: if (!notifWatch.running) notifWatch.running = true }
  function usageColor(u) { return u >= usageCrit ? "#E5534B" : (u >= usageWarn ? "#E3A23B" : accent) }
  // Refresh usage every usage_refresh_min while open (the script caches and rate-limits).
  Timer { interval: Math.max(1, root.usageRefreshMin) * 60000; repeat: true; running: root.opened && root.usageDisplay !== "off"; onTriggered: root.run(["usage"]) }

  // Auto-hide: when focus leaves special:agents (link opened a browser, user
  // clicked another app or workspace) the script hides panel + strip together.
  property double lastShow: 0
  Process { id: autohideProc; command: [root.bin, "autohide"] }
  Timer { id: autohideTimer; interval: 180; onTriggered: if (root.opened && !autohideProc.running) autohideProc.running = true }
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || !event.name) return
      var n = String(event.name)
      // openwindow data: ADDRESS,WORKSPACE,CLASS,TITLE. A non-agent window that lands on the
      // agents workspace is moved out by the script (it checks the class against agents.conf).
      if (n === "openwindow") { var d = String(event.data || "").split(","); if (d[1] === "special:agents") root.run(["evict", "0x" + d[0].replace(/^0x/, "")]) }
      if (!root.opened) return
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
    function closeSheet(): string { root.hideSheet(); return "ok" }
    function status(): string { if (root.opened) root.run(["show", root.active]); return "ok" }   // an agent status changed
    function ping(): string { return "ok" }
    function metrics(): string { return "window=" + win.implicitWidth + "x" + win.implicitHeight + " strip=" + strip.width + " sheet=" + root.sheet }
    function shortcuts(): string { if (!root.opened) return "closed"; root.toggleSheet(); return root.sheet ? "shown" : "hidden" }
  }

  // Touchpads send many small wheel steps: switch once per full notch, at most every 150 ms.
  property real wheelAcc: 0
  property double lastWheel: 0
  function wheel(dy) {
    wheelAcc += dy
    if (Math.abs(wheelAcc) < 120 || Date.now() - lastWheel < 150) return
    run([wheelAcc < 0 ? "next" : "prev"]); wheelAcc = 0; lastWheel = Date.now()
  }

  // Click-away for the cheat sheet: while it's up, a transparent full-screen layer under the
  // strip catches the next click anywhere else (including on the agent) and closes the sheet.
  PanelWindow {
    id: sheetCatcher
    visible: root.opened && root.sheet
    screen: root.screenFor(root.monitorName)
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-agent-switcher-sheet"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: root.hideSheet() }
  }

  PanelWindow {
    id: win
    visible: root.opened
    screen: root.screenFor(root.monitorName)
    anchors { top: true }
    // The cheat sheet sits above the strip, so the window grows upward.
    margins.top: root.edge === "top" ? root.stripTop : Math.max(0, root.stripTop - (sheetBox.visible ? sheetBox.height + 8 : 0))
    implicitWidth: Math.max(strip.width, menu.visible ? menu.width + 16 : 0, hintLine.visible ? hintMetrics.width + 16 : 0, sheetBox.visible ? sheetBox.width + 8 : 0)
    implicitHeight: (sheetBox.visible ? sheetBox.height + 8 : 0) + 44 + ((menu.visible || hintLine.visible) ? 20 : 0)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-agent-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    // Never take keyboard focus: an on-demand layer grabs it when it maps, which left
    // the agent window unable to type after every open. Clicks still work.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
      id: sheetBox
      visible: root.sheet
      anchors.top: root.edge === "top" ? (menu.visible ? menu.bottom : (hintLine.visible ? hintLine.bottom : strip.bottom)) : parent.top
      anchors.topMargin: root.edge === "top" ? 8 : 0
      anchors.horizontalCenter: parent.horizontalCenter
      width: grid.implicitWidth + 28
      height: grid.implicitHeight + sheetTitle.implicitHeight + 30
      radius: 14
      color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.94)
      border.width: 2
      border.color: root.accent
      Accessible.role: Accessible.Dialog
      Accessible.name: "Agent switcher shortcuts"
      MouseArea { anchors.fill: parent; onClicked: root.hideSheet() }
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
      anchors.top: (sheetBox.visible && root.edge !== "top") ? sheetBox.bottom : parent.top
      anchors.topMargin: (sheetBox.visible && root.edge !== "top") ? 8 : 0
      anchors.horizontalCenter: parent.horizontalCenter
      width: row.implicitWidth + 16
      height: 44
      radius: 22
      color: root.bg
      border.width: 2
      border.color: root.accent
      focus: true
      Accessible.role: Accessible.PageTabList
      Accessible.name: "Agent switcher"

      Keys.onLeftPressed: root.run(["prev"])
      Keys.onRightPressed: root.run(["next"])
      Keys.onTabPressed: root.run(["next"])
      Keys.onBacktabPressed: root.run(["prev"])
      Keys.onEscapePressed: { if (root.sheet) root.hideSheet(); else if (root.menuFor !== "") root.menuFor = ""; else root.run(["hide"]) }
      Keys.onPressed: (e) => { if (e.key === Qt.Key_Question || e.text === "?") { root.toggleSheet(); e.accepted = true } else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9) root.run(["show", String(e.key - Qt.Key_1)]) }

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
            opacity: 1.0
            color: sel ? root.accent
                       : (ma.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22) : "transparent")
            // keyboard focus ring on the active tab
            border.width: (sel && strip.activeFocus) ? 2 : ((!sel && ma.containsMouse) ? 1 : 0)
            border.color: (sel && strip.activeFocus) ? root.fg : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.6)
            Behavior on color { ColorAnimation { duration: 140 } }
            readonly property real usage: modelData.usage === undefined ? -1 : modelData.usage
            readonly property bool hasUsage: usage >= 0 && root.usageDisplay !== "off"
            clip: true
            // usage fill, left to right behind the label
            Rectangle {
              visible: tab.hasUsage && root.usageDisplay === "fill"
              anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
              width: parent.width * Math.min(1, Math.max(0, tab.usage))
              radius: Math.min(parent.radius, width / 2)
              color: root.usageColor(tab.usage)
              opacity: tab.sel ? 0.45 : 0.3
              Behavior on width { NumberAnimation { duration: 300 } }
            }
            readonly property string status: modelData.status || "idle"
            // status dot, top-right corner of the tab
            Rectangle {
              visible: tab.status !== "idle"
              width: 7; height: 7; radius: 3.5; z: 5
              anchors { right: parent.right; top: parent.top; rightMargin: 7; topMargin: 4 }
              color: root.statusColor(tab.status)
              border.width: 1; border.color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.8)
              SequentialAnimation on opacity {
                running: tab.status === "working"; loops: Animation.Infinite
                NumberAnimation { to: 0.3; duration: 700 } NumberAnimation { to: 1; duration: 700 }
                onRunningChanged: if (!running) parent.opacity = 1
              }
            }
            Accessible.role: Accessible.PageTab
            Accessible.name: modelData.name + (status !== "idle" ? ", " + status : "") + (st === "starting" ? ", starting" : st === "stopped" ? ", not started" : "") + (hasUsage ? ", " + (modelData.usageLabel || Math.round(usage * 100) + "% used") : "")
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
                color: tab.sel ? root.readableText(root.accent, root.themeText) : root.fg
                font.family: Style.font.family
                font.weight: tab.sel ? Font.DemiBold : Font.Normal
                font.pixelSize: 13
              }
              // Percent only in "percent" mode; hover detail goes in the fixed-width hint line,
              // so hovering never changes any size.
              Text {
                visible: tab.hasUsage && root.usageDisplay === "percent"
                anchors.verticalCenter: parent.verticalCenter
                width: pctMetrics.width
                horizontalAlignment: Text.AlignRight
                text: Math.round(tab.usage * 100) + "%"
                color: tab.sel ? root.readableText(root.accent, root.themeText) : root.fg
                font.family: Style.font.family; font.pixelSize: 12
                TextMetrics { id: pctMetrics; font.family: Style.font.family; font.pixelSize: 12; text: "100%" }
              }
            }
            MouseArea {
              id: ma
              anchors.fill: parent
              hoverEnabled: true
              onContainsMouseChanged: root.hoverInfo = (containsMouse && tab.hasUsage)
                ? tab.modelData.name + ": " + (tab.modelData.usageLabel || Math.round(tab.usage * 100) + "%") + "  ·  can lag or differ slightly from the provider" : ""
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
      }
    }

    // Hint line under the tabs (show_hint / omarchy-agents hint on|off); the right-click menu replaces it.
    Text {
      id: hintLine
      // Fixed size: the line's width comes from the default hint text (never from the hover text),
      // and it is always reserved, so hovering can't resize/re-centre the strip window.
      visible: root.hint && root.menuFor === ""
      anchors.top: strip.bottom
      anchors.topMargin: 4
      anchors.horizontalCenter: strip.horizontalCenter
      width: Math.max(hintMetrics.width, strip.width - 16)
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      TextMetrics { id: hintMetrics; font: hintLine.font; text: hintLine.defaultText }
      readonly property string defaultText: ((root.shortcutsKey !== "" ? root.prettyKey(root.shortcutsKey) : "?") + " shortcuts"
            + (root.prevKey !== "" && root.nextKey !== "" ? "  ·  " + root.prettyKey(root.prevKey) + " / " + root.prettyKey(root.nextKey) + " switch" : "")
            + "  ·  " + root.prettyKey(root.toggleKey) + " close")
      text: root.hoverInfo !== "" ? root.hoverInfo : defaultText
      color: root.fg
      font.family: Style.font.family; font.pixelSize: 10
      style: Text.Outline; styleColor: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.6)
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
