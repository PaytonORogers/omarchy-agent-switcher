import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons as Commons

// Tab strip shown under the omarchy-agents drop-down. All state comes from the
// omarchy-agents script via `omarchy-shell shell summon <id> <payload>`.
Item {
  id: root
  property var shell: null
  readonly property var idleService: shell && typeof shell.firstPartyServiceFor === "function" ? shell.firstPartyServiceFor("omarchy.idle") : null
  readonly property var lockService: shell && typeof shell.firstPartyServiceFor === "function" ? shell.firstPartyServiceFor("omarchy.lock") : null
  readonly property bool desktopBlocked: !!((idleService && (idleService.screensaverStartedThisCycle || idleService.screensaverWindowCount > 0)) || (lockService && lockService.locked))
  onDesktopBlockedChanged: if (desktopBlocked) { close(); run(["hide"]) }
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
  property color accent: Commons.Color.accent      // overridden by `accent =` in agents.conf
  property var catalog: ({agents: [], enabled: [], settings: {}})
  property bool catalogDirty: false
  property string controlMode: ""
  property string buttonHint: ""
  property string controlError: ""
  property bool arranging: false
  property string editAgent: ""
  property bool focusPrimed: false
  property var actionQueue: []
  property var loginResult: ({state: "checking"})
  property bool loginVisible: false
  property bool loginCancelled: false
  property string loginAgent: ""
  property string pendingLoginAction: ""
  property string menuFor: ""              // agent whose right-click menu is open
  property var shortcuts: []               // [{ keys, action }] generated from the live config
  property string hoverInfo: ""             // usage detail for the hovered tab, shown in the hint line
  property bool sheet: false               // cheat-sheet overlay
  property string usageDisplay: "fill"     // fill | percent | off
  property real usageWarn: 0.7
  property real usageCrit: 0.9
  property real usageRefreshMin: 10

  // Popup roles follow shell.toml overrides; typed properties convert role strings to colors.
  readonly property color surfaceBackground: Commons.Color.popups ? Commons.Color.popups.background : Commons.Color.background
  readonly property color themeText: Commons.Color.popups ? Commons.Color.popups.text : Commons.Color.foreground
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

  function readableFillOpacity(background, ink, overlay, maximum) {
    for (var a = maximum; a > 0; a -= 0.05) {
      var mixed = Qt.rgba(background.r * (1-a) + overlay.r * a, background.g * (1-a) + overlay.g * a, background.b * (1-a) + overlay.b * a, 1)
      if (contrast(mixed, ink) >= 4.5) return a
    }
    return 0
  }

  function open(payloadJson) {
    if (desktopBlocked) return
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
      if (p.configureOpen) {
        controlMode = p.picker ? "add" : "settings"
        loadCatalog()
      }
    } catch (e) {}
  }
  // Closing the sheet on purpose (key, click, Esc) hands the keyboard back to the agent:
  // the strip is an on-demand layer surface and otherwise keeps keyboard focus.
  function hideSheet() { if (!sheet) return; sheet = false; if (opened) run(["refocus"]) }
  onSheetChanged: run(["sheet-keys", sheet ? "on" : "off"])   // Esc bind only while the sheet is up
  function toggleSheet() { if (sheet) hideSheet(); else sheet = true }
  function endArrange() { if (!arranging) return; arranging = false; actionQueue = actionQueue.filter(function(a) { return a[0] !== "arrange-keys" }); mutate(["arrange-keys", "off"]) }
  function dismissControls() { if (loginProc.running && !loginVisible) { loginCancelled = true; loginProc.signal(15); } controlMode = ""; menuFor = ""; endArrange(); run(["refocus"]) }
  function close() { if (loginProc.running && !loginVisible) { loginCancelled = true; loginProc.signal(15); } endArrange(); opened = false; menuFor = ""; controlMode = ""; sheet = false }
  function loadCatalog() { if (catalogProc.running) catalogDirty = true; else catalogProc.running = true }
  function controls(mode, name) { if (desktopBlocked) return; focusPrimed = false; focusTimer.restart(); endArrange(); sheet = false; menuFor = name || ""; controlMode = mode; controlError = ""; loadCatalog() }
  function arrange(name) {
    if (desktopBlocked) return
    controlMode = ""; menuFor = ""; sheet = false
    editAgent = name || active || (agents.length ? agents[0].name : "")
    if (!editAgent) return
    arranging = true; focusPrimed = false; focusTimer.restart(); strip.forceActiveFocus()
    mutate(["arrange-keys", "on"])
  }
  function arrangeAction(action) {
    if (!arranging) { run(["arrange-keys", "off"]); return }
    var i = agents.findIndex(function(a) { return a.name === editAgent })
    if (action === "done") { dismissControls(); return }
    if (action === "activate") { var n = editAgent; dismissControls(); run(["show", n]); return }
    if (action === "select-left" || action === "select-right") {
      var next = i + (action === "select-left" ? -1 : 1)
      if (next >= 0 && next < agents.length) editAgent = agents[next].name
    } else if (action === "move-left" || action === "move-right") mutate(["move", editAgent, action === "move-left" ? "left" : "right"])
  }
  function mutate(args) { actionQueue = actionQueue.concat([args]); startAction() }
  function startAction() { if (actionProc.running || !actionQueue.length) return; var a = actionQueue[0]; actionQueue = actionQueue.slice(1); actionProc.command = [bin].concat(a); actionProc.running = true }
  function beginLogin(name, action) {
    if (desktopBlocked) return
    if (loginProc.running) return
    loginCancelled = false
    pendingLoginAction = action || ""
    loginAgent = name; loginResult = {state: "checking", name: name}; controlError = "Checking sign-in…"
    loginProc.command = [Quickshell.env("HOME") + "/.local/share/omarchy-agent-switcher/configure-signin", bin, name]
    loginProc.running = true
  }
  function loginAction(action) {
    if (action === "cancel") { loginCancelled = true; loginVisible = false; if (loginProc.running) loginProc.signal(15); return }
    if (!loginProc.running) { beginLogin(loginAgent, action); return }
    loginProc.write(action + "\n")
  }
  Process {
    id: catalogProc
    command: [root.bin, "agents", "--json"]
    onExited: { if (root.catalogDirty) { root.catalogDirty = false; Qt.callLater(root.loadCatalog) } }
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
      try { root.catalog = JSON.parse(text); root.hint = root.catalog.settings.show_hint; root.usageDisplay = root.catalog.settings.usage_display; if (!root.active) root.agents = root.catalog.enabled.map(function(n) { return {name:n,state:"stopped"} }); }
      catch (e) { root.controlError = "Cannot read installed agents." }
    } }
  }
  Process {
    id: actionProc
    stderr: StdioCollector { id: actionErrors; waitForEnd: true }
    onExited: (code) => {
      if (code !== 0) root.controlError = String(actionErrors.text).trim() || "The change could not be saved."
      root.loadCatalog()
      if (code === 0 && actionProc.command[1] === "disable") root.run(["toggle"])
      if (root.arranging && actionProc.command[1] !== "arrange-keys") root.run(["arrange-keys", "on"])
      Qt.callLater(root.startAction)
    }
  }
  Process {
    id: loginProc
    stdinEnabled: true
    stdout: SplitParser { onRead: (data) => {
      try {
        if (root.loginCancelled) return
        var r = JSON.parse(data)
        root.loginResult = r
        if (r.state === "added") { root.loginVisible = false; root.controlError = ""; root.loadCatalog(); root.run(["configure"]); }
        else if (r.state !== "verified") {
          root.loginVisible = true
          if (root.opened) root.run(["hide"])
          if (root.pendingLoginAction !== "") { var a=root.pendingLoginAction; root.pendingLoginAction=""; loginProc.write(a + "\n") }
        }
      } catch (e) { root.controlError = "Cannot read sign-in status." }
    } }
    onExited: (code) => { if (code !== 0 && root.loginVisible) root.loginResult = {name:root.loginAgent,state:"failed",message:"Sign-in stopped. Retry or cancel."} }
  }
  SigninWindow {
    visible: root.loginVisible && !root.desktopBlocked
    result: root.loginResult
    background: root.bg; foreground: root.fg; accent: root.accent
    onActionRequested: (action) => root.loginAction(action)
  }
  Timer { id: focusTimer; interval: 60; onTriggered: { root.focusPrimed = true; strip.forceActiveFocus() } }
  Component.onDestruction: { run(["arrange-keys", "off"]); if (loginProc.running) loginProc.signal(15) }
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
    run(["arrange-keys", "off"])
    run(["rules", "--reload"])
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
      if (root.arranging || root.controlMode !== "") {
        if (n === "workspace" || n === "workspacev2" || n === "focusedmon" || n === "activespecial") { root.dismissControls(); autohideTimer.restart() }
        return
      }
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
    function configure(mode: string, name: string): string { if (mode === "arrange") root.arrange(name); else if (["add", "settings", "tab"].indexOf(mode) >= 0) root.controls(mode, name); else return "unknown mode"; return "ok" }
    function arrangeAction(action: string): string { root.arrangeAction(action); return "ok" }
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
    visible: root.opened && (root.sheet || root.controlMode !== "" || root.arranging)
    screen: root.screenFor(root.monitorName)
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-agent-switcher-sheet"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: { root.hideSheet(); root.dismissControls() } }
  }

  PanelWindow {
    id: win
    visible: root.opened
    screen: root.screenFor(root.monitorName)
    anchors { top: true }
    // The cheat sheet sits above the strip, so the window grows upward.
    margins.top: root.edge === "top" ? root.stripTop : Math.max(0, root.stripTop - (sheetBox.visible ? sheetBox.height + 8 : 0) - (configCard.visible ? configCard.height + 8 : 0))
    implicitWidth: Math.max(strip.width + 2 * (sideControls.width + 10), configCard.visible ? configCard.width + 16 : 0, hintLine.visible ? hintMetrics.width + 16 : 0, sheetBox.visible ? sheetBox.width + 8 : 0)
    implicitHeight: (sheetBox.visible ? sheetBox.height + 8 : 0) + 44 + (configCard.visible ? configCard.height + 8 : (hintLine.visible ? 20 : 0))
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-agent-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    // Acquire keyboard focus only while configuring or arranging. Ordinary opening
    // keeps typing in the agent, with no layer-shell focus grab.
    WlrLayershell.keyboardFocus: root.arranging || root.controlMode !== "" ? (root.focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive) : WlrKeyboardFocus.None

    Rectangle {
      id: sheetBox
      visible: root.sheet
      anchors.top: root.edge === "top" ? (configCard.visible ? configCard.bottom : (hintLine.visible ? hintLine.bottom : strip.bottom)) : parent.top
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
      Text { id: sheetTitle; x: 14; y: 10; text: "Agent switcher shortcuts"; color: root.accent; font.family: Commons.Style.font.family; font.pixelSize: 12; font.weight: Font.DemiBold }
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
            font.family: Commons.Style.font.family; font.pixelSize: 11
            font.weight: index % 2 === 0 ? Font.DemiBold : Font.Normal
          }
        }
      }
    }

    Rectangle {
      id: strip
      anchors.top: root.edge !== "top" && configCard.visible ? configCard.bottom : (sheetBox.visible && root.edge !== "top") ? sheetBox.bottom : parent.top
      anchors.topMargin: root.edge !== "top" && (configCard.visible || sheetBox.visible) ? 8 : 0
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

      Keys.onLeftPressed: { if (root.arranging) root.arrangeAction("select-left"); else root.run(["prev"]) }
      Keys.onRightPressed: { if (root.arranging) root.arrangeAction("select-right"); else root.run(["next"]) }
      Keys.onTabPressed: (e) => { if (root.controlMode !== "") e.accepted = false; else root.run(["next"]) }
      Keys.onBacktabPressed: (e) => { if (root.controlMode !== "") e.accepted = false; else root.run(["prev"]) }
      Keys.onEscapePressed: { if (root.arranging || root.controlMode !== "") root.dismissControls(); else if (root.sheet) root.hideSheet(); else if (root.menuFor !== "") root.menuFor = ""; else root.run(["hide"]) }
      Keys.onReturnPressed: { if (root.arranging) root.arrangeAction("activate") }
      Keys.onPressed: (e) => { if (e.key === Qt.Key_Question || e.text === "?") { root.toggleSheet(); e.accepted = true } else if (root.controlMode === "" && !root.arranging && e.key >= Qt.Key_1 && e.key <= Qt.Key_9) root.run(["show", String(e.key - Qt.Key_1)]) }

      WheelHandler { onWheel: (e) => root.wheel(e.angleDelta.y) }

      Row {
        id: row
        anchors.centerIn: parent
        spacing: 4
        Text { visible: !root.agents.length; text: "No agents"; color: root.fg; font.family: Commons.Style.font.family; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
        Repeater {
          model: root.agents
          Rectangle {
            id: tab
            required property var modelData
            required property int index
            readonly property bool sel: modelData.name === root.active
            readonly property string st: modelData.state || "running"
            readonly property color ink: sel ? root.readableText(root.accent, root.themeText) : root.fg
            width: content.implicitWidth + 30
            height: 32
            radius: 16
            opacity: 1.0
            color: sel ? root.accent
                       : (ma.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, root.readableFillOpacity(root.bg, root.fg, root.accent, 0.22)) : "transparent")
            // keyboard focus ring on the active tab
            border.width: (root.arranging && root.editAgent === modelData.name) ? 2 : ((!sel && ma.containsMouse) ? 1 : 0)
            border.color: (root.arranging && root.editAgent === modelData.name) ? root.fg : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.6)
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
              opacity: root.readableFillOpacity(tab.sel ? root.accent : root.bg, tab.ink, root.usageColor(tab.usage), tab.sel ? 0.45 : 0.3)
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
                color: tab.ink
                font.family: Commons.Style.font.family
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
                color: tab.ink
                font.family: Commons.Style.font.family; font.pixelSize: 12
                TextMetrics { id: pctMetrics; font.family: Commons.Style.font.family; font.pixelSize: 12; text: "100%" }
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
                if (m.button === Qt.RightButton) root.controls("tab", tab.modelData.name)
                else if (m.button === Qt.MiddleButton) root.run(["close", tab.modelData.name])
                else if (root.arranging) root.editAgent = tab.modelData.name
                else { root.dismissControls(); root.run(["show", tab.modelData.name]) }
              }
            }
          }
        }

      }
    }

    // Reserve space without moving the centered tab pill when the actions appear.
    HoverHandler {
      id: stripHover
      parent: win.contentItem
      blocking: false
      readonly property bool overStrip: hovered && point.position.x >= strip.x - 5 && point.position.x <= strip.x + strip.width + sideControls.width + 11 && point.position.y >= strip.y - 5 && point.position.y <= strip.y + strip.height + 5
    }
    Row {
      id: sideControls
      anchors.left: strip.right; anchors.leftMargin: 6
      anchors.verticalCenter: strip.verticalCenter
      spacing: 6
      opacity: stripHover.overStrip ? 1 : 0
      enabled: stripHover.overStrip
      Behavior on opacity { NumberAnimation { duration: 100 } }
      HoverAction {
        glyph: "+"; label: "Add agent"
        background: root.bg; foreground: root.fg; accent: root.accent
        onHovered: (over) => root.buttonHint = over ? "Add agent" : ""
        onClicked: root.controls("add", "")
      }
      HoverAction {
        glyph: "\ue615"; label: "Settings"; ring: false // Same glyph as Omarchy's Setup/settings menu.
        background: root.bg; foreground: root.fg; accent: root.accent
        onHovered: (over) => root.buttonHint = over ? "Settings" : ""
        onClicked: root.controls("settings", "")
      }
    }

    // Hint line under the tabs (show_hint / omarchy-agents hint on|off); the right-click menu replaces it.
    Text {
      id: hintLine
      // Fixed size: the line's width comes from the default hint text (never from the hover text),
      // and it is always reserved, so hovering can't resize/re-centre the strip window.
      visible: (root.hint || root.arranging) && root.controlMode === ""
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
      text: root.arranging ? "←/→ select · Super+Shift+←/→ move · Enter open · Esc done" : (root.buttonHint !== "" ? root.buttonHint : root.hoverInfo !== "" ? root.hoverInfo : defaultText)
      color: root.fg
      font.family: Commons.Style.font.family; font.pixelSize: 10
      style: Text.Outline; styleColor: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.6)
    }

    ConfigureCard {
      id: configCard
      visible: root.controlMode !== ""
      mode: root.controlMode; agent: root.menuFor; catalog: root.catalog; error: root.controlError
      anchors.top: root.edge === "top" ? strip.bottom : parent.top; anchors.topMargin: root.edge === "top" ? 8 : 0; anchors.horizontalCenter: strip.horizontalCenter
      background: root.bg; foreground: root.fg; accent: root.accent
      onDismissed: root.dismissControls()
      onAddRequested: (name) => root.beginLogin(name)
      onArrangeRequested: (name) => root.arrange(name)
      onSettingRequested: (key, value) => root.mutate(["setting", key, value])
      onCommandRequested: (command, name) => {
        if (command === "left" || command === "right") root.mutate(["move", name, command])
        else { root.dismissControls(); root.mutate([command, name]) }
      }
    }
  }
}
