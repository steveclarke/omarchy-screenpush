# Screen Push

Push every screen on your desk to another computer in one click.

If your screens are cabled to more than one computer, switching between them
means pressing buttons on each screen's own menu, one screen at a time.
Screen Push puts a panel in the Omarchy bar with a picture of your desk and a
list of your computers. Pick a computer and every screen on the desk switches
to it, over DDC/CI. Press a key on the
other computer and they come back.

It pushes rather than pulls: you tell the computer you are *leaving* where to
send the screens. Tools that only "bring my screens here" have to be run from
the computer that doesn't have them yet.

## Requirements

- Omarchy 4 (Quattro) - this is a shell plugin, not a standalone app
- `ddcutil` - `sudo pacman -S ddcutil`
- Your user in the `i2c` group, so `ddcutil` can talk to the screens:

      sudo usermod -aG i2c "$USER"

  then log out and back in. No sudo or pkexec is required after that; the
  plugin never elevates.
- Screens with DDC/CI enabled (it is often off by default, in the screen's
  own menu) and cabled to two or more computers

Screen Push only switches the screens. It does not move a keyboard or mouse.
Each computer needs its own, or a separate USB switch.

## Install

    omarchy plugin add https://github.com/steveclarke/omarchy-screenpush.git --enable

A swap-arrows icon appears in the bar. Click it, choose **Set up this desk**,
name your computers and pick which input each screen shows for each of them.
**Try it** switches a screen right now so you can check a cable, and brings it
back when pressed again.

The desk is identified by the serial numbers of the screens present, so a
laptop that moves between desks gets a separate setup for each, and a screen
switched off at the wall does not lose the desk.

## Use

Click the icon and pick a computer. Every screen on the desk goes there. To
send a single screen, click it in the desk picture; it goes to the next
computer in the desk's order, so on a two-computer desk each click is a
there-and-back toggle. A screen plugged in that the desk has not been set up
for shows as **New screen**, stays put on every send, and opens setup when
clicked.

If the computer you are sending to has a hostname recorded, it is pinged
first. With **Ask before sending to a computer that isn't answering** on (the
default), you are asked before the screens go to a computer that does not
answer; with it off, they are sent straight away.

### Settings

Desk setup has three settings:

- **Bar shows** - the icon only (default), or the icon and the name of the
  computer the screens are on.
- **Notify after switching** - on by default. A desktop notification, through
  `notify-send`, when every screen moves to another computer.
- **Ask before sending to a computer that isn't answering** - on by default.

They are saved, when **Save** is pressed, in this widget's entry in
`~/.config/omarchy/shell.json`, through the shell's own settings call.

### Hotkeys

The other computers need a way to bring the screens back. On another Omarchy
computer with this plugin, bind a key to the engine directly, so it works when
the shell is not running and with nothing on screen:

    ~/.config/omarchy/plugins/io.github.steveclarke.screenpush/bin/screenpush switch this

Any computer id from desk setup works in place of `this`. On a Mac or
Windows computer, any tool that can send DDC/CI input codes will do the same
job for the return trip.

To open the panel or desk setup from a key:

    omarchy-shell shell toggle io.github.steveclarke.screenpush
    omarchy-shell screenpush setup

## Remove

    omarchy plugin remove io.github.steveclarke.screenpush

Your desk file stays in `screenpush/` under your config directory
(`~/.config/screenpush/` by default); delete it if you want a clean slate.
The bar settings are part of the bar layout in `~/.config/omarchy/shell.json`,
which Omarchy owns and handles on removal. Screen Push writes nothing else.

## How it works

`bin/screenpush` is a bash script around `ddcutil`. It reads each screen's
input capabilities, refuses any code a screen does not report, and checks
that every screen answers before moving any of them, so a fault cannot leave
the desk half switched. The bar widget and desk setup are QML on Omarchy's
own panel components.

Screens are found from the kernel's display connectors, not by `ddcutil detect`,
and every `ddcutil` call names the one I2C bus that reaches its screen. A scan
opens every bus on the machine, and on AMD RDNA4 cards (RX 9070, Radeon AI PRO
R9700) two of those belong to the card's power controller; probing them
crashes the card. Screen Push never opens a bus the kernel names `AMDGPU SMU`.

The desk file is read and written only by `lib/deskfile.py`, through
descriptors checked for ownership. Starting at the passwd home, it walks
`.config` or an absolute `XDG_CONFIG_HOME` beneath that home one directory at
a time and refuses symlinks or directories owned by someone else. It creates
only a missing default `.config`; a missing custom config directory is refused.
It also refuses a symlinked or hard-linked `desks.json`, or one writable by
others, and saves by renaming a fresh owner-only file into place. After a
save, it checks that the home, config path, and `screenpush` directory still
resolve to the same directories.

## Development

    bats test/screenpush.bats      # engine tests, against a fake ddcutil
    node --test test/engine.test.js # desk-state parsing in Engine.js
    tools/lint-qml *.qml           # QML against the installed shell modules
    omarchy plugin validate .

Tests never touch real screens.

## License

MIT - see [LICENSE](LICENSE).
