# windows-like-remap

A Hammerspoon configuration for remapping macOS keyboard and mouse behavior to feel more like Windows.

## Features

- 🔁 **Ctrl → Cmd** remaps for common shortcuts (copy, paste, save, etc.)
- 🚫 **Fullscreen suppression** for selected apps (`Ctrl+Cmd+F` is blocked)
- 💡 **AltGr fixes** for consistent symbol input (e.g. `{`, `}`, `"`)
- 🖱️ **Scroll-to-zoom** support (`Ctrl + Scroll` → `Cmd + +/-`)
- ⚙️ **App-specific remap blocking** via bundle ID
- 🧠 **Diagnostic hotkey** (`Cmd+Alt+Ctrl+T`) shows active remap state

## Installation

1. Clone the repo:
   ```bash
   git clone git@github.com:KMRH47/windows-like-remap.git
   ```

2. Symlink or copy the config file into your Hammerspoon config directory:
   ```bash
   ln -s /path/to/windows-like-remap/init.lua ~/.hammerspoon/init.lua
   ```

3. Reload Hammerspoon and grant necessary accessibility permissions.

## Notes

- Remaps are declarative and customizable (`SHORTCUTS`, `APP_SHORTCUTS`, etc.)
- Easily extendable with more app-specific behavior or keyboard layers
- Logging is enabled by setting `DEBUG = true` in the script

## License

MIT
