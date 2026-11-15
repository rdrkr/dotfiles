-- Rex configuration, migrated from tmux (~/.config/tmux/tmux.conf) and
-- Ghostty (~/.config/ghostty/config).

--- shift+enter sends alt+enter (ESC CR) to the program in the pane,
--- as Ghostty's `keybind = shift+enter=text:\x1b\r` did (config:55).
rex.bind("shift+enter", "pane.send_key", { key = "alt+enter" })
