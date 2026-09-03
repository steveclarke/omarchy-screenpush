import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Engine.js" as Engine

Panel {
  id: root
  moduleName: "io.github.steveclarke.screenpush"
  ipcTarget: "screenpush"
  manageIpc: false

  // The bar sizes a widget from its root's implicit size; without these the
  // slot is 0x0 and the widget is invisible and unclickable.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string engine: Engine.enginePath(Qt.resolvedUrl)
  readonly property string ff: bar ? bar.fontFamily : Style.font.family
  property var deskState: Engine.parseState("")
  property bool busy: false
  property string pendingComputer: ""
  property string pendingSerial: ""
  property bool confirmOpen: false
  readonly property bool loading: stateProc.running

  // Which row is doing something, and what it says while it does it. A
  // switch takes several seconds; the row it was asked on reports progress
  // and, on refusal, the engine's own sentence, the way the network panel
  // reports on the station row rather than in a toast.
  property string statusKey: ""
  property string statusText: ""
  property bool statusUrgent: false

  // "" is the computer list; "monitors" the screen picker; a serial that
  // screen's computer list.
  property string submenuSerial: ""

  // Keyboard cursor over the visible rows, as every first-party panel.
  property bool cursorActive: false
  property int selectedIndex: 0

  function refresh() { stateProc.running = true }

  // Ui/Panel has no broadcast(); this is Ui/BarWidget.qml:29-35. One bar
  // surface exists per monitor, so a process exit reaches one instance and
  // the others keep stale state until reopened. Relay refreshes only; never
  // a side effect, and never from inside refresh().
  function broadcast(method) {
    var items = bar && typeof bar.moduleWidgets === "function"
      ? bar.moduleWidgets(moduleName) : [root]
    for (var i = 0; i < items.length; i++) {
      if (items[i] && typeof items[i][method] === "function") items[i][method]()
    }
  }

  function labelFor(computerId) {
    for (var i = 0; i < deskState.computers.length; i++) {
      if (deskState.computers[i].id === computerId) return deskState.computers[i].label
    }
    return computerId
  }

  function monitorLabel(serial) {
    for (var i = 0; i < deskState.monitors.length; i++) {
      if (deskState.monitors[i].serial === serial) return deskState.monitors[i].label
    }
    return "this screen"
  }

  function setStatus(key, text, urgent) { statusKey = key; statusText = text; statusUrgent = urgent === true }
  function clearStatus() { statusKey = ""; statusText = ""; statusUrgent = false }

  // Ask first, then act. `busy` goes up HERE so a second click cannot
  // overwrite the in-flight reachability check and suppress the dialog the
  // first, unreachable, machine had earned.
  function sendTo(computerId, serial) {
    busy = true
    pendingComputer = computerId
    pendingSerial = serial || ""
    clearStatus()
    setStatus(rowKey(computerId, pendingSerial), "Checking…", false)
    watchdog.restart()
    reachProc.command = [root.engine, "reachable", computerId]
    reachProc.running = true
  }

  function reallySendTo(computerId) {
    busy = true
    setStatus(rowKey(computerId, pendingSerial), "Sending…", false)
    watchdog.restart()
    var cmd = [root.engine, "switch", computerId]
    if (pendingSerial !== "") cmd = cmd.concat(["--screen", pendingSerial])
    switchProc.command = cmd
    switchProc.running = true
  }

  function rowKey(computerId, serial) { return "c:" + computerId + ":" + (serial || "") }

  function openSetup() {
    root.close()
    if (setupLoader.active && setupLoader.item) setupLoader.item.open()
    else setupLoader.active = true
  }

  // The rows on screen right now, as data, so the mouse, the keyboard cursor
  // and the layout all read the same list.
  readonly property var rows: {
    var out = []
    var s = deskState
    if (!s.known) return out
    if (submenuSerial === "") {
      for (var i = 0; i < s.computers.length; i++) {
        var c = s.computers[i]
        out.push({ key: rowKey(c.id, ""), kind: "computer", id: c.id, label: c.label,
                   icon: "\u{f0379}", current: c.id === s.current, trailing: "" })
      }
      if (s.monitors.length > 1)
        out.push({ key: "nav:screens", kind: "screens", label: "Send one screen", icon: "", current: false, trailing: "\u{f0142}" })
    } else if (submenuSerial === "monitors") {
      for (var m = 0; m < s.monitors.length; m++)
        out.push({ key: "m:" + s.monitors[m].serial, kind: "monitor", serial: s.monitors[m].serial,
                   label: s.monitors[m].label, icon: "\u{f0379}", current: false, trailing: "\u{f0142}" })
      out.push({ key: "nav:back", kind: "back", label: "Back", icon: "\u{f0141}", current: false, trailing: "" })
    } else {
      for (var j = 0; j < s.computers.length; j++) {
        var cc = s.computers[j]
        out.push({ key: rowKey(cc.id, submenuSerial), kind: "computer", id: cc.id, serial: submenuSerial,
                   label: cc.label, icon: "\u{f0379}", current: (s.live[submenuSerial] || "") === (cc.inputs[submenuSerial] || "-"), trailing: "" })
      }
      out.push({ key: "nav:back", kind: "back", label: "Back", icon: "\u{f0141}", current: false, trailing: "" })
    }
    return out
  }

  readonly property string sectionTitle: {
    if (submenuSerial === "") return "SEND SCREENS TO"
    if (submenuSerial === "monitors") return "WHICH SCREEN"
    return "SEND " + monitorLabel(submenuSerial).toUpperCase() + " TO"
  }

  readonly property string heroMeta: {
    if (loading && !deskState.known) return "CHECKING SCREENS…"
    if (!deskState.known) return "NOT SET UP"
    if (deskState.current) return "SCREENS ARE ON " + labelFor(deskState.current).toUpperCase()
    return "SPLIT ACROSS COMPUTERS"
  }

  function activate(row) {
    if (!row || busy) return
    if (row.kind === "computer") { if (!row.current) sendTo(row.id, row.serial) }
    else if (row.kind === "screens") { submenuSerial = "monitors"; selectedIndex = 0 }
    else if (row.kind === "monitor") { submenuSerial = row.serial; selectedIndex = 0 }
    else if (row.kind === "back") { submenuSerial = (submenuSerial === "monitors" ? "" : "monitors"); selectedIndex = 0 }
  }

  function moveCursor(delta) {
    if (rows.length === 0) return
    if (!cursorActive) { cursorActive = true; return }
    selectedIndex = Math.max(0, Math.min(rows.length - 1, selectedIndex + delta))
  }

  // Every piece of transient state resets on open: a stale confirmation, a
  // stuck busy from a process that never reported, a submenu left open.
  // Reopening is the gesture people make when it stops responding, so it is
  // the thing that must unstick it.
  onOpenedChanged: {
    if (opened) {
      submenuSerial = ""
      confirmOpen = false
      pendingComputer = ""
      pendingSerial = ""
      busy = false
      cursorActive = false
      selectedIndex = 0
      clearStatus()
      refresh()
    }
  }

  onConfirmOpenChanged: if (confirmOpen) confirm.selectedIndex = 0

  // A Process that fails to spawn reports nothing at all. Nothing should sit
  // on "Sending…" forever.
  Timer {
    id: watchdog
    interval: 30000
    repeat: false
    onTriggered: if (root.busy) { root.busy = false; root.setStatus(root.statusKey, "Timed out. Try again.", true) }
  }

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
    stderr: StdioCollector { id: reachStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) { root.reallySendTo(root.pendingComputer); return }
      var reason = String(reachStderr.text || "").trim()
      if (reason !== "") {
        // The engine had its own reason (desk not set up, no such id). That
        // is not "the machine is not answering", so no dialog: show it.
        watchdog.stop()
        root.busy = false
        root.setStatus(root.statusKey, reason, true)
        return
      }
      watchdog.stop()
      root.setStatus(root.statusKey, "", false)
      root.confirmOpen = true
    }
  }

  Process {
    id: switchProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: switchStderr; waitForEnd: true }
    onExited: function(exitCode) {
      watchdog.stop()
      root.busy = false
      if (exitCode === 0) {
        root.clearStatus()
        root.broadcast("refresh")
        // The screens are now on another computer, so the person is not
        // looking at this panel. A notification is the one thing they can see.
        if (root.pendingSerial === "") {
          notifyProc.command = ["notify-send", "Screen Push", "Screens sent to " + root.labelFor(root.pendingComputer) + "."]
          notifyProc.running = true
        }
        root.close()
        return
      }
      // Refused: nothing moved. Leave the menu up and say why, under the row.
      root.setStatus(root.statusKey, String(switchStderr.text || "").trim(), true)
    }
  }

  Process { id: notifyProc }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.broadcast("refresh") }
    function screens(): void { root.open(); root.submenuSerial = "monitors" }
    function setup(): void { root.openSetup() }
    function send(id: string): string { root.sendTo(id); return "ok" }
  }

  // One menu line, built like a bluetooth device row: left label with an
  // icon column, a right-hand slot for a status word, a chevron or a check,
  // hover fill, stronger fill and a check for the current one.
  component MenuRow: CursorSurface {
    id: row
    property var model: ({})
    property int index: 0
    property string status: ""
    property bool statusUrgent: false
    readonly property bool isCurrent: model.current === true
    readonly property bool clickable: root.enabled && !root.busy && !isCurrent

    foreground: root.barForeground
    current: isCurrent
    hasCursor: root.cursorActive && root.selectedIndex === index
    implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX
    opacity: (root.busy && root.statusKey !== model.key) ? 0.45 : 1

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: row.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
      onContainsMouseChanged: if (containsMouse) { root.cursorActive = true; root.selectedIndex = row.index }
      onClicked: if (row.clickable) root.activate(row.model)
    }

    Item {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      implicitHeight: Math.max(rowIcon.implicitHeight, rowLabel.implicitHeight, Style.font.title)

      Text {
        id: rowIcon
        visible: row.model.icon !== ""
        text: row.model.icon || ""
        color: row.foreground
        font.family: root.ff
        font.pixelSize: Style.font.title
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: rowLabel
        text: row.model.label + (row.isCurrent ? " · here now" : "")
        color: row.foreground
        font.family: root.ff
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        anchors.left: row.model.icon !== "" ? rowIcon.right : parent.left
        anchors.leftMargin: row.model.icon !== "" ? Style.space(10) : 0
        anchors.right: rowRight.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
      }

      // Right slot: a status word while working, a check for the current
      // computer, or a chevron for a row that leads somewhere.
      Text {
        id: rowRight
        text: row.status !== "" && !row.statusUrgent ? row.status
            : row.isCurrent ? "\u{f012c}"
            : (row.model.trailing || "")
        color: row.status !== "" ? row.foreground : Qt.darker(row.foreground, 1.4)
        font.family: root.ff
        font.pixelSize: row.status !== "" ? Style.font.caption : Style.font.subtitle
        horizontalAlignment: Text.AlignRight
        width: Math.max(Style.space(22), implicitWidth)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\u{f04e1}"
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.confirmOpen
      onCloseRequested: root.close()
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveCursor(dy) }
      onActivateRequested: if (root.cursorActive) root.activate(root.rows[root.selectedIndex])
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(14)

        PanelHero {
          foreground: root.barForeground
          fontFamily: root.ff
          title: "Screen Push"
          meta: root.heroMeta
          iconComponent: Component {
            Text {
              text: "\u{f04e1}"
              color: root.barForeground
              font.family: root.ff
              font.pixelSize: Style.font.display
            }
          }
          trailingControl: Component {
            PanelActionButton {
              iconText: "\u{f0493}"
              tooltipText: root.deskState.known ? "Edit this desk" : "Set up this desk"
              foreground: root.barForeground
              fontFamily: root.ff
              onClicked: root.openSetup()
            }
          }
        }

        PanelSeparator { foreground: root.barForeground }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: root.sectionTitle
            foreground: root.barForeground
            fontFamily: root.ff
            visible: root.deskState.known
          }

          // Not set up, or nothing answered: one sentence and the gear above.
          Text {
            visible: !root.deskState.known
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.loading ? "Checking screens…"
                : root.deskState.hint !== "" ? root.deskState.hint
                : "This desk isn't set up yet. Use the gear above to set it up."
            color: Qt.darker(root.barForeground, 1.5)
            font.family: root.ff
            font.pixelSize: Style.font.bodySmall
          }

          // A screen the desk has never seen still shows; a switch just leaves
          // it where it is. Say so before the click.
          Text {
            visible: root.submenuSerial === "" && root.deskState.known && root.deskState.unmapped.length > 0
            width: parent.width
            wrapMode: Text.WordWrap
            text: (root.deskState.unmapped.length === 1
                   ? "1 screen here isn't set up yet and will stay put."
                   : root.deskState.unmapped.length + " screens here aren't set up yet and will stay put.")
                  + " Use the gear above to add it."
            color: Color.urgent
            font.family: root.ff
            font.pixelSize: Style.font.bodySmall
          }

          Repeater {
            model: root.rows
            delegate: Column {
              required property var modelData
              required property int index
              width: parent.width
              spacing: Style.space(4)

              MenuRow {
                width: parent.width
                model: modelData
                index: parent.index
                status: root.statusKey === modelData.key ? root.statusText : ""
                statusUrgent: root.statusUrgent
              }

              // The engine's refusal, under the row that asked for it.
              Text {
                visible: root.statusKey === modelData.key && root.statusUrgent && root.statusText !== ""
                width: parent.width - Style.space(20)
                x: Style.space(10)
                wrapMode: Text.WordWrap
                text: root.statusText
                color: Color.urgent
                font.family: root.ff
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }

      // ConfirmDialog has no focus of its own; keys must be routed into
      // handleKey(). PanelKeyCatcher stands down (blocked) while it is up.
      Item {
        id: confirmKeys
        anchors.fill: parent
        z: 11
        visible: root.confirmOpen
        onVisibleChanged: if (visible) forceActiveFocus(); else keyCatcher.forceActiveFocus()
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) { if (confirm.handleKey(event)) event.accepted = true }
      }

      ConfirmDialog {
        id: confirm
        anchors.fill: parent
        z: 10
        opened: root.confirmOpen
        message: root.labelFor(root.pendingComputer) + " isn't answering. It may be off or asleep. Send the screens anyway?"
        confirmText: "Send anyway"
        cancelText: "Cancel"
        onConfirmed: { root.confirmOpen = false; root.reallySendTo(root.pendingComputer) }
        onCanceled: { root.confirmOpen = false; root.pendingComputer = ""; root.pendingSerial = ""; root.busy = false; root.clearStatus() }
      }
    }
  }

  Loader {
    id: setupLoader
    active: false
    source: Qt.resolvedUrl("Setup.qml")
    onStatusChanged: {
      if (status === Loader.Error) {
        notifyProc.command = ["notify-send", "Screen Push", "Couldn't open desk setup. Run: journalctl --user -b | grep screenpush"]
        notifyProc.running = true
        active = false
      }
    }
    onLoaded: {
      item.engine = root.engine
      item.anchorItem = button
      item.bar = root.bar
      // Not deactivating on close: that destroys the half-filled sheet.
      item.closed.connect(function() { root.refresh() })
      item.open()
    }
  }
}
