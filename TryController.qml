import QtQuick
import Quickshell
import Quickshell.Io

// Owns one in-flight "Try it": which screen was moved, what it showed before,
// how to put it back, and what to tell the sheet about it.
Item {
  id: root

  property string engine: ""
  property int monitorCount: 0

  // Empty while nothing is being tried. Keyed by computer id, not column:
  // removing a computer above the tried one must not move the indicator.
  property string serial: ""
  property string computerId: ""
  property string previousCode: ""
  property string code: ""
  property bool busy: false
  property string error: ""

  // Seconds left before a one-screen desk brings itself back.
  property int remaining: 0

  readonly property bool trying: serial !== ""

  function isTrying(targetSerial, targetComputerId) {
    return trying && serial === targetSerial && computerId === targetComputerId
  }

  // Pressing Try on the cell being tried brings it back. Pressing Try on a
  // different cell while one is out reverts that one first, then tries the
  // new one, rather than silently doing only the revert.
  function toggle(targetSerial, targetComputerId, targetCode) {
    if (busy) return
    error = ""
    if (isTrying(targetSerial, targetComputerId)) { revert(); return }
    if (!targetSerial || !targetCode) return
    if (trying) {
      queued = { serial: targetSerial, computerId: targetComputerId, code: targetCode }
      revert()
      return
    }
    start(targetSerial, targetComputerId, targetCode)
  }

  property var queued: null

  function start(targetSerial, targetComputerId, targetCode) {
    busy = true
    root.serial = targetSerial
    root.computerId = targetComputerId
    root.code = targetCode
    readProc.command = [root.engine, "state"]
    readProc.running = true
  }

  function revert() {
    if (!trying || previousCode === "") { clear(); return }
    busy = true
    revertProc.command = [root.engine, "switch-raw", serial, previousCode]
    revertProc.running = true
  }

  function clear() {
    autoRevert.stop()
    countdown.stop()
    serial = ""
    computerId = ""
    previousCode = ""
    code = ""
    remaining = 0
    busy = false
    if (queued) { var q = queued; queued = null; start(q.serial, q.computerId, q.code) }
  }

  Process {
    id: readProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var live = {}
        try { live = (JSON.parse(String(text || "")).live) || {} } catch (e) { live = {} }
        root.previousCode = live[root.serial] !== undefined ? live[root.serial] : ""
        if (root.previousCode === "") { root.error = "That screen isn't answering, so it wasn't tried."; root.clear(); return }
        applyProc.command = [root.engine, "switch-raw", root.serial, root.code]
        applyProc.running = true
      }
    }
  }

  Process {
    id: applyProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: applyStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.busy = false
      if (exitCode !== 0) { root.error = String(applyStderr.text || "").trim(); root.clear(); return }
      // Only a one-screen desk needs the timer: with a second screen the
      // sheet is still visible and Bring it back is right there.
      if (root.monitorCount <= 1) { root.remaining = 15; autoRevert.restart(); countdown.restart() }
    }
  }

  Process {
    id: revertProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: revertStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.error = "Couldn't bring the screen back. Use its own menu to switch it."
      root.clear()
    }
  }

  Timer { id: autoRevert; interval: 15000; repeat: false; onTriggered: root.revert() }
  Timer {
    id: countdown
    interval: 1000
    repeat: true
    onTriggered: root.remaining = Math.max(0, root.remaining - 1)
  }
}
