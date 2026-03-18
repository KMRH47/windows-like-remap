# Windows-like Remap

Hammerspoon configuration to make macOS keyboard shortcuts feel like Windows.

## Features

- Ctrl → Cmd remapping for common shortcuts (copy, paste, save, etc.)
- Fullscreen suppression for selected apps
- AltGr fixes for consistent symbol input
- Scroll-to-zoom support (Ctrl + Scroll)
- App-specific remap blocking via bundle ID
- Diagnostic hotkey (Cmd+Alt+Ctrl+T) shows active remap state

## Installation

1. Install [Hammerspoon](https://www.hammerspoon.org/)
2. Clone this repo:
   ```bash
   git clone https://github.com/qol-tools/windows-like-remap.git
   ```
3. Symlink the config file:
   ```bash
   ln -s /path/to/windows-like-remap/init.lua ~/.hammerspoon/init.lua
   ```
4. Reload Hammerspoon and grant accessibility permissions

## Customization

Edit `init.lua` to customize shortcuts, app-specific behavior, or enable debug logging with `DEBUG = true`.

## License

PolyForm Noncommercial 1.0.0
