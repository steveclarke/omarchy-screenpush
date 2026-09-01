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
    onRunningChanged: if (!running) root.clear()
  }

  Timer {
    id: autoRevert
    interval: 15000
    repeat: false
    onTriggered: root.revert()
  }
}
