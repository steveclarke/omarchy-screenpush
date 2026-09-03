// Turns engine JSON into plain objects for the QML layer. No UI, no Process.

// The engine ships inside the plugin folder, which can be anywhere the user
// cloned it, so the path is resolved relative to this file rather than
// assumed. Qt hands back a file:// URL; Process wants a filesystem path.
function enginePath(resolveUrl) {
  return String(resolveUrl("bin/screenpush")).replace(/^file:\/\//, "")
}

function parseState(text) {
  var empty = { deskKey: "", known: false, computers: [], current: null, monitors: [], unmapped: [] }
  if (!text) return empty
  try {
    var parsed = JSON.parse(text)
    return {
      deskKey: String(parsed.deskKey || ""),
      known: parsed.known === true,
      computers: Array.isArray(parsed.computers) ? parsed.computers : [],
      current: parsed.current === null ? null : String(parsed.current),
      monitors: Array.isArray(parsed.monitors) ? parsed.monitors : [],
      unmapped: Array.isArray(parsed.unmapped) ? parsed.unmapped : []
    }
  } catch (e) {
    return empty
  }
}
