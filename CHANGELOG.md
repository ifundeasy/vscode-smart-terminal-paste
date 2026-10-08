# Changelog

## 0.1.0

- First release.
- Ctrl+V in the terminal pastes text, or sends Ctrl+V when the clipboard holds no text, e.g. an image.
- Adds the command to `terminal.integrated.commandsToSkipShell` automatically; opt out with `smartTerminalPaste.autoConfigure`.
- `bridge/`: a server-side clipboard bridge that makes image paste and selection copy work over SSH. It has `xclip` / `wl-paste` / `wl-copy` shims, an installer and an uninstaller; the tutorial is `docs/remote-clipboard.md`.
