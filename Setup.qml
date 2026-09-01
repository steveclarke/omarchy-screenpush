import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Item {
  id: root
  anchors.fill: parent

  property string engine: ""
  signal closed()

  // [{serial, label, model, inputs: ["0x0f", ...]}]
  property var monitors: []
  // [{id, label, host, inputs: {serial: code}}]
  property var computers: []
  property string deskLabel: ""
  property int nextComputerNumber: 2

  function open() { detectProc.running = true }

  // Human names for the codes the hardware reports, so a cell reads
  // "HDMI 1" rather than "0x11". Anything unrecognised falls through as
  // the raw code rather than being hidden, because a monitor with an
  // unusual input still needs to be selectable.
  readonly property var inputNames: ({
    "0x01": "VGA 1", "0x03": "DVI 1", "0x04": "DVI 2",
    "0x0f": "DisplayPort 1", "0x10": "DisplayPort 2",
    "0x11": "HDMI 1", "0x12": "HDMI 2",
    "0x1b": "USB-C"
  })

  function inputLabel(code) {
    return inputNames[code] !== undefined ? inputNames[code] : code
  }

  function optionsFor(serial) {
    for (var i = 0; i < monitors.length; i++) {
      if (monitors[i].serial !== serial) continue
      var out = []
      for (var j = 0; j < monitors[i].inputs.length; j++) {
        out.push({ label: inputLabel(monitors[i].inputs[j]), value: monitors[i].inputs[j] })
      }
      return out
    }
    return []
  }

  function cellValue(computerIndex, serial) {
    var c = computers[computerIndex]
    return c && c.inputs && c.inputs[serial] !== undefined ? c.inputs[serial] : ""
  }

  function setCell(computerIndex, serial, code) {
    var next = JSON.parse(JSON.stringify(computers))
    next[computerIndex].inputs[serial] = code
    computers = next
  }

  function setLabel(computerIndex, text) {
    var next = JSON.parse(JSON.stringify(computers))
    next[computerIndex].label = text
    computers = next
  }

  function addComputer() {
    var next = JSON.parse(JSON.stringify(computers))
    next.push({ id: "computer" + nextComputerNumber,
                label: "Computer " + nextComputerNumber,
                host: null, inputs: {} })
    nextComputerNumber += 1
    computers = next
  }

  function save() {
    var payload = {
      label: deskLabel === "" ? "My desk" : deskLabel,
      monitors: monitors.map(function(m) {
        return { serial: m.serial, label: m.label, model: m.model }
      }),
      computers: computers
    }
    saveProc.stdinText = JSON.stringify(payload)
    saveProc.running = true
  }

  Process {
    id: detectProc
    command: [root.engine, "detect"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var found = []
        try { found = JSON.parse(String(text || "")).monitors || [] } catch (e) { found = [] }
        // Left-to-right names are a guess the person can correct; ddcutil
        // order is not physical order. A blank name would be worse: the
        // grid would be rows of anonymous serials.
        var positions = ["Left screen", "Middle screen", "Right screen",
                         "Fourth screen", "Fifth screen"]
        for (var i = 0; i < found.length; i++) {
          found[i].label = positions[i] !== undefined ? positions[i] : ("Screen " + (i + 1))
          found[i].model = found[i].model || ""
        }
        root.monitors = found
        stateProc.running = true
      }
    }
  }

  Process {
    id: stateProc
    command: [root.engine, "state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = {}
        try { parsed = JSON.parse(String(text || "")) } catch (e) { parsed = {} }

        if (parsed.known && parsed.computers && parsed.computers.length > 0) {
          root.computers = parsed.computers
          root.deskLabel = parsed.label || ""
          if (parsed.monitors && parsed.monitors.length === root.monitors.length) {
            root.monitors = root.monitors.map(function(m) {
              for (var i = 0; i < parsed.monitors.length; i++) {
                if (parsed.monitors[i].serial === m.serial) m.label = parsed.monitors[i].label
              }
              return m
            })
          }
          return
        }

        // First run on this desk. The machine in use can answer for itself:
        // whatever every monitor is showing right now IS this computer, so
        // that column is filled in rather than asked about (PRD R8).
        var mine = { id: "this", label: "This machine", host: null, inputs: {} }
        var live = parsed.live || {}
        for (var serial in live) mine.inputs[serial] = live[serial]
        root.computers = [mine]
        root.addComputer()
      }
    }
  }

  Process {
    id: saveProc
    command: [root.engine, "save-desk"]
    stdinEnabled: true
    property string stdinText: ""
    onStarted: { write(stdinText); stdinEnabled = false }
    onRunningChanged: if (!running) root.closed()
  }

  KeyboardPanel {
    id: sheet
    owner: root
    open: true
    contentWidth: Style.space(220) + root.computers.length * Style.space(180)
    contentHeight: Style.space(140) + root.monitors.length * Style.space(64)

    ColumnLayout {
      anchors.fill: parent
      spacing: Style.space(8)

      PanelSectionHeader { text: "Which input is each computer plugged into?" }

      GridLayout {
        columns: root.computers.length + 1
        columnSpacing: Style.space(12)
        rowSpacing: Style.space(8)

        Item { Layout.preferredWidth: Style.space(200) }

        Repeater {
          model: root.computers.length
          delegate: TextField {
            required property int index
            Layout.preferredWidth: Style.space(160)
            text: root.computers[index].label
            onTextChanged: root.setLabel(index, text)
          }
        }

        Repeater {
          model: root.monitors.length * (root.computers.length + 1)
          delegate: Item {
            required property int index
            readonly property int columns: root.computers.length + 1
            readonly property int row: Math.floor(index / columns)
            readonly property int col: index % columns
            readonly property var monitor: root.monitors[row]

            Layout.preferredWidth: col === 0 ? Style.space(200) : Style.space(160)
            Layout.preferredHeight: Style.space(56)

            ColumnLayout {
              anchors.fill: parent
              visible: col === 0
              spacing: 0
              Text {
                text: monitor ? monitor.label : ""
                color: Color.foreground
                font.family: Style.font.family
              }
              Text {
                text: monitor ? monitor.model : ""
                color: Qt.darker(Color.foreground, 1.55)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            ColumnLayout {
              anchors.fill: parent
              visible: col > 0
              spacing: Style.space(2)

              Dropdown {
                Layout.fillWidth: true
                showLabel: false
                options: monitor ? root.optionsFor(monitor.serial) : []
                value: monitor ? root.cellValue(col - 1, monitor.serial) : ""
                onChanged: function(v) { if (monitor) root.setCell(col - 1, monitor.serial, v) }
              }

              Button {
                Layout.fillWidth: true
                text: tryController.serial === (monitor ? monitor.serial : "")
                      && tryController.column === col
                      ? "Bring it back" : "Try it"
                enabled: monitor && root.cellValue(col - 1, monitor.serial) !== ""
                onClicked: tryController.toggle(monitor.serial, col,
                                                root.cellValue(col - 1, monitor.serial))
              }
            }
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        Button { text: "+ Computer"; onClicked: root.addComputer() }
        Item { Layout.fillWidth: true }
        Button { text: "Cancel"; onClicked: root.closed() }
        Button { text: "Save"; onClicked: root.save() }
      }
    }
  }

  TryController {
    id: tryController
    engine: root.engine
    monitorCount: root.monitors.length
  }
}
