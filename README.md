# Screen Push

Push every screen on your desk to another computer in one click.

If your monitors are cabled to more than one machine, switching between them
means pressing buttons on each monitor's own menu, one monitor at a time.
Screen Push puts a menu in the Omarchy bar that lists your computers. Pick one
and every screen on the desk switches to it, over DDC/CI. Press a key on the
other machine and they come back.

It pushes rather than pulls: you tell the machine you are *leaving* where to
send the screens. Tools that only "bring my screens here" have to be run from
the machine that doesn't have them yet.

## Requirements

- Omarchy 4 (Quattro) - this is a shell plugin, not a standalone app
- `ddcutil` - `sudo pacman -S ddcutil`
- Your user in the `i2c` group, so `ddcutil` can talk to the monitors:

      sudo usermod -aG i2c "$USER"

  then log out and back in. No sudo or pkexec is required after that; the
  plugin never elevates.
- Monitors with DDC/CI enabled (it is often off by default, in the monitor's
  own menu) and cabled to two or more computers

Screen Push only switches the monitors. It does not move a keyboard or mouse.
Each computer needs its own, or a separate USB switch.

## Install

    omarchy plugin add https://github.com/steveclarke/omarchy-screenpush.git --enable

A swap-arrows icon appears in the bar. Click it, choose **Set up this desk**,
name your computers and pick which input each screen shows for each of them.
**Try it** switches a screen right now so you can check a cable before saving.

The desk is identified by the serial numbers of the monitors present, so a
laptop that moves between desks gets a separate setup for each, and a monitor
switched off at the wall does not lose the desk.

## Use

Click the icon and pick a computer. Every screen on the desk goes there. To
send just one screen, use **Just one screen**.

If the computer you are sending to has a hostname recorded, it is pinged
first, and you are asked before the screens go to a machine that is not
answering.

### Hotkeys

The other computers need a way to bring the screens back. On another Omarchy
machine with this plugin, bind a key to the engine directly, so it works when
the shell is not running and with nothing on screen:

    ~/.config/omarchy/plugins/io.github.steveclarke.screenpush/bin/screenpush switch this

Any computer id from the setup sheet works in place of `this`. On a Mac or
Windows machine, any tool that can send DDC/CI input codes will do the same
job for the return trip.

To open the menu or the setup sheet from a key:

    omarchy-shell shell toggle io.github.steveclarke.screenpush
    omarchy-shell screenpush setup

## Remove

    omarchy plugin remove io.github.steveclarke.screenpush

Your desk file stays in `~/.config/screenpush/`; delete it if you want a
clean slate.

## How it works

`bin/screenpush` is a bash script around `ddcutil`. It reads each monitor's
input capabilities, refuses any code a monitor does not report, and checks
that every monitor answers before moving any of them, so a fault cannot leave
the desk half switched. The bar widget and setup sheet are QML on Omarchy's
own panel components.

## Development

    bats test/screenpush.bats      # engine tests, against a fake ddcutil
    tools/lint-qml *.qml           # QML against the installed shell modules
    omarchy plugin validate .

Tests never touch real monitors.

## License

MIT - see [LICENSE](LICENSE).
