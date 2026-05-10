# Windows-like Remap

A [Hammerspoon](https://www.hammerspoon.org/) configuration that makes macOS keyboard shortcuts feel like Windows.

## Quick start

Install Hammerspoon, then symlink `init.lua`:

```bash
git clone https://github.com/qol-tools/windows-like-remap
ln -s "$PWD/windows-like-remap/init.lua" ~/.hammerspoon/init.lua
```

Reload Hammerspoon and grant accessibility permissions. Edit `init.lua` to customise.

## About

Remaps Ctrl to Cmd for common shortcuts, suppresses fullscreen on selected apps, fixes AltGr symbol input, adds Ctrl+Scroll to zoom, and supports per-app remap blocking by bundle ID. Press Cmd+Alt+Ctrl+T to inspect active remap state.

## License

PolyForm Noncommercial 1.0.0
