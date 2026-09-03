# Screen Push - agent instructions

Durable rules only. Anything discoverable from the repo (structure, commands,
manifest fields) lives in the repo, not here.

## What this is

An Omarchy 4 (Quattro) shell plugin: a bar widget that pushes every monitor on
a desk to another computer over DDC/CI. `bin/screenpush` is the engine (bash
around `ddcutil`); `Panel.qml` is the bar icon and menu; `Setup.qml` the setup
sheet; `TryController.qml` the "try it" state. It is published as
`io.github.steveclarke.screenpush` and that id is permanent once listed.

## Never touch the real monitors from an agent

`ddcutil setvcp`, `screenpush switch`, `switch-raw` and `save-desk` change the
physical inputs of the screens this session is displayed on. Never run them
against real hardware. `detect`, `state` and `getvcp` are read-only and fine.
The tests use `test/stub/ddcutil` and never reach hardware; keep it that way.

## Gates - run all three before every commit

    tools/lint-qml Panel.qml Setup.qml TryController.qml
    bats test/screenpush.bats
    omarchy plugin validate .

`tools/lint-qml` is not plain qmllint. It builds the `qs/` namespace qmllint
needs, denies "no matching signal found for handler" (a handler for a signal
the type lacks makes the whole widget fail to load), and runs
`tools/check-required-props` because qmllint 6.11 silently skips the
`[required]` check for any object holding a Repeater or inline Component - the
exact hole that shipped a setup sheet that never appeared. A deliberately
broken fixture in `test/fixtures/` proves the check is alive on every run.

Every new regression test must be shown to fail against the old code before it
is trusted. This repo has had tests that passed for the wrong reason.

## Verify the UI yourself

Do not make the user click things to find out whether they render. Drive it:

    omarchy-shell screenpush open|toggle|setup
    grim -o <output> shot.png            # then crop and look

Check `journalctl --user -b` for `Plugin widget ... failed`, `Required property
... was not initialized` and `Binding loop` after every load. The symptom of
four different defects (zero implicit size, an unset required property, a
bad signal handler, a wrong manifest id) is the same: nothing appears. Read
the log before guessing.

`IpcHandler ... another handler is registered for target screenpush` is
benign: one bar instance exists per monitor. Every first-party widget logs it.

## Install model

The installed copy at `~/.config/omarchy/plugins/io.github.steveclarke.screenpush/`
is a git clone, not a link to this checkout. To test a change: commit, push,
`omarchy plugin update`. Hot reload picks up file edits but keeps stale glyphs
and IPC methods - after changing either, `omarchy-restart-shell`.

Copying files straight into the plugin folder is fine for a quick look but
leaves the clone dirty; prefer the update path.

## Contract with the shell, learned the hard way

- The bar sizes a widget from its root's `implicitWidth`/`implicitHeight`.
  Without them the slot is 0x0: loaded, running, unclickable, invisible.
- `KeyboardPanel` requires `anchorItem` and `bar`. Unset, it never instantiates.
- A `Loader`-hosted panel must expose `close()`; `KeyboardPanel.close()` and
  `Bar.requestPopout()` both look for it by name.
- Never bind `text:` to a model the handler writes back; seed in
  `Component.onCompleted` and use `onTextEdited`.
- `Panel` has no `broadcast()`. Refreshes must fan out to every screen's
  instance via `bar.moduleWidgets(moduleName)`; side effects must not.
- Hotkeys call the engine directly, not IPC, so they work with the shell down.
  The shell-routed form `omarchy-shell shell toggle <plugin-id>` opens on the
  focused screen; `omarchy-shell screenpush toggle` opens on an arbitrary one.

## Privacy

This repo is public. No monitor serials, hostnames, LAN addresses or personal
details in any committed file, test fixture, screenshot or preview image, and
none in git history. Fixtures use invented serials like `AAA0001`.

## Publishing

Listing on plugins.omarchy.org requires the owner to confirm the submission
checklist and see the exact issue text before an agent files it. Never submit
on the owner's behalf. Keep the README's install and removal sections and its
"No sudo or pkexec is required" line - the marketplace scans for both.

## Commits

No AI attribution lines. `master`, not `main`.
