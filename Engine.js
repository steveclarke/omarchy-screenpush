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
  var empty = { deskKey: "", label: "", known: false, computers: [], current: null, monitors: [], unmapped: [], live: {}, hint: "" }
  if (!text) return empty
  try {
    var parsed = JSON.parse(text)
    return {
      deskKey: String(parsed.deskKey || ""),
      label: plain(parsed.label || ""),
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


// Which computer each screen is showing, in the desk's own left-to-right order.
// A screen whose live input matches no computer was switched by its own front
// panel; it is neither here nor on a computer we know, so it says so.
function screenViews(state) {
  var out = []
  for (var i = 0; i < state.monitors.length; i++) {
    var m = state.monitors[i]
    var live = state.live[m.serial] || ""
    var who = null
    for (var j = 0; j < state.computers.length; j++) {
      var inputs = state.computers[j].inputs || {}
      if (live !== "" && inputs[m.serial] === live) { who = state.computers[j]; break }
    }
    var unmapped = state.unmapped.indexOf(m.serial) !== -1
    out.push({
      serial: m.serial,
      label: plain(m.label),
      computerId: who ? String(who.id) : "",
      computerLabel: who ? plain(who.label) : (unmapped ? "Not set up" : "Another input"),
      here: who ? who.id === "this" : false,
      known: who !== null,
      unmapped: unmapped
    })
  }
  return out
}

// A click on a screen sends it to the next computer in the desk's own order,
// so the common two-computer desk is a straight there-and-back toggle.
function nextComputer(state, currentId) {
  var ids = []
  for (var i = 0; i < state.computers.length; i++) ids.push(String(state.computers[i].id))
  if (ids.length === 0) return ""
  var at = ids.indexOf(String(currentId))
  return ids[(at + 1) % ids.length]
}

function labelOf(state, computerId) {
  for (var i = 0; i < state.computers.length; i++) {
    if (String(state.computers[i].id) === String(computerId)) return plain(state.computers[i].label)
  }
  return plain(computerId)
}

function countWord(n, one, many) { return n === 1 ? one : String(n) + " " + many }

// The hero's title, meta line, detail and tone, derived from the desk alone so
// the panel never decides what state it is in.
function hero(state, views, ctx) {
  var c = ctx || {}
  var desk = state.label !== "" ? state.label : "This desk"
  if (c.unreachable) {
    return { title: labelOf(state, c.unreachable) + " isn't answering",
             meta: desk + " \u00b7 nothing has moved", detail: "It may be off or asleep", tone: "urgent" }
  }
  if (c.busy) {
    var target = labelOf(state, c.sendingTo)
    if (c.sendingSerial) {
      var name = "the screen"
      for (var i = 0; i < views.length; i++) if (views[i].serial === c.sendingSerial) name = views[i].label.toLowerCase()
      return { title: "Sending " + name + "\u2026", meta: "sending " + name + " to " + target,
               detail: "Takes a few seconds", tone: "accent" }
    }
    return { title: "Sending every screen\u2026", meta: "sending every screen to " + target,
             detail: "Takes a few seconds", tone: "accent" }
  }
  if (!state.known) {
    return { title: c.loading ? "Looking for your screens\u2026" : "This desk isn't set up",
             meta: "Screen Push \u00b7 " + countWord(state.monitors.length, "1 screen", "screens") + " found",
             detail: c.loading ? "" : "Three steps and it's done", tone: "dim" }
  }
  var unmapped = 0
  for (var u = 0; u < views.length; u++) if (views[u].unmapped) unmapped++
  var counts = desk + " \u00b7 " + countWord(views.length, "1 screen", "screens")
  if (unmapped > 0) {
    return { title: unmapped === 1 ? "One screen isn't set up" : String(unmapped) + " screens aren't set up",
             meta: counts, detail: unmapped === 1 ? "It will stay where it is" : "They will stay where they are",
             tone: "urgent" }
  }
  var first = views.length > 0 ? views[0].computerId : ""
  var same = views.length > 0
  for (var v = 0; v < views.length; v++) if (views[v].computerId !== first) same = false
  var hint = views.length > 1 ? "Click a screen to send just that one" : ""
  if (same && first !== "") {
    var here = first === "this"
    return { title: "Screens are on " + labelOf(state, first), meta: counts,
             detail: here ? hint : (views.length > 1 ? "Click a screen to bring just that one back" : ""),
             tone: here ? "normal" : "dim" }
  }
  return { title: "Screens are split", meta: counts, detail: hint, tone: "normal" }
}
