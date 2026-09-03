import QtQuick
import QtQuick.Controls
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

  // After Cancel or Save the next open starts from what is saved; after a
  // click outside, the draft survives.
  property bool reloadOnOpen: false
  property bool detecting: false
  property bool saving: false
  property string sheetError: ""
  property string noScreensHint: ""

  function open() {
    sheetError = ""
    if (monitors.length > 0 && !reloadOnOpen) { sheetOpen = true; return }
    detect()
  }

  function detect() {
    reloadOnOpen = false
    detecting = true
    noScreensHint = ""
    sheetOpen = true
    detectProc.running = true
  }

  function cancel() { reloadOnOpen = true; close() }

  // KeyboardPanel.close() calls owner.close() if the owner has one, and
  // Bar.requestPopout() closes a displaced popup through closeForPopoutSwitch
  // or close. Without this function neither finds anything: the sheet vanishes
  // without emitting closed(), Panel.qml's Loader stays active, onLoaded never
  // re-fires, and "Set up this desk" is dead for the rest of the session.
  function close() {
    // A screen left on a tried input with the sheet gone would be a screen
    // showing another computer with no Bring it back in sight.
    if (tryController.trying) tryController.revert()
    sheetOpen = false
    root.closed()
  }

  // Every computer needs a name; the menu row is the name.
  readonly property string validationError: {
    for (var i = 0; i < computers.length; i++) {
      if (String(computers[i].label || "").trim() === "") return "Give every computer a name."
    }
    return ""
  }
  readonly property bool canSave: !saving && !detecting && monitors.length > 0 && validationError === ""

  // Human names for the codes the hardware reports, so a cell reads
  // "HDMI 1" rather than "0x11". Anything unrecognised falls through as
  // the raw code rather than being hidden, because a monitor with an
  // unusual input still needs to be selectable.
  function monitorLabelFor(serial) {
    for (var i = 0; i < monitors.length; i++) if (monitors[i].serial === serial) return monitors[i].label
    return "Screen"
  }

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
    if (tryController.computerId === computers[computerIndex].id) tryController.revert()
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
    if (!canSave) return
    saving = true
    sheetError = ""
    // onStarted clears stdinEnabled after writing, and a failed save
    // deliberately leaves the sheet open to retry. Without re-arming here the
    // retry's write() goes nowhere, the engine reads EOF, and it reports
    // "stdin is not valid JSON" forever - a wrong reason the user cannot act on.
    saveProc.stdinEnabled = true
    var payload = {
      label: deskLabel === "" ? "This desk" : deskLabel,
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
        var found = [], parsedDetect = {}
        try { parsedDetect = JSON.parse(String(text || "")); found = parsedDetect.monitors || [] } catch (e) { found = [] }
        // Left-to-right names are a guess the person can correct; ddcutil
        // order is not physical order. Two screens are Left and Right, not
        // Left and Middle - that read as a lost third screen.
        var positions = found.length === 2 ? ["Left screen", "Right screen"]
                      : found.length === 3 ? ["Left screen", "Middle screen", "Right screen"]
                      : []
        for (var i = 0; i < found.length; i++) {
          found[i].label = positions[i] !== undefined ? positions[i] : ("Screen " + (i + 1))
          found[i].model = found[i].model || ""
        }
        root.monitors = found
        root.noScreensHint = found.length === 0 ? String(parsedDetect.hint || "No screens answered.") : ""
        if (found.length === 0) { root.detecting = false; return }
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
          root.detecting = false
          root.sheetOpen = true
          return
        }

        // First run on this desk. The machine in use can answer for itself:
        // whatever every monitor is showing right now IS this computer, so
        // that column is filled in rather than asked about (PRD R8).
        var mine = { id: "this", label: "This computer", host: null, inputs: {} }
        var live = parsed.live || {}
        for (var serial in live) mine.inputs[serial] = live[serial]
        root.computers = [mine]
        root.addComputer()
        root.detecting = false
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
      root.saving = false
      if (exitCode === 0) { root.reloadOnOpen = true; root.close(); return }
      root.sheetError = String(saveStderr.text || "").trim()
    }
  }

  Process { id: notifyProc }

  KeyboardPanel {
    id: sheet
    owner: root
    anchorItem: root.anchorItem
    bar: root.bar
    open: root.sheetOpen
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: sheet.fittedContentWidth(Style.space(460))
    contentHeight: sheet.fittedContentHeight(column.implicitHeight, Style.space(760))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      // Taller desks scroll inside the card rather than running off it.
      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: column
        width: flick.width
        spacing: Style.space(14)

        PanelHero {
          foreground: root.fg
          fontFamily: root.ff
          title: "Screen Push"
          meta: root.detecting ? "LOOKING FOR SCREENS…"
              : tryController.trying
                ? (root.monitorLabelFor(tryController.serial) + " IS ON " + root.inputLabel(tryController.code)
                   + (tryController.remaining > 0 ? " · BACK IN " + tryController.remaining + " S" : " · PRESS AGAIN TO BRING IT BACK")).toUpperCase()
              : ("THIS DESK · " + root.monitors.length + (root.monitors.length === 1 ? " SCREEN · " : " SCREENS · ")
                 + root.computers.length + (root.computers.length === 1 ? " COMPUTER" : " COMPUTERS"))
          iconComponent: Component {
            Text { text: "\u{f04e1}"; color: root.fg; font.family: root.ff; font.pixelSize: Style.font.display }
          }
          trailingControl: Component {
            PanelActionButton {
              iconText: "\u{f0450}"
              tooltipText: "Look for screens again"
              foreground: root.fg
              fontFamily: root.ff
              enabled: !root.detecting
              onClicked: root.detect()
            }
          }
        }

        // Nothing answered: say why, and stop there.
        Text {
          visible: !root.detecting && root.monitors.length === 0
          width: parent.width
          wrapMode: Text.WordWrap
          text: root.noScreensHint
          color: Color.urgent
          font.family: root.ff
          font.pixelSize: Style.font.bodySmall
        }

        PanelSeparator { visible: root.monitors.length > 0; foreground: root.fg }

        // ---------- Computers ----------
        Column {
          visible: root.monitors.length > 0
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader { text: "COMPUTERS"; foreground: root.fg; fontFamily: root.ff }

          Repeater {
            model: root.computers.length
            delegate: Column {
              required property int index
              width: parent.width
              spacing: Style.spacing.labelGap

              Row {
                width: parent.width
                spacing: Style.space(6)
                TextField {
                  width: parent.width - removeBtn.width - Style.space(6)
                  verticalPadding: Style.spacing.controlPaddingY
                  placeholderText: "Name"
                  Component.onCompleted: text = root.computers[index].label
                  onTextEdited: root.setLabel(index, text)
                }
                PanelActionButton {
                  id: removeBtn
                  iconText: "\u{f0156}"
                  tooltipText: "Remove"
                  foreground: root.fg
                  fontFamily: root.ff
                  enabled: root.computers.length > 1
                  anchors.verticalCenter: parent.verticalCenter
                  onClicked: root.removeComputer(index)
                }
              }
              TextField {
                width: parent.width
                verticalPadding: Style.spacing.controlPaddingY
                placeholderText: "Hostname or IP, optional - pinged before sending"
                Component.onCompleted: text = root.computers[index].host || ""
                onTextEdited: root.setHost(index, text)
              }
            }
          }

          Button {
            iconText: "\u{f0415}"
            text: "Add computer"
            bordered: true
            fontSize: Style.font.caption
            foreground: root.fg
            fontFamily: root.ff
            onClicked: root.addComputer()
          }
        }

        PanelSeparator { visible: root.monitors.length > 0; foreground: root.fg }

        // ---------- Screens ----------
        Column {
          visible: root.monitors.length > 0
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader { text: "SCREENS"; foreground: root.fg; fontFamily: root.ff }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "For each screen, pick the input each computer is plugged into. Try it switches the screen right now, and brings it back when pressed again."
            color: Qt.darker(root.fg, 1.5)
            font.family: root.ff
            font.pixelSize: Style.font.bodySmall
          }

          Repeater {
            model: root.monitors.length
            delegate: Column {
              id: screenBlock
              required property int index
              readonly property var monitor: root.monitors[index]
              readonly property bool switchable: monitor && monitor.inputs.length > 0
              width: parent.width
              spacing: Style.space(8)

              Column {
                spacing: 0
                Text {
                  text: screenBlock.monitor ? screenBlock.monitor.label : ""
                  color: root.fg
                  font.family: root.ff
                  font.pixelSize: Style.font.subtitle
                }
                Text {
                  text: screenBlock.monitor ? screenBlock.monitor.model : ""
                  color: Qt.darker(root.fg, 1.4)
                  font.family: root.ff
                  font.pixelSize: Style.font.caption
                }
              }

              Text {
                visible: !screenBlock.switchable
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Can't switch this screen. Turn on DDC/CI in its own menu, then look for screens again."
                color: Qt.darker(root.fg, 1.4)
                font.family: root.ff
                font.pixelSize: Style.font.bodySmall
              }

              Repeater {
                model: screenBlock.switchable ? root.computers.length : 0
                delegate: Row {
                  id: cell
                  required property int index
                  readonly property var computer: root.computers[index]
                  readonly property string serial: screenBlock.monitor ? screenBlock.monitor.serial : ""
                  readonly property string value: root.cellValue(index, serial)
                  readonly property bool trying: tryController.isTrying(serial, computer ? computer.id : "")
                  width: parent.width
                  spacing: Style.space(8)

                  Dropdown {
                    width: parent.width - tryBtn.width - Style.space(8)
                    label: cell.computer ? cell.computer.label : ""
                    foreground: root.fg
                    fontFamily: root.ff
                    options: root.optionsFor(cell.serial)
                    value: cell.value
                    onChanged: function(v) { root.setCell(cell.index, cell.serial, v) }
                  }
                  PanelActionButton {
                    id: tryBtn
                    iconText: cell.trying ? "\u{f054c}" : "\u{f040a}"
                    tooltipText: cell.trying ? "Bring it back" : "Try it"
                    foreground: cell.trying ? Color.accent : root.fg
                    fontFamily: root.ff
                    enabled: cell.value !== "" && !tryController.busy
                    anchors.bottom: parent.bottom
                    onClicked: tryController.toggle(cell.serial, cell.computer.id, cell.value)
                  }
                }
              }

              PanelSeparator { visible: screenBlock.index < root.monitors.length - 1; foreground: root.fg }
            }
          }
        }

        // Problems, in one place, above the buttons that caused them.
        Text {
          visible: text !== ""
          width: parent.width
          wrapMode: Text.WordWrap
          text: root.sheetError !== "" ? root.sheetError
              : tryController.error !== "" ? tryController.error
              : root.validationError
          color: Color.urgent
          font.family: root.ff
          font.pixelSize: Style.font.bodySmall
        }

        Row {
          visible: root.monitors.length > 0
          anchors.right: parent.right
          spacing: Style.space(8)
          Button { text: "Cancel"; bordered: true; fontSize: Style.font.caption; foreground: root.fg; fontFamily: root.ff; onClicked: root.cancel() }
          Button {
            text: root.saving ? "Saving…" : "Save"
            bordered: true
            active: true
            fontSize: Style.font.caption
            foreground: root.fg
            fontFamily: root.ff
            opacity: root.canSave ? 1 : 0.45
            onClicked: root.save()
          }
        }
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
