import QtQuick
import Quickshell
import Quickshell.Io

// Owns one in-flight "Try it": which panel was moved, what it was showing
// before, and how to put it back.
Item {
  id: root

  property string engine: ""
  property int monitorCount: 0

  // Empty while nothing is being tried.
  property string serial: ""
  property int column: -1
  property string previousCode: ""

  readonly property bool trying: serial !== ""

  function toggle(targetSerial, targetColumn, code) {
    if (trying) { revert(); return }
    if (!targetSerial || !code) return
    root.serial = targetSerial
    root.column = targetColumn
    readProc.command = [root.engine, "state"]
    readProc.pendingCode = code
    readProc.running = true
  }

  function revert() {
    if (!trying || previousCode === "") { clear(); return }
    revertProc.command = [root.engine, "switch-raw", serial, previousCode]
    revertProc.running = true
  }

  function clear() {
    autoRevert.stop()
    serial = ""
    column = -1
    previousCode = ""
  }

  Process {
    id: readProc
    property string pendingCode: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var live = {}
        try { live = (JSON.parse(String(text || "")).live) || {} } catch (e) { live = {} }
        root.previousCode = live[root.serial] !== undefined ? live[root.serial] : ""
        if (root.previousCode === "") { root.clear(); return }
        applyProc.command = [root.engine, "switch-raw", root.serial, readProc.pendingCode]
        applyProc.running = true
      }
    }
  }

  Process {
    id: applyProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: applyStderr; waitForEnd: true }
    // A refused switch-raw - a stale code, a sleeping monitor, DDC/CI turned
    // off in the monitor's own menu - exited silently, and the button then sat
    // there offering to bring back a screen that never moved. Say so instead.
    onExited: function(exitCode) {
      if (exitCode === 0) return
      root.clear()
      notifyProc.command = ["notify-send", "Monitor Input", String(applyStderr.text || "").trim()]
      notifyProc.running = true
    }
    onRunningChanged: {
      if (running) return
      // Only a single-monitor desk needs the timer. With a second screen the
      // grid is still visible and the person can press Bring it back, which
      // is a better experience than a countdown they have to beat.
      if (root.monitorCount <= 1) autoRevert.restart()
    }
  }

  Process {
    id: revertProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: revertStderr; waitForEnd: true }
    // Failing to revert is the worse half of the pair: the screen is sitting
    // on the input we moved it to and the person is looking at another machine.
    onExited: function(exitCode) {
      if (exitCode === 0) return
      notifyProc.command = ["notify-send", "Monitor Input",
                            "Could not bring the screen back: " + String(revertStderr.text || "").trim()]
      notifyProc.running = true
    }
    onRunningChanged: if (!running) root.clear()
  }

  Process { id: notifyProc }

  Timer {
    id: autoRevert
    interval: 15000
    repeat: false
    onTriggered: root.revert()
  }
}
