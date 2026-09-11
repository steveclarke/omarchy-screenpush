import Quickshell.Io

// Collects a child process's output with a byte ceiling, in place of
// StdioCollector, which keeps whatever the child writes before any check can
// run. Raw chunks, not lines: a line parser must buffer to the newline first,
// which is the same unbounded problem one layer down.
SplitParser {
  id: root
  property int maxBytes: 262144
  property string text: ""
  property bool overflowed: false
  signal overflow()

  function reset() { text = ""; overflowed = false }

  splitMarker: ""
  onRead: function(chunk) {
    if (overflowed) return
    if (text.length + chunk.length > maxBytes) {
      overflowed = true
      text = ""
      root.overflow()
      return
    }
    text += chunk
  }
}
