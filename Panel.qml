import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Engine.js" as Engine

Panel {
  id: root
  moduleName: "io.github.steveclarke.monitor-input"
  ipcTarget: "monitor-input"
  manageIpc: false

  readonly property string engine: Engine.enginePath(Qt.resolvedUrl)
  property var deskState: Engine.parseState("")
  property bool busy: false
  property string pendingComputer: ""
  property bool confirmOpen: false

  function refresh() { stateProc.running = true }

  // Ask first, then act. reachable exits 0 for a computer with no host
  // recorded, so a desk that never named hostnames never sees a dialog.
  //
  // `busy` goes up HERE, not in reallySendTo. The rows are disabled by !busy,
  // and without this they stay live while the reachability check is in flight:
  // a second click would overwrite pendingComputer and the in-flight command,
  // so an exit(0) from the newly-clicked reachable machine would suppress the
  // dialog that the FIRST, unreachable, machine had earned - sending the whole
  // desk to a machine that is not answering, with no confirmation. That is
  // precisely the outcome this confirmation exists to prevent.
  function sendTo(computerId) {
    busy = true
    pendingComputer = computerId
    reachProc.command = [root.engine, "reachable", computerId]
    reachProc.running = true
  }

  function reallySendTo(computerId) {
    busy = true
    switchProc.command = [root.engine, "switch", computerId]
    switchProc.running = true
  }

  function labelFor(computerId) {
    for (var i = 0; i < deskState.computers.length; i++) {
      if (deskState.computers[i].id === computerId) return deskState.computers[i].label
    }
    return computerId
  }

  function sendMonitorTo(serial, computerId) {
    busy = true
    switchProc.command = [root.engine, "switch", computerId, "--monitor", serial]
    switchProc.running = true
  }

  // "" is the computer list; a serial is that monitor's computer list.
  property string submenuSerial: ""

  // Every piece of transient state resets here, not just the submenu. A
  // confirmation left open when the popup is dismissed would otherwise still be
  // open on the next summon, presenting a stale target the person has since
  // stopped caring about - and the dialog names a machine, so a half-remembered
  // "Send anyway" would go somewhere they did not just choose.
  onOpenedChanged: {
    if (opened) {
      submenuSerial = ""
      confirmOpen = false
      pendingComputer = ""
      refresh()
    }
  }
  Component.onCompleted: refresh()

  Process {
    id: stateProc
    command: [root.engine, "state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.deskState = Engine.parseState(String(text || ""))
    }
  }

  Process {
    id: reachProc
    onExited: function(exitCode) {
      if (exitCode === 0) { root.reallySendTo(root.pendingComputer); return }
      root.confirmOpen = true
    }
  }

  Process {
    id: switchProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: {
      if (running) return
      root.busy = false
      root.close()
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function send(id: string): string { root.sendTo(id); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        OpticalGlyph {
          anchors.centerIn: parent
          text: "󰝹"
          fontFamily: Style.font.family
          fontSize: Style.font.icon
          color: root.barForeground
        }
      }
    }
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(420))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      ColumnLayout {
        id: column
        anchors.fill: parent
        spacing: Style.space(4)

        PanelSectionHeader { text: "Send my screens to" }

        Repeater {
          model: root.submenuSerial === "" ? root.deskState.computers : []
          delegate: Button {
            required property var modelData
            Layout.fillWidth: true
            enabled: !root.busy
            text: (modelData.id === root.deskState.current ? "●  " : "○  ") + modelData.label
            onClicked: root.sendTo(modelData.id)
          }
        }

        // Monitor picker: which screen, then which computer for that screen.
        Repeater {
          model: root.submenuSerial === "monitors" ? root.deskState.monitors : []
          delegate: Button {
            required property var modelData
            Layout.fillWidth: true
            text: modelData.label + "   ›"
            onClicked: root.submenuSerial = modelData.serial
          }
        }

        Repeater {
          model: (root.submenuSerial !== "" && root.submenuSerial !== "monitors")
                 ? root.deskState.computers : []
          delegate: Button {
            required property var modelData
            Layout.fillWidth: true
            enabled: !root.busy
            text: modelData.label
            onClicked: root.sendMonitorTo(root.submenuSerial, modelData.id)
          }
        }

        PanelSeparator {}

        Button {
          Layout.fillWidth: true
          visible: root.submenuSerial === "" && root.deskState.monitors.length > 1
          text: "Just one screen   ›"
          onClicked: root.submenuSerial = "monitors"
        }

        Button {
          Layout.fillWidth: true
          visible: root.submenuSerial !== ""
          text: "‹   Back"
          onClicked: root.submenuSerial = (root.submenuSerial === "monitors" ? "" : "monitors")
        }

        Button {
          Layout.fillWidth: true
          text: root.deskState.known ? "Set up this desk..." : "Set up this desk"
          onClicked: { root.close(); setupLoader.active = true }
        }
      }

      ConfirmDialog {
        id: confirm
        anchors.fill: parent
        z: 10
        opened: root.confirmOpen
        message: root.labelFor(root.pendingComputer)
                 + " is not responding. Send the screens anyway?"
        confirmText: "Send anyway"
        cancelText: "Cancel"
        onConfirmed: { root.confirmOpen = false; root.reallySendTo(root.pendingComputer) }
        // Cancelling is the one path that ends without a switchProc run, so it is
        // the one path that has to hand `busy` back itself. Miss it and the menu
        // stays disabled until the panel is reopened.
        onCanceled: { root.confirmOpen = false; root.pendingComputer = ""; root.busy = false }
      }
    }
  }

  Loader {
    id: setupLoader
    active: false
    source: Qt.resolvedUrl("Setup.qml")
    onLoaded: {
      item.engine = root.engine
      item.closed.connect(function() { setupLoader.active = false; root.refresh() })
      item.open()
    }
  }
}
