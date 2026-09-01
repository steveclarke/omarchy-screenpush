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

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function refresh() { stateProc.running = true }

  function sendTo(computerId) {
    busy = true
    switchProc.command = [root.engine, "switch", computerId]
    switchProc.running = true
  }

  onOpenedChanged: if (opened) refresh()
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
          model: root.deskState.computers
          delegate: Button {
            required property var modelData
            Layout.fillWidth: true
            enabled: !root.busy
            text: (modelData.id === root.deskState.current ? "●  " : "○  ") + modelData.label
            onClicked: root.sendTo(modelData.id)
          }
        }

        PanelSeparator { visible: root.deskState.known }

        Button {
          Layout.fillWidth: true
          text: root.deskState.known ? "Set up this desk..." : "Set up this desk"
          onClicked: { root.close(); setupLoader.active = true }
        }
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
