## Hotkeys

Any computer can have its own key. The ids are the `id` fields in
`~/.config/monitor-input/desks.json`:

    bindd = SUPER SHIFT, H, Screens to this machine, exec, ~/.local/bin/monitor-input switch this
    bindd = SUPER SHIFT, J, Screens to the laptop,   exec, ~/.local/bin/monitor-input switch laptop

These call the script directly, so they keep working when the shell is not
running. Nothing requires a hotkey; the menu does the same thing.
