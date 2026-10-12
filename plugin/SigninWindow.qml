import QtQuick
import Quickshell
import qs.Commons as Commons

FloatingWindow {
  id: root
  property var result: ({state: "checking"})
  property color background: Commons.Color.background
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  signal actionRequested(string action)
  title: "Agent switcher sign-in: " + (result.name || "agent")
  implicitWidth: 440
  implicitHeight: body.implicitHeight + 32
  color: background
  onClosed: actionRequested("cancel")
  Column {
    id: body
    x: 16; y: 16; width: parent.width - 32; spacing: 12
    Text { width: parent.width; text: "Add " + (root.result.name || "agent"); color: root.foreground; font.family: Commons.Style.font.family; font.pixelSize: 16; font.bold: true }
    Text {
      width: parent.width; wrapMode: Text.WordWrap
      text: root.result.message || (root.result.state === "confirmation_needed" ? "This agent has no supported sign-in check. If you have already signed in, confirm below. Otherwise open the agent to sign in." : root.result.state === "signed_out" ? "This agent reports that it is signed out. Open it to sign in, then choose Check again." : "Checking sign-in…")
      color: root.foreground; font.family: Commons.Style.font.family; font.pixelSize: 13
    }
    Flow {
      width: parent.width; spacing: 8
      ControlButton { visible: root.result.state === "confirmation_needed"; text: "Already signed in"; background: root.background; foreground: root.foreground; accent: root.accent; onClicked: root.actionRequested("confirm") }
      ControlButton { visible: ["confirmation_needed", "signed_out", "failed"].indexOf(root.result.state) >= 0; text: root.result.state === "failed" ? "Retry" : root.result.state === "signed_out" ? "Sign in" : "Open agent"; background: root.background; foreground: root.foreground; accent: root.accent; onClicked: root.actionRequested("open") }
      ControlButton { visible: root.result.state === "awaiting_login" || root.result.state === "confirmation_needed" || root.result.state === "signed_out"; text: "Check again"; background: root.background; foreground: root.foreground; accent: root.accent; onClicked: root.actionRequested("check") }
      ControlButton { text: "Cancel"; background: root.background; foreground: root.foreground; accent: root.accent; onClicked: root.actionRequested("cancel") }
    }
  }
}
