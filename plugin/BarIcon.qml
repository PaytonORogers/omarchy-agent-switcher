import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Agents icon for the Omarchy bar: click opens the agent panel; the dot shows the most
// urgent agent status (approval > error > done > working). Styled like payton.chatbar.
BarWidget {
  id: root
  moduleName: "io.github.paytonorogers.agent-switcher"

  readonly property string oaBin: Quickshell.env("HOME") + "/.local/bin/omarchy-agents"
  property string topState: "idle"
  property var agents: []

  function stateColor(s) { return s === "approval" ? "#E3A23B" : s === "error" ? "#E5534B" : s === "done" ? "#57AB5A" : "#9B7BD4" }
  function label(s) { return s === "approval" ? "waiting for approval" : s === "error" ? "error" : s === "done" ? "done, waiting on you" : s === "working" ? "working" : "idle" }
  function parse(text) {
    try { var j = JSON.parse(String(text || "{}")); topState = j.top || "idle"; agents = j.agents || [] } catch (e) {}
  }

  implicitWidth: btn.implicitWidth
  implicitHeight: btn.implicitHeight

  Process { id: poll; command: [root.oaBin, "status", "--json"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.parse(text) } }
  Timer { interval: Math.max(500, root.setting("pollMs", 2000)); running: true; repeat: true; triggeredOnStart: true
    onTriggered: if (!poll.running) poll.running = true }
  Process { id: toggler; command: [root.oaBin, "toggle"] }

  BarIconButton {
    id: btn
    anchors.fill: parent
    bar: root.bar
    text: "\uee0d"
    tooltipText: "Agents" + root.agents.map(function (a) { return "\n" + a.name + ": " + root.label(a.state) }).join("")
    onPressed: { toggler.running = true }
  }
  Rectangle {
    id: dot
    visible: root.topState !== "idle"
    width: 6; height: 6; radius: 3
    color: root.stateColor(root.topState)
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.horizontalCenterOffset: 7
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: -6
    SequentialAnimation on opacity {
      running: root.topState === "working"; loops: Animation.Infinite
      NumberAnimation { to: 0.3; duration: 700 } NumberAnimation { to: 1; duration: 700 }
      onRunningChanged: if (!running) dot.opacity = 1
    }
  }
}
