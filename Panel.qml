pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Ui
import qs.Ui as Ui
import "Engine.js" as Engine

Panel {
  id: root
  moduleName: "io.github.steveclarke.screenpush"
  ipcTarget: "screenpush"
  manageIpc: false

  // The bar sizes a widget from its root's implicit size; without these the
  // slot is 0x0 and the widget is invisible and unclickable.
  implicitWidth: barButton.implicitWidth
  implicitHeight: barButton.implicitHeight

  readonly property string engine: Engine.enginePath(Qt.resolvedUrl)
  readonly property string ff: bar ? bar.fontFamily : Style.font.family
  property var deskState: Engine.parseState("")
  property bool busy: false
  property string pendingComputer: ""
  property string pendingSerial: ""
  // The computer that did not answer a ping. Non-empty puts the message box
  // up with its own Send anyway; there is no modal dialog any more.
  property string unreachable: ""
  readonly property bool loading: stateProc.running

  // Which row is doing something and what it says while it does it. A switch
  // takes several seconds; the row it was asked on reports progress and, on
  // refusal, the engine's own sentence.
  property string statusKey: ""
  property string statusText: ""
  property bool statusUrgent: false

  // Keyboard cursor over the computer rows, as every first-party panel.
  property bool cursorActive: false
  property int selectedIndex: 0

  readonly property var prefs: Engine.prefs(settings)
  readonly property string barName: Engine.barLabel(deskState, views)
  // Whichever bar control is showing: icon only, or icon and computer name.
  readonly property Item barButton: prefs.barText === "computer" && barName !== "" ? textButton : button

  readonly property color ink: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(ink, 1.4)
  readonly property color muted: Color.muted
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color track: Qt.rgba(ink.r, ink.g, ink.b, 0.12)

  // What the desk looks like right now: one entry per screen, in the desk's
  // own left-to-right order, carrying the computer it is showing.
  readonly property var views: Engine.screenViews(deskState)
  readonly property var heroData: Engine.hero(deskState, views, {
    loading: root.loading && !root.deskState.known,
    busy: root.busy,
    sendingSerial: root.pendingSerial,
    sendingTo: root.pendingComputer,
    unreachable: root.unreachable
  })
  readonly property color stateColor: heroData.tone === "urgent" ? urgent
                                    : heroData.tone === "accent" ? accent
                                    : heroData.tone === "dim" ? dim : ink
  readonly property int unmappedCount: {
    var n = 0
    for (var i = 0; i < views.length; i++) if (views[i].unmapped) n++
    return n
  }
  readonly property bool allAway: {
    if (!deskState.known || views.length === 0) return false
    for (var i = 0; i < views.length; i++) if (views[i].here) return false
    return true
  }

  function refresh() { stateProc.running = true }

  // Ui/Panel has no broadcast(); this is Ui/BarWidget.qml:29-35. One bar
  // surface exists per monitor, so a process exit reaches one instance and the
  // others keep stale state until reopened. Relay refreshes only; never a side
  // effect, and never from inside refresh().
  function broadcast(method) {
    var items = bar && typeof bar.moduleWidgets === "function"
      ? bar.moduleWidgets(moduleName) : [root]
    for (var i = 0; i < items.length; i++) {
      if (items[i] && typeof items[i][method] === "function") items[i][method]()
    }
  }

  function labelFor(computerId) { return Engine.labelOf(deskState, computerId) }

  function setStatus(key, text, urgent) { statusKey = key; statusText = text; statusUrgent = urgent === true }
  function clearStatus() { statusKey = ""; statusText = ""; statusUrgent = false }

  // Ask first, then act. `busy` goes up HERE so a second click cannot overwrite
  // the in-flight reachability check and suppress the message the first,
  // unreachable, machine had earned.
  function sendTo(computerId, serial) {
    if (busy || computerId === "") return
    busy = true
    unreachable = ""
    pendingComputer = computerId
    pendingSerial = serial || ""
    clearStatus()
    setStatus(rowKey(computerId, pendingSerial), "Checking…", false)
    watchdog.restart()
    reachStderr.reset()
    reachProc.command = [root.engine, "reachable", computerId]
    reachProc.running = true
  }

  // Clicking a screen sends that screen to the next computer in the desk's
  // order, which on a two-computer desk is simply the other one.
  function sendScreen(view) {
    if (!view || busy || !deskState.known) return
    if (view.unmapped) { openSetup(); return }
    sendTo(Engine.nextComputer(deskState, view.computerId), view.serial)
  }

  function reallySendTo(computerId) {
    busy = true
    unreachable = ""
    setStatus(rowKey(computerId, pendingSerial), "Sending…", false)
    watchdog.restart()
    var cmd = [root.engine, "switch", computerId]
    if (pendingSerial !== "") cmd = cmd.concat(["--screen", pendingSerial])
    switchStderr.reset()
    switchProc.command = cmd
    switchProc.running = true
  }

  function cancelSend() {
    unreachable = ""
    pendingComputer = ""
    pendingSerial = ""
    busy = false
    clearStatus()
  }

  // The shell replaces this widget's whole entry, so every setting it already
  // holds is carried along with the ones being changed.
  function saveSettings(changes) {
    var api = bar && bar.shell ? bar.shell : null
    if (!api || typeof api.updateEntryInline !== "function") return false
    var merged = Object.assign({}, settings || {}, changes || {})
    delete merged.id
    return api.updateEntryInline(moduleName, merged)
  }

  function rowKey(computerId, serial) { return "c:" + computerId + ":" + (serial || "") }

  function openSetup() {
    root.close()
    if (setupLoader.active && setupLoader.item) setupLoader.item.open()
    else setupLoader.active = true
  }

  // The computer rows on screen right now, as data, so the mouse, the keyboard
  // cursor and the layout all read the same list.
  readonly property var rows: {
    var out = []
    if (!deskState.known) return out
    for (var i = 0; i < deskState.computers.length; i++) {
      var c = deskState.computers[i]
      var mine = true
      for (var v = 0; v < views.length; v++) if (views[v].computerId !== String(c.id)) mine = false
      out.push({ key: rowKey(c.id, ""), id: String(c.id), label: Engine.plain(c.label),
                 icon: "\u{f0379}", current: mine && views.length > 0 })
    }
    return out
  }

  function activate(row) {
    if (!row || busy) return
    if (!row.current) sendTo(row.id, "")
  }

  function moveCursor(delta) {
    if (rows.length === 0) return
    if (!cursorActive) { cursorActive = true; return }
    selectedIndex = Math.max(0, Math.min(rows.length - 1, selectedIndex + delta))
  }

  // Every piece of transient state resets on open: a stuck busy from a process
  // that never reported, a message box left up. Reopening is the gesture people
  // make when it stops responding, so it is the thing that must unstick it.
  onOpenedChanged: {
    if (opened) {
      cancelSend()
      cursorActive = false
      selectedIndex = 0
      refresh()
    }
  }

  // A Process that fails to spawn reports nothing at all. Nothing should sit on
  // "Sending…" forever.
  Timer {
    id: watchdog
    interval: 30000
    repeat: false
    onTriggered: if (root.busy) { root.busy = false; root.setStatus(root.statusKey, "Timed out. Try again.", true) }
  }

  Process {
    id: stateProc
    command: [root.engine, "state"]
    stdout: BoundedParser { id: stateOut; onOverflow: stateProc.signal(15) }
    onStarted: stateOut.reset()
    onExited: function(exitCode) { root.deskState = Engine.parseState(stateOut.overflowed ? "" : stateOut.text) }
  }

  Process {
    id: reachProc
    stderr: BoundedParser { id: reachStderr; maxBytes: 8192 }
    onExited: function(exitCode) {
      if (exitCode === 0) { root.reallySendTo(root.pendingComputer); return }
      watchdog.stop()
      var reason = reachStderr.text.trim()
      root.busy = false
      if (reason !== "") {
        // The engine had its own reason (desk not set up, no such id). That is
        // not "the machine is not answering", so no message box: show it.
        root.setStatus(root.statusKey, reason, true)
        return
      }
      root.clearStatus()
      if (!root.prefs.askWhenUnreachable) { root.reallySendTo(root.pendingComputer); return }
      root.unreachable = root.pendingComputer
    }
  }

  Process {
    id: switchProc
    stdout: BoundedParser { maxBytes: 8192 }
    stderr: BoundedParser { id: switchStderr; maxBytes: 8192 }
    onExited: function(exitCode) {
      watchdog.stop()
      root.busy = false
      if (exitCode === 0) {
        var wasAll = root.pendingSerial === ""
        var target = root.labelFor(root.pendingComputer)
        root.cancelSend()
        root.broadcast("refresh")
        if (wasAll) {
          // Every screen is now on another computer, so the person is not
          // looking at this panel. A notification is the one thing they can see.
          if (root.prefs.notifyAfterSwitch) {
            notifyProc.command = ["/usr/bin/notify-send", "Screen Push", "Screens sent to " + target + "."]
            notifyProc.running = true
          }
          root.close()
        }
        return
      }
      // Refused: nothing moved. Leave the panel up and say why.
      root.setStatus(root.statusKey, switchStderr.text.trim(), true)
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
    function setup(): void { root.openSetup() }
    function send(id: string): string { root.sendTo(id, ""); return "ok" }
  }

  // Every string this panel shows comes from the person's own config or from
  // the monitor itself, so no Text in here is allowed to interpret markup.
  component PlainLabel: Text {
    textFormat: Text.PlainText
    color: root.ink
    font.family: root.ff
    font.pixelSize: Style.font.body
  }

  // One screen on the desk: a rectangle carrying the name of the computer it
  // is showing, its stand below it, and its own name under that. Accent border
  // while it is on this computer, dashed-looking dim while it is not set up.
  component ScreenBox: Column {
    id: boxCol
    property var view: ({})
    property bool sending: false
    readonly property bool clickable: root.deskState.known && !root.busy
    spacing: 0

    Rectangle {
      id: face
      width: parent.width
      implicitHeight: Math.max(Style.space(46), who.implicitHeight + Style.space(26))
      radius: Style.cornerRadius
      color: boxCol.view.here ? "transparent" : root.track
      border.width: 2
      border.color: boxCol.sending ? root.accent
                  : boxCol.view.unmapped ? root.urgent
                  : boxCol.view.here ? root.accent : root.track
      clip: true

      Rectangle {
        id: fill
        visible: boxCol.sending
        height: parent.height
        width: 0
        color: root.accent
        opacity: 0.25
        SequentialAnimation on width {
          running: boxCol.sending
          loops: Animation.Infinite
          NumberAnimation { from: 0; to: face.width; duration: 1500; easing.type: Easing.InOutSine }
          PauseAnimation { duration: 200 }
        }
      }

      PlainLabel {
        id: who
        anchors.centerIn: parent
        width: parent.width - Style.space(12)
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: boxCol.view.computerLabel || ""
        color: boxCol.view.unmapped ? root.urgent : boxCol.view.here ? root.ink : root.dim
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: boxCol.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (boxCol.clickable) root.sendScreen(boxCol.view)
      }
    }

    Rectangle { width: Math.round(parent.width * 0.36); height: Style.space(4); color: root.track
                anchors.horizontalCenter: parent.horizontalCenter }
    Rectangle { width: Math.round(parent.width * 0.58); height: Style.space(3); radius: height / 2; color: root.track
                anchors.horizontalCenter: parent.horizontalCenter }

    PlainLabel {
      width: parent.width
      topPadding: Style.space(6)
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      text: (boxCol.view.label || "").toUpperCase()
      color: root.dim
      font.pixelSize: Style.font.caption
      font.letterSpacing: 0.8
    }
  }

  // One box for everything that has gone wrong: the problem in bold, the next
  // step, the command to check with, and its own buttons.
  component MessageBox: Rectangle {
    id: box
    property color tone: root.urgent
    property string title: ""
    property string next: ""
    property string command: ""
    default property alias buttons: buttonRow.data
    width: parent.width
    implicitHeight: boxText.implicitHeight + Style.space(20)
    color: "transparent"
    radius: Style.cornerRadius
    border.width: 1
    border.color: tone

    Column {
      id: boxText
      x: Style.space(12); y: Style.space(10); width: parent.width - Style.space(24)
      spacing: Style.space(4)
      PlainLabel { width: parent.width; wrapMode: Text.WordWrap; text: box.title; color: box.tone; font.bold: true }
      PlainLabel { visible: box.next !== ""; width: parent.width; wrapMode: Text.WordWrap; text: box.next }
      PlainLabel { visible: box.command !== ""; width: parent.width; elide: Text.ElideRight; text: box.command
                   color: root.dim; font.pixelSize: Style.font.bodySmall }
      Row { id: buttonRow; spacing: Style.space(8); topPadding: Style.space(4) }
    }
  }

  // One computer line, built like a bluetooth device row: left label with an
  // icon column, a right-hand slot for a status word or a check, hover fill.
  component MenuRow: CursorSurface {
    id: row
    property var model: ({})
    property int index: 0
    property string status: ""
    property bool statusUrgent: false
    readonly property bool isCurrent: model.current === true
    readonly property bool clickable: root.enabled && !root.busy && !isCurrent

    foreground: root.ink
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

      PlainLabel {
        id: rowIcon
        text: row.model.icon || ""
        color: row.foreground
        font.pixelSize: Style.font.title
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      PlainLabel {
        id: rowLabel
        text: (row.model.label || "") + (row.isCurrent ? " · here now" : "")
        color: row.foreground
        elide: Text.ElideRight
        anchors.left: rowIcon.right
        anchors.leftMargin: Style.space(10)
        anchors.right: rowRight.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
      }

      PlainLabel {
        id: rowRight
        text: row.status !== "" && !row.statusUrgent ? row.status
            : row.isCurrent ? "\u{f012c}" : ""
        color: row.status !== "" ? row.foreground : Qt.darker(row.foreground, 1.4)
        font.pixelSize: row.status !== "" ? Style.font.caption : Style.font.subtitle
        horizontalAlignment: Text.AlignRight
        width: Math.max(Style.space(22), implicitWidth)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

  WidgetButton {
    id: textButton
    anchors.fill: parent
    visible: root.barButton === textButton
    bar: root.bar
    text: "\u{f04e1}  " + Engine.plain(root.barName)
    foreground: button.foreground
    onPressed: root.toggle()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    visible: root.barButton === button
    bar: root.bar
    text: "\u{f04e1}"
    // State lives in the glyph colour: accent while a switch is running, urgent
    // when a screen here is not set up, dim while the screens are elsewhere.
    foreground: root.busy ? root.accent
              : root.unmappedCount > 0 ? root.urgent
              : root.allAway ? root.dim
              : (root.bar ? root.bar.foreground : Color.foreground)
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.barButton
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveCursor(dy) }
      onActivateRequested: if (root.cursorActive) root.activate(root.rows[root.selectedIndex])
      onTabRequested: function(direction) { root.switchPanel(direction) }
      Keys.onPressed: function(event) {
        if (event.text === ",") { root.openSetup(); event.accepted = true }
        else if (event.text === "r" || event.text === "R") { root.refresh(); event.accepted = true }
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(14)

        // ---------- hero ----------
        PanelHero {
          width: parent.width
          foreground: root.stateColor
          fontFamily: root.ff
          metaOpacity: 1
          title: Engine.plain(root.heroData.title)
          meta: Engine.plain(root.heroData.meta).toUpperCase()
          iconComponent: Component {
            PlainLabel {
              text: "\u{f04e1}"
              color: root.stateColor
              font.pixelSize: Style.font.display
            }
          }
          trailingControl: Component {
            PanelActionButton {
              iconText: "\u{f0493}"
              tooltipText: root.deskState.known ? "Set up this desk" : "Set up this desk"
              foreground: root.ink
              fontFamily: root.ff
              onClicked: root.openSetup()
            }
          }
        }
        PlainLabel {
          visible: root.heroData.detail !== ""
          width: parent.width
          topPadding: -Style.space(10)
          text: Engine.plain(root.heroData.detail)
          color: root.dim
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        // ---------- the desk ----------
        Column {
          visible: root.deskState.known && root.views.length > 0
          width: parent.width
          spacing: Style.space(10)
          PanelSeparator { foreground: root.ink }
          PanelSectionHeader { text: "THIS DESK"; foreground: root.ink; fontFamily: root.ff }
          Row {
            id: deskRow
            width: parent.width
            spacing: Style.space(10)
            Repeater {
              model: root.views
              delegate: ScreenBox {
                required property var modelData
                required property int index
                width: (deskRow.width - Style.space(10) * (root.views.length - 1)) / Math.max(1, root.views.length)
                view: modelData
                sending: root.busy && root.pendingSerial === modelData.serial
              }
            }
          }
        }

        // ---------- not set up: three steps ----------
        Column {
          visible: !root.deskState.known && !root.loading
          width: parent.width
          spacing: Style.space(10)
          PanelSeparator { foreground: root.ink }
          PanelSectionHeader { text: "TO SET IT UP"; foreground: root.ink; fontFamily: root.ff }
          Repeater {
            model: [
              { step: "Turn on DDC/CI in each screen's own menu", hint: "Usually under Others or System" },
              { step: "Open setup and name your computers", hint: "Whatever you call them" },
              { step: "Pick the input each computer is plugged into", hint: "Try it switches the screen so you can see which is which" }
            ]
            delegate: Row {
              required property var modelData
              required property int index
              width: parent.width
              spacing: Style.space(12)
              PlainLabel { text: String(index + 1); color: root.dim; font.pixelSize: Style.font.bodySmall }
              Column {
                width: parent.width - Style.space(24)
                spacing: Style.space(2)
                PlainLabel { width: parent.width; wrapMode: Text.WordWrap; text: modelData.step; font.pixelSize: Style.font.bodySmall }
                PlainLabel { width: parent.width; wrapMode: Text.WordWrap; text: modelData.hint; color: root.dim; font.pixelSize: Style.font.caption }
              }
            }
          }
        }

        // ---------- a screen that is not set up ----------
        MessageBox {
          visible: root.deskState.known && root.unmappedCount > 0 && root.unreachable === ""
          tone: root.urgent
          title: root.unmappedCount === 1 ? "One screen here isn't set up, so it will stay put."
                                          : String(root.unmappedCount) + " screens here aren't set up, so they will stay put."
          next: "Open setup and pick the input each computer uses. If a screen doesn't appear, turn on DDC/CI in its own menu."
          command: "ddcutil detect"
          Ui.Button {
            text: "Set up this desk"; iconText: "\u{f0493}"
            foreground: root.ink; bordered: true; fontFamily: root.ff; fontSize: Style.font.caption
            onClicked: root.openSetup()
          }
          Ui.Button {
            text: "Look again"; iconText: "\u{f0450}"
            foreground: root.ink; bordered: true; fontFamily: root.ff; fontSize: Style.font.caption
            onClicked: root.refresh()
          }
        }

        // ---------- a computer that did not answer ----------
        MessageBox {
          visible: root.unreachable !== ""
          tone: root.urgent
          title: root.labelFor(root.unreachable) + " didn't answer."
          next: "It may be off or asleep. The screens will still switch; you just won't see anything until it wakes."
          Ui.Button {
            text: "Send anyway"
            foreground: root.ink; bordered: true; fontFamily: root.ff; fontSize: Style.font.caption
            onClicked: { var id = root.unreachable; root.unreachable = ""; root.reallySendTo(id) }
          }
          Ui.Button {
            text: "Cancel"
            foreground: root.ink; bordered: true; fontFamily: root.ff; fontSize: Style.font.caption
            onClicked: root.cancelSend()
          }
        }

        // ---------- send every screen ----------
        Column {
          visible: root.deskState.known && root.rows.length > 0
          width: parent.width
          spacing: Style.space(4)
          PanelSeparator { foreground: root.ink }
          PanelSectionHeader { text: "SEND ALL SCREENS TO"; foreground: root.ink; fontFamily: root.ff }
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
              PlainLabel {
                visible: root.statusKey === modelData.key && root.statusUrgent && root.statusText !== ""
                width: parent.width - Style.space(20)
                x: Style.space(10)
                wrapMode: Text.WordWrap
                text: root.statusText
                color: root.urgent
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        // ---------- actions ----------
        Row {
          width: parent.width
          layoutDirection: Qt.RightToLeft
          spacing: Style.space(8)
          Ui.Button {
            visible: root.deskState.known
            text: "Refresh"; iconText: "\u{f0450}"
            foreground: root.ink; bordered: true; fontFamily: root.ff; iconSize: Style.font.icon
            onClicked: root.refresh()
          }
          Ui.Button {
            text: "Set up this desk"; iconText: "\u{f0493}"
            foreground: root.ink; bordered: true; fontFamily: root.ff; iconSize: Style.font.icon
            onClicked: root.openSetup()
          }
        }

        PlainLabel {
          visible: root.deskState.known
          width: parent.width
          elide: Text.ElideRight
          text: "j/k select · enter send · , set up · esc close"
          color: root.muted
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  Loader {
    id: setupLoader
    active: false
    source: Qt.resolvedUrl("Setup.qml")
    onStatusChanged: {
      if (status === Loader.Error) {
        notifyProc.command = ["/usr/bin/notify-send", "Screen Push", "Couldn't open desk setup. Run: journalctl --user -b | grep screenpush"]
        notifyProc.running = true
        active = false
      }
    }
    onLoaded: {
      item.engine = root.engine
      item.anchorItem = root.barButton
      item.host = root
      item.bar = root.bar
      // Not deactivating on close: that destroys the half-filled sheet.
      item.closed.connect(function() { root.refresh() })
      item.open()
    }
  }
}
