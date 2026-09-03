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

  // The bar's own foreground and font, so the sheet matches every other panel
  // on this theme. `bar` is injected after load, hence the guards.
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property string ff: bar ? bar.fontFamily : Style.font.family

  // [{serial, label, model, inputs: ["0x0f", ...]}]
  property var monitors: []
  // [{id, label, host, inputs: {serial: code}}]
  property var computers: []
  property string deskLabel: ""

  // Whether the card is showing. Open and close used to mean build and
  // destroy: Panel.qml deactivated the Loader on close, which took the whole
  // half-filled grid with it. One click outside and the work was gone. The
  // draft now outlives the card - hyprmoncfg has the same property for the
  // same reason, by keeping its editor state in a backend the panel queries
  // on open rather than in the panel itself.
  property bool sheetOpen: false

  function open() {
    // Already loaded: show what is there rather than re-detecting, which
    // would also overwrite whatever was typed.
    if (monitors.length > 0) { sheetOpen = true; return }
    detectProc.running = true
  }

  // KeyboardPanel.close() calls owner.close() if the owner has one, and
  // Bar.requestPopout() closes a displaced popup through closeForPopoutSwitch
  // or close. Without this function neither finds anything: the sheet vanishes
  // without emitting closed(), Panel.qml's Loader stays active, onLoaded never
  // re-fires, and "Set up this desk" is dead for the rest of the session.
  function close() { sheetOpen = false; root.closed() }

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

  // Removing the only computer would leave nothing to switch to and no way
  // to add one back with a sensible default, so the last column stays.
  function removeComputer(computerIndex) {
    if (computers.length <= 1) return
    if (tryController.column === computerIndex + 1) tryController.revert()
    var next = JSON.parse(JSON.stringify(computers))
    next.splice(computerIndex, 1)
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
          root.sheetOpen = true
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
        // Only now. Showing the card before detect and state have answered
        // meant it mapped nearly empty and then jumped to full size as the
        // rows arrived - the shift you see on open.
        root.sheetOpen = true
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
      notifyProc.command = ["notify-send", "Screen Push", String(saveStderr.text || "").trim()]
      notifyProc.running = true
    }
  }

  Process { id: notifyProc }

  KeyboardPanel {
    id: sheet
    owner: root
    anchorItem: root.anchorItem
    bar: root.bar
    open: root.sheetOpen
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
    contentWidth: sheet.fittedContentWidth(Style.space(260) + root.computers.length * Style.space(266))
    contentHeight: sheet.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      ColumnLayout {
        id: column
        anchors.fill: parent
        spacing: Style.space(12)

        // Same hero every first-party panel opens with: icon, title, and a
        // small-caps status line. Here the status is what this sheet is for.
        PanelHero {
          Layout.fillWidth: true
          foreground: root.fg
          fontFamily: root.ff
          title: "Screen Push"
          meta: (root.deskLabel !== "" ? root.deskLabel : "This desk").toUpperCase()
          detail: root.monitors.length + (root.monitors.length === 1 ? " screen" : " screens")
                  + " · " + root.computers.length + (root.computers.length === 1 ? " computer" : " computers")
          iconComponent: Component {
            Text {
              text: "\u{f04e1}"
              color: root.fg
              font.family: root.ff
              font.pixelSize: Style.font.display
            }
          }
        }

        Text {
          Layout.fillWidth: true
          visible: root.monitors.filter(function(m) { return m.inputs.length === 0 }).length > 0
          wrapMode: Text.WordWrap
          text: "Some screens here cannot be switched from software. They will keep "
                + "showing whatever they are on now."
          color: Color.urgent
          font.family: root.ff
          font.pixelSize: Style.font.bodySmall
        }

        PanelSeparator { Layout.fillWidth: true; foreground: root.fg }
        PanelSectionHeader { text: "COMPUTERS"; foreground: root.fg; fontFamily: root.ff }

        // Column widths, shared by the header row and every monitor row so
        // the grid lines up without a GridLayout's index arithmetic.
        readonly property int gutterWidth: Style.space(220)
        readonly property int computerWidth: Style.space(250)
        readonly property int columnGap: Style.space(16)

        // Computer columns: a name and an optional hostname, labelled, so an
        // editable field no longer masquerades as a column header.
        RowLayout {
          spacing: column.columnGap
          Item { Layout.preferredWidth: column.gutterWidth; Layout.minimumWidth: column.gutterWidth }

          Repeater {
            model: root.computers.length
            delegate: GridLayout {
              required property int index
              Layout.preferredWidth: column.computerWidth
              Layout.minimumWidth: column.computerWidth
              columns: 2
              columnSpacing: Style.space(8)
              rowSpacing: Style.space(4)

              Text {
                text: "Name"
                Layout.preferredWidth: Style.space(34)
                horizontalAlignment: Text.AlignRight
                color: root.dim
                font.family: root.ff
                font.pixelSize: Style.font.caption
              }
              // Seeded once rather than bound: a `text:` binding on a model the
              // handler writes back to is a loop. onTextEdited fires only for
              // real typing, so a programmatic reseed cannot re-enter it.
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(6)
                TextField {
                  Layout.fillWidth: true
                  Component.onCompleted: text = root.computers[index].label
                  onTextEdited: root.setLabel(index, text)
                }
                PanelActionButton {
                  iconText: "\u{f0156}"
                  tooltipText: "Remove this computer"
                  foreground: root.fg
                  fontFamily: root.ff
                  enabled: root.computers.length > 1
                  onClicked: root.removeComputer(index)
                }
              }

              Text {
                text: "Host"
                Layout.preferredWidth: Style.space(34)
                horizontalAlignment: Text.AlignRight
                color: root.dim
                font.family: root.ff
                font.pixelSize: Style.font.caption
              }
              TextField {
                Layout.fillWidth: true
                placeholderText: "optional"
                Component.onCompleted: text = root.computers[index].host || ""
                onTextEdited: root.setHost(index, text)
              }
            }
          }
        }

        PanelSeparator { Layout.fillWidth: true; foreground: root.fg }

        RowLayout {
          Layout.fillWidth: true
          PanelSectionHeader { text: "SCREENS"; foreground: root.fg; fontFamily: root.ff }
          Item { Layout.fillWidth: true }
          Text {
            text: "\u{f040a}  switches the screen now, so you can check the cable"
            color: root.dim
            font.family: root.ff
            font.pixelSize: Style.font.caption
          }
        }

        // One row per screen, separated by a hairline so two screens read as
        // two things. The Try button sits on the dropdown's line rather than
        // under it, so each cell is one line high.
        Repeater {
          model: root.monitors.length
          delegate: ColumnLayout {
            id: monitorRow
            required property int index
            readonly property var monitor: root.monitors[index]
            Layout.fillWidth: true
            spacing: Style.space(8)

            RowLayout {
              spacing: column.columnGap

              ColumnLayout {
                Layout.preferredWidth: column.gutterWidth
                Layout.minimumWidth: column.gutterWidth
                Layout.alignment: Qt.AlignVCenter
                spacing: 0
                Text {
                  text: monitorRow.monitor ? monitorRow.monitor.label : ""
                  color: root.fg
                  font.family: root.ff
                  font.pixelSize: Style.font.subtitle
                }
                Text {
                  text: monitorRow.monitor ? monitorRow.monitor.model : ""
                  color: root.dim
                  font.family: root.ff
                  font.pixelSize: Style.font.caption
                }
              }

              Repeater {
                model: root.computers.length
                delegate: Item {
                  id: cell
                  required property int index
                  readonly property int col: index + 1
                  readonly property var monitor: monitorRow.monitor
                  readonly property bool switchable: monitor && monitor.inputs.length > 0
                  readonly property bool trying: tryController.serial === (monitor ? monitor.serial : "")
                                                 && tryController.column === col
                  Layout.preferredWidth: column.computerWidth
                  Layout.minimumWidth: column.computerWidth
                  implicitHeight: switchable ? cellRow.implicitHeight : noSwitch.implicitHeight

                  RowLayout {
                    id: cellRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    visible: cell.switchable
                    spacing: Style.space(6)

                    Dropdown {
                      Layout.fillWidth: true
                      showLabel: false
                      options: cell.monitor ? root.optionsFor(cell.monitor.serial) : []
                      value: cell.monitor ? root.cellValue(cell.col - 1, cell.monitor.serial) : ""
                      onChanged: function(v) { if (cell.monitor) root.setCell(cell.col - 1, cell.monitor.serial, v) }
                    }

                    PanelActionButton {
                      iconText: cell.trying ? "\u{f054c}" : "\u{f040a}"
                      tooltipText: cell.trying ? "Bring it back" : "Try it now"
                      foreground: cell.trying ? Color.accent : root.fg
                      fontFamily: root.ff
                      enabled: cell.monitor && root.cellValue(cell.col - 1, cell.monitor.serial) !== ""
                      onClicked: tryController.toggle(cell.monitor.serial, cell.col,
                                                      root.cellValue(cell.col - 1, cell.monitor.serial))
                    }
                  }

                  // A monitor that answers DDC but lists no input codes cannot be
                  // switched from software. Saying so is the whole of R16: the
                  // alternative is an empty dropdown that looks like a bug here.
                  Text {
                    id: noSwitch
                    anchors.left: parent.left
                    anchors.right: parent.right
                    visible: !cell.switchable
                    wrapMode: Text.WordWrap
                    text: "No input switching. Check DDC/CI is enabled in this screen's own menu."
                    color: root.dim
                    font.family: root.ff
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }

            PanelSeparator { Layout.fillWidth: true; foreground: root.fg }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)
          Button {
            iconText: "\u{f0415}"
            text: "Add computer"
            foreground: root.fg
            fontFamily: root.ff
            onClicked: root.addComputer()
          }
          Item { Layout.fillWidth: true }
          Button { text: "Cancel"; foreground: root.fg; fontFamily: root.ff; onClicked: root.close() }
          Button { text: "Save"; bordered: true; foreground: root.fg; fontFamily: root.ff; onClicked: root.save() }
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
