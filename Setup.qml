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

  // KeyboardPanel declares `anchorItem` and `bar` as required properties: it
  // positions its card relative to the bar icon that opened it. Leaving them
  // unset does not error, it just warns and refuses to build the component -
  // so the panel silently never appears. Panel.qml supplies both on load.
  property Item anchorItem: null
  property QtObject bar: null

  // [{serial, label, model, inputs: ["0x0f", ...]}]
  property var monitors: []
  // [{id, label, host, inputs: {serial: code}}]
  property var computers: []
  property string deskLabel: ""

  function open() { detectProc.running = true }

  // KeyboardPanel.close() calls owner.close() if the owner has one, and
  // Bar.requestPopout() closes a displaced popup through closeForPopoutSwitch
  // or close. Without this function neither finds anything: the sheet vanishes
  // without emitting closed(), Panel.qml's Loader stays active, onLoaded never
  // re-fires, and "Set up this desk" is dead for the rest of the session.
  function close() { root.closed() }

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

  // Empty means "nothing to check", not the empty string: cmd_reachable
  // treats a missing host as advisory-only and always exits 0, and it does
  // that by testing for a JSON null, not for the empty string a blanked
  // TextField would otherwise write.
  function setHost(computerIndex, text) {
    var next = JSON.parse(JSON.stringify(computers))
    next[computerIndex].host = text === "" ? null : text
    computers = next
  }

  // Ids must be unique: the engine looks a computer up by id, and two matches
  // make it read two values for every field, which ends with a newline inside
  // the code sent to a monitor. So the counter is derived from the ids already
  // present rather than trusting its own default - a reopened desk starts the
  // counter at 2 again otherwise, and the second "+ Computer" of the session
  // mints an id that already exists.
  function nextFreeNumber() {
    var highest = 1
    for (var i = 0; i < computers.length; i++) {
      var match = /^computer(\d+)$/.exec(String(computers[i].id))
      if (match) highest = Math.max(highest, parseInt(match[1], 10))
    }
    return highest + 1
  }

  function addComputer() {
    var number = nextFreeNumber()
    var next = JSON.parse(JSON.stringify(computers))
    next.push({ id: "computer" + number,
                label: "Computer " + number,
                host: null, inputs: {} })
    computers = next
  }

  function save() {
    // onStarted clears stdinEnabled after writing, and a failed save
    // deliberately leaves the sheet open to retry. Without re-arming here the
    // retry's write() goes nowhere, the engine reads EOF, and it reports
    // "stdin is not valid JSON" forever - a wrong reason the user cannot act on.
    saveProc.stdinEnabled = true
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
    stderr: StdioCollector { id: saveStderr; waitForEnd: true }
    onStarted: { write(stdinText); stdinEnabled = false }
    // A failed save (a malformed payload, a disk that would not accept the
    // rename) must not close the sheet: closing unconditionally here would
    // discard the whole grid the person just filled in, with no way back
    // but to redo it. Close on success only; on failure, surface the
    // engine's own message and leave the grid exactly as it was.
    onExited: function(exitCode) {
      if (exitCode === 0) { root.closed(); return }
      notifyProc.command = ["notify-send", "Monitor Input", String(saveStderr.text || "").trim()]
      notifyProc.running = true
    }
  }

  Process { id: notifyProc }

  KeyboardPanel {
    id: sheet
    owner: root
    anchorItem: root.anchorItem
    bar: root.bar
    open: true
    // centerOnBar because this sheet is far wider than the bar icon it hangs
    // off; anchored to the icon it would sit half off-screen near an edge.
    centerOnBar: true
    // The surface gets keyboard focus, but Qt needs an active-focus item
    // inside it before any key handler fires. Without this Esc does nothing
    // and the first click is spent focusing a field.
    focusTarget: keyCatcher
    // fitted* clamps to the screen and adds the border+padding inset. The
    // hand-rolled arithmetic this replaces ran the card off the right edge
    // once enough computers were added, taking the Save button with it.
    contentWidth: sheet.fittedContentWidth(Style.space(220) + root.computers.length * Style.space(180))
    contentHeight: sheet.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      ColumnLayout {
        id: column
        anchors.fill: parent
        spacing: Style.space(8)

        PanelSectionHeader { text: "Which input is each computer plugged into?" }

        Text {
          Layout.fillWidth: true
          visible: root.monitors.filter(function(m) { return m.inputs.length === 0 }).length > 0
          wrapMode: Text.WordWrap
          text: "Some monitors here cannot be switched from software. They will keep "
                + "showing whatever they are on now."
          color: Color.urgent
          font.family: Style.font.family
        }

        GridLayout {
          columns: root.computers.length + 1
          columnSpacing: Style.space(12)
          rowSpacing: Style.space(8)

          Item { Layout.preferredWidth: Style.space(200) }

          Repeater {
            model: root.computers.length
            delegate: ColumnLayout {
              required property int index
              Layout.preferredWidth: Style.space(160)
              spacing: Style.space(2)

              TextField {
                Layout.fillWidth: true
                text: root.computers[index].label
                onTextChanged: root.setLabel(index, text)
              }

              TextField {
                Layout.fillWidth: true
                placeholderText: "Hostname to ping first (optional)"
                text: root.computers[index].host || ""
                onTextChanged: root.setHost(index, text)
              }
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
                visible: col > 0 && monitor && monitor.inputs.length > 0
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

              // A monitor that answers DDC but lists no input codes cannot be switched
              // from software at all. Saying so here is the whole of R16: the alternative
              // is an empty dropdown that looks like a bug in this plugin.
              Text {
                anchors.fill: parent
                visible: col > 0 && monitor && monitor.inputs.length === 0
                wrapMode: Text.WordWrap
                text: "No input switching. Check DDC/CI is enabled in this monitor's own menu."
                color: Qt.darker(Color.foreground, 1.55)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          Button { text: "+ Computer"; onClicked: root.addComputer() }
          Item { Layout.fillWidth: true }
          Button { text: "Cancel"; onClicked: root.close() }
          Button { text: "Save"; onClicked: root.save() }
        }
      }
    }
  }

  TryController {
    id: tryController
    engine: root.engine
    monitorCount: root.monitors.length
  }
}
