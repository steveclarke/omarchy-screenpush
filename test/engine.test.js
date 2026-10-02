// Desk-state parsing in Engine.js. Engine.js is a QML JavaScript resource, not
// a module, so it is loaded into a function scope and its functions read back.
const { test } = require("node:test")
const assert = require("node:assert")
const fs = require("fs")
const path = require("path")

const src = fs.readFileSync(path.join(__dirname, "..", "Engine.js"), "utf8")
const E = new Function(src + "\nreturn { parseState, parseDetect, screenViews, barLabel, prefs }")()

const desk = {
  known: true, label: "Desk",
  computers: [{ id: "this", label: "Mine", inputs: { A: "0x0f" } },
              { id: "mac", label: "<b>Mac</b>", host: "192.0.2.10", inputs: { A: "0x11" } }],
  monitors: [{ serial: "A", label: "Left" }], unmapped: ["B"], live: { A: "0x0f" }
}

test("a good desk parses and names are stripped of markup when shown", () => {
  const s = E.parseState(JSON.stringify(desk))
  assert.strictEqual(s.known, true)
  assert.strictEqual(s.computers[1].host, "192.0.2.10")
  const v = E.screenViews(s)
  assert.strictEqual(v[0].computerId, "this")
  assert.strictEqual(E.barLabel(s, v), "Mine")
})

test("a screen the desk has never seen shows as a new screen", () => {
  const v = E.screenViews(E.parseState(JSON.stringify(desk)))
  assert.strictEqual(v.length, 2)
  assert.deepStrictEqual([v[1].serial, v[1].unmapped, v[1].label], ["B", true, "New screen"])
})

test("__proto__ is an ordinary serial", () => {
  const s = E.parseState(JSON.stringify({ known: true,
    computers: [{ id: "a", inputs: { ["__proto__"]: "0x0f" } }],
    monitors: [{ serial: "__proto__" }], live: JSON.parse('{"__proto__":"0x11"}') }))
  const v = E.screenViews(s)
  assert.strictEqual(v[0].known, false)
})

test("documents outside the limits are refused whole", () => {
  const bad = [
    "[]", "null", "42", "not json",
    JSON.stringify({ known: true, computers: Array(17).fill({ id: "x" }) }),
    JSON.stringify({ known: true, computers: [null] }),
    JSON.stringify({ known: true, computers: [{ id: 7 }] }),
    JSON.stringify({ known: true, computers: [{ id: "a", label: { x: 1 } }] }),
    JSON.stringify({ known: true, computers: [{ id: "a".repeat(65) }] }),
    JSON.stringify({ known: true, monitors: [{ serial: "A", label: "x".repeat(65) }] }),
    JSON.stringify({ known: true, live: { A: 15 } })
  ]
  for (const t of bad) {
    const s = E.parseState(t)
    assert.strictEqual(s.known, false, t)
    assert.strictEqual(s.computers.length, 0, t)
  }
})

test("detect output is bounded the same way", () => {
  const ok = E.parseDetect(JSON.stringify({ monitors: [{ serial: "A", model: "<i>M</i>", inputs: ["0x0f"] }] }))
  assert.strictEqual(ok.monitors[0].model, "iM/i")
  const tooMany = E.parseDetect(JSON.stringify({ monitors: [{ serial: "A", inputs: Array(33).fill("0x0f") }] }))
  assert.strictEqual(tooMany.monitors.length, 0)
})

test("settings read strings and booleans alike", () => {
  assert.strictEqual(E.prefs({ notifyAfterSwitch: "false" }).notifyAfterSwitch, false)
  assert.strictEqual(E.prefs({ notifyAfterSwitch: false }).notifyAfterSwitch, false)
  assert.strictEqual(E.prefs({}).askWhenUnreachable, true)
  assert.strictEqual(E.prefs({ barText: "<x>" }).barText, "none")
})
