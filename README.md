# Screen Push

Push every screen on your desk to another computer in one click.

If your screens are cabled to more than one computer, switching between them
means pressing buttons on each screen's own menu, one screen at a time.
Screen Push puts a menu in the Omarchy bar that lists your computers. Pick one
and every screen on the desk switches to it, over DDC/CI. Press a key on the
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
send a single screen, use **Send one screen**.

If the computer you are sending to has a hostname recorded, it is pinged
first, and you are asked before the screens go to a computer that is not
answering.

### Hotkeys

The other computers need a way to bring the screens back. On another Omarchy
computer with this plugin, bind a key to the engine directly, so it works when
the shell is not running and with nothing on screen:

    ~/.config/omarchy/plugins/io.github.steveclarke.screenpush/bin/screenpush switch this

Any computer id from desk setup works in place of `this`. On a Mac or
Windows computer, any tool that can send DDC/CI input codes will do the same
job for the return trip.

To open the menu, the single-screen picker, or desk setup from a key:

    omarchy-shell shell toggle io.github.steveclarke.screenpush
    omarchy-shell screenpush screens
    omarchy-shell screenpush setup

## Remove

    omarchy plugin remove io.github.steveclarke.screenpush

Your desk file stays in `~/.config/screenpush/`; delete it if you want a
clean slate.

## How it works

`bin/screenpush` is a bash script around `ddcutil`. It reads each screen's
input capabilities, refuses any code a screen does not report, and checks
that every screen answers before moving any of them, so a fault cannot leave
the desk half switched. The bar widget and desk setup are QML on Omarchy's
own panel components.

## Development

    bats test/screenpush.bats      # engine tests, against a fake ddcutil
    tools/lint-qml *.qml           # QML against the installed shell modules
    omarchy plugin validate .

Tests never touch real screens.

## License

MIT - see [LICENSE](LICENSE).
