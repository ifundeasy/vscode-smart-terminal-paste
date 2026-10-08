# Changelog

## 0.2.0

Security hardening of the bridge. **The setup changed**: re-run `bridge/install.sh` with `--setup-client`, or run `install-client.sh` on your machine.

- The server now reaches your machine with a **dedicated key** (`~/.ssh/clipbridge_ed25519`). On your machine that key is locked to the new forced command `clipbridge-serve` (`restrict,command=...,from=...`), which accepts only `ping`, `targets`, `get` and `set` on the clipboard/primary selection. In 0.1.0 the bridge used your normal SSH identity, so a compromised server could run any command on your machine.
- The shims send those fixed requests instead of command lines.
- `install.sh --setup-client` sets up your machine over SSH. `install-client.sh` does it by hand on your machine. `uninstall.sh --client` removes it again.
- The installer verifies that the dedicated key **cannot** run other commands, and it closes control connections left by 0.1.0.
- **Rule 2 (desktop-idle routing) is now opt-in** (`--desktop-rule`). While it is on, any process of the user on the server that has the desktop environment can use your clipboard.

## 0.1.0

- First release.
- Ctrl+V in the terminal pastes text, or sends Ctrl+V when the clipboard holds no text, e.g. an image.
- Adds the command to `terminal.integrated.commandsToSkipShell` automatically; opt out with `smartTerminalPaste.autoConfigure`.
- `bridge/`: a server-side clipboard bridge that makes image paste and selection copy work over SSH. It has `xclip` / `wl-paste` / `wl-copy` shims, an installer and an uninstaller; the tutorial is `docs/remote-clipboard.md`.
