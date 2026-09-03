# Screen Push - agent rules

Omarchy 4 bar-widget plugin. `bin/screenpush` (bash + ddcutil) is the engine;
the QML is the UI. Plugin id `io.github.steveclarke.screenpush` is permanent.

## Never run against real monitors

`ddcutil setvcp`, `screenpush switch`, `switch-raw`, `save-desk`. They change
the inputs of the screens this session is on. `detect`, `state`, `getvcp` are
read-only. Tests use `test/stub/ddcutil`; keep it that way.

## Gates, before every commit

    tools/lint-qml Panel.qml Setup.qml TryController.qml
    bats test/screenpush.bats
    omarchy plugin validate .

Use `tools/lint-qml`, not bare qmllint: qmllint cannot resolve `qs.*` from the
shell root and skips the `[required]` check on any object containing a
Repeater. A new regression test must be shown failing on the old code first.

## Verify UI yourself

`omarchy-shell screenpush open|toggle|setup`, then `grim -o <output>` and look.
Then check `journalctl --user -b` for `Plugin widget ... failed`,
`Required property`, `Binding loop`. A widget that renders nothing has four
possible causes with one symptom; read the log before guessing.
`IpcHandler ... another handler is registered` is benign (one bar per monitor).

## Install model

`~/.config/omarchy/plugins/io.github.steveclarke.screenpush/` is a git clone,
not a link. Commit, push, `omarchy plugin update`. Hot reload keeps stale
glyphs and IPC methods; `omarchy-restart-shell` after changing either.

## Non-obvious shell contract

- Root must set `implicitWidth`/`implicitHeight` or the bar slot is 0x0.
- `KeyboardPanel` requires `anchorItem` and `bar`.
- A Loader-hosted panel must define `close()`; the shell calls it by name.
- `Panel` has no `broadcast()`; refreshes fan out via `bar.moduleWidgets()`,
  side effects must not.
- Hotkeys call the engine directly (works with the shell down).

## Public repo

No serials, hostnames, LAN addresses or personal details in files, fixtures,
screenshots or history. Fixture serials look like `AAA0001`.

Never file the marketplace submission; the owner does that.
No AI attribution in commits. `master`, not `main`.
