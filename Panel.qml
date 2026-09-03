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

  // A bar widget must publish its own size. Item defaults to 0x0, so
  // without these the bar allocates no width: the widget loads, runs and
  // registers its IPC, and draws nothing. Every first-party bar widget
  // sets these off its button.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string engine: Engine.enginePath(Qt.resolvedUrl)
  property var deskState: Engine.parseState("")
  property bool busy: false
  property string pendingComputer: ""
  property bool confirmOpen: false

  function refresh() { stateProc.running = true }

  // Ui/Panel has no broadcast(); this is Ui/BarWidget.qml:29-35. A bar surface
  // exists per monitor, so an IPC call or a process exit reaches exactly one
  // instance - the others keep showing stale state until they are reopened.
  // Relay refreshes only. Broadcasting a side effect like sendTo would run the
  // DDC switch once per screen, and calling this from inside refresh() would
  // recurse forever, so the caller broadcasts and refresh() stays local.
  function broadcast(method) {
    var items = bar && typeof bar.moduleWidgets === "function"
      ? bar.moduleWidgets(moduleName) : [root]
    for (var i = 0; i < items.length; i++) {
      if (items[i] && typeof items[i][method] === "function") items[i][method]()
    }
  }

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
  //
  // busy resets here too. A switch takes a few seconds and closes the panel
  // itself when it finishes, so a `busy` surviving into a fresh summon is
  // stale by definition - and reopening the menu is the gesture someone makes
  // when it has stopped responding, so it is the thing that should unstick it.
  // Quickshell's Process has no errorOccurred signal, so a process that fails
  // to start reports nothing at all, and this reset is the only thing that
  // releases the menu in that case.
  onOpenedChanged: {
    if (opened) {
      submenuSerial = ""
      confirmOpen = false
      pendingComputer = ""
      busy = false
      refresh()
    }
  }
  // No refresh on completion. A bar surface exists per monitor, so this ran
  // once per screen at every shell start and hot reload - each call is two
  // `ddcutil detect` passes plus a getvcp per monitor, concurrently on the same
  // I2C buses. The collapsed widget renders a fixed glyph and shows no state,
  // and the panel already refreshes in onOpenedChanged, so it bought nothing.

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
    // Non-zero does not always mean "the machine is not answering". On a desk
    // that was never set up the engine exits 1 with its own explanation, and
    // asking "send the screens anyway?" would be both wrong and unanswerable.
    // Only an actual reachability failure earns the dialog.
    onExited: function(exitCode) {
      if (exitCode === 0) { root.reallySendTo(root.pendingComputer); return }
      var reason = String(reachStderr.text || "").trim()
      if (reason !== "") {
        root.busy = false
        root.pendingComputer = ""
        notifyProc.command = ["notify-send", "Screen Push", reason]
        notifyProc.running = true
        return
      }
      root.confirmOpen = true
    }
  }

  Process {
    id: switchProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: switchStderr; waitForEnd: true }
    // A refusal - no DDC response, an unsupported code, an ambiguous
    // computer id - exits non-zero with the reason on stderr, written by
    // the engine to be read by a person. Closing unconditionally here would
    // make every refusal look identical to a success: the menu just shuts
    // and nothing moves, with no way to tell the two apart. So close only
    // on success; on failure, leave the menu as it is and surface the
    // engine's own message instead.
    onExited: function(exitCode) {
      root.busy = false
      if (exitCode === 0) { root.broadcast("refresh"); root.close(); return }
      notifyProc.command = ["notify-send", "Screen Push", String(switchStderr.text || "").trim()]
      notifyProc.running = true
    }
    // Failing closed is right here: nothing moved, so release the menu and
    // let them try again, unlike reachProc's fail-open above.
  }

  Process { id: notifyProc }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    // Broadcast: an IPC call lands on one instance, and a stale second screen
    // is exactly what this exists to prevent.
    function refresh(): void { root.broadcast("refresh") }
    // Opening setup without going through the menu. Worth having on its own
    // terms - it gives the setup sheet a bindable entry point - and it is the
    // only way to reach the sheet without a pointer.
    function setup(): void {
      root.close()
      if (setupLoader.active && setupLoader.item) setupLoader.item.open()
      else setupLoader.active = true
    }
    function send(id: string): string { root.sendTo(id); return "ok" }
  }

  // One menu line, built the way the bluetooth and network panels build a
  // device row: left-aligned label, optional icon, optional trailing text or
  // chevron on the right, hover fill, and a stronger fill for the current one.
  component MenuRow: CursorSurface {
    id: row
    property string label: ""
    property string icon: ""
    property string trailing: ""
    property bool dim: false
    signal activated()

    foreground: root.barForeground
    implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX
    opacity: enabled ? 1 : 0.5

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: if (row.enabled) row.activated()
    }

    Item {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      implicitHeight: Math.max(rowIcon.implicitHeight, rowLabel.implicitHeight)

      Text {
        id: rowIcon
        visible: row.icon !== ""
        text: row.icon
        color: row.dim ? Qt.darker(row.foreground, 1.4) : row.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.title
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: rowLabel
        text: row.label
        color: row.dim ? Qt.darker(row.foreground, 1.4) : row.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        anchors.left: rowIcon.visible ? rowIcon.right : parent.left
        anchors.leftMargin: rowIcon.visible ? Style.space(10) : 0
        anchors.right: rowTrailing.visible ? rowTrailing.left : parent.right
        anchors.rightMargin: rowTrailing.visible ? Style.space(8) : 0
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: rowTrailing
        visible: row.trailing !== ""
        text: row.trailing
        color: Qt.darker(row.foreground, 1.4)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // BarIconButton already renders `text` through an anchors.filled
    // OpticalGlyph, coloured from bar.barForeground with the bar's own colour
    // animation (Ui/BarIconButton.qml:29-39). The hand-built iconComponent
    // this replaces centred a glyph in a zero-sized Item, opted out of the
    // active-state colouring and the theme transition, and sized off
    // Style.font.icon rather than the bar's Style.bar.iconFont. Every
    // first-party bar widget just sets text.
    // Not the monitor glyph: omarchy.monitor uses U+F037A for a multi-screen
    // desk, so the two icons were identical side by side. Swap arrows say
    // what this does - move the screens - and nothing else on the bar uses it.
    text: "󰓡"
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
      // Stand down while the confirmation owns the keyboard, otherwise Esc
      // closes the panel out from under a dialog that should have cancelled.
      blocked: root.confirmOpen
      onCloseRequested: root.close()

      ColumnLayout {
        id: column
        anchors.fill: parent
        spacing: Style.space(4)

        PanelSectionHeader { text: "Send my screens to" }

        // A screen the desk has never seen. The desk still resolves (on
        // purpose - see the engine's `unmapped`), but a switch leaves this
        // screen where it is. Say so here, before the click, not after.
        RowLayout {
          Layout.fillWidth: true
          visible: root.submenuSerial === "" && root.deskState.known && root.deskState.unmapped.length > 0
          spacing: Style.space(8)
          Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: root.deskState.unmapped.length === 1
                  ? "1 screen here isn't set up. It will stay where it is."
                  : root.deskState.unmapped.length + " screens here aren't set up. They will stay where they are."
            color: Color.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          Button {
            text: "Set up"
            onClicked: {
              root.close()
              if (setupLoader.active && setupLoader.item) setupLoader.item.open()
              else setupLoader.active = true
            }
          }
        }

        Repeater {
          model: root.submenuSerial === "" ? root.deskState.computers : []
          delegate: MenuRow {
            required property var modelData
            Layout.fillWidth: true
            enabled: !root.busy
            label: modelData.label
            current: modelData.id === root.deskState.current
            trailing: current ? "here now" : ""
            icon: "\u{f0379}"
            onActivated: root.sendTo(modelData.id)
          }
        }

        // Monitor picker: which screen, then which computer for that screen.
        Repeater {
          model: root.submenuSerial === "monitors" ? root.deskState.monitors : []
          delegate: MenuRow {
            required property var modelData
            Layout.fillWidth: true
            label: modelData.label
            trailing: "\u{f0142}"
            onActivated: root.submenuSerial = modelData.serial
          }
        }

        Repeater {
          model: (root.submenuSerial !== "" && root.submenuSerial !== "monitors")
                 ? root.deskState.computers : []
          delegate: MenuRow {
            required property var modelData
            Layout.fillWidth: true
            enabled: !root.busy
            label: modelData.label
            icon: "\u{f0379}"
            onActivated: root.sendMonitorTo(root.submenuSerial, modelData.id)
          }
        }

        PanelSeparator { Layout.fillWidth: true; foreground: root.barForeground }

        MenuRow {
          Layout.fillWidth: true
          visible: root.submenuSerial === "" && root.deskState.monitors.length > 1
          label: "Just one screen"
          trailing: "\u{f0142}"
          onActivated: root.submenuSerial = "monitors"
        }

        MenuRow {
          Layout.fillWidth: true
          visible: root.submenuSerial !== ""
          icon: "\u{f0141}"
          label: "Back"
          onActivated: root.submenuSerial = (root.submenuSerial === "monitors" ? "" : "monitors")
        }

        MenuRow {
          Layout.fillWidth: true
          icon: "\u{f0493}"
          label: root.deskState.known ? "Set up this desk" : "Set up this desk"
          dim: true
          onActivated: {
            root.close()
            if (setupLoader.active && setupLoader.item) setupLoader.item.open()
            else setupLoader.active = true
          }
        }
      }

      // ConfirmDialog has no focus of its own - Ui/ConfirmDialog.qml:23 exposes
      // handleKey(event) and expects the parent to route keys into it, which
      // is what clipboard and menu do. Without this the dialog is mouse-only:
      // Enter and the arrows do nothing, and Esc closes the whole panel
      // instead of cancelling. PanelKeyCatcher sees keys first, so this takes
      // focus while the dialog is up and hands it straight back after.
      Item {
        id: confirmKeys
        anchors.fill: parent
        z: 11
        visible: root.confirmOpen
        onVisibleChanged: if (visible) forceActiveFocus(); else keyCatcher.forceActiveFocus()
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (confirm.handleKey(event)) event.accepted = true
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
    onStatusChanged: {
      if (status === Loader.Error) {
        notifyProc.command = ["notify-send", "Screen Push",
                              "The setup screen failed to load. See: journalctl --user -b | grep screenpush"]
        notifyProc.running = true
        active = false
      }
    }
    onLoaded: {
      item.engine = root.engine
      // KeyboardPanel positions itself against the bar icon, so Setup needs
      // both the anchor and the bar host. Without them it warns and never
      // builds, which reads as "the button does nothing".
      item.anchorItem = button
      item.bar = root.bar
      // Deliberately NOT deactivating the Loader here. active = false destroys
      // the item and every property on it, which is the whole half-filled
      // grid. Closing hides the card; the draft stays in memory for the next
      // open. It costs one idle QML object and saves the person's work.
      item.closed.connect(function() { root.refresh() })
      item.open()
    }
  }
}
