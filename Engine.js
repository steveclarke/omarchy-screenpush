// Turns engine JSON into plain objects for the QML layer. No UI, no Process.

// The engine ships inside the plugin folder, which can be anywhere the user
// cloned it, so the path is resolved relative to this file rather than
// assumed. Qt hands back a file:// URL; Process wants a filesystem path.
function enginePath(resolveUrl) {
  return String(resolveUrl("bin/screenpush")).replace(/^file:\/\//, "")
}

// Titles, headers, tooltips and notification bodies are rendered by the shell
// with markup-capable components a plugin cannot pin to plain text. Computer and
// screen names come from the person's own config and from the monitor itself.
function plain(value) {
  return String(value === undefined || value === null ? "" : value)
    .replace(/[<>&\u0000-\u001f\u007f-\u009f\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, "")
    .slice(0, 120)
}

function parseState(text) {
  var empty = { deskKey: "", known: false, computers: [], current: null, monitors: [], unmapped: [], live: {}, hint: "" }
  if (!text) return empty
  try {
    var parsed = JSON.parse(text)
    return {
      deskKey: String(parsed.deskKey || ""),
      known: parsed.known === true,
      computers: Array.isArray(parsed.computers) ? parsed.computers : [],
      current: parsed.current === null ? null : String(parsed.current),
      monitors: Array.isArray(parsed.monitors) ? parsed.monitors : [],
      unmapped: Array.isArray(parsed.unmapped) ? parsed.unmapped : [],
      live: (parsed.live && typeof parsed.live === "object") ? parsed.live : {},
      hint: String(parsed.hint || "")
    }
  } catch (e) {
    return empty
  }
}
