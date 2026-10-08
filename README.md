# Smart Terminal Paste

One **Ctrl+V** for the VS Code integrated terminal on Linux. It pastes text, and it pastes images too.

| Clipboard holds | What Ctrl+V does in the terminal |
|---|---|
| Text | Normal terminal paste (bracketed paste, same as Ctrl+Shift+V) |
| No text, e.g. a screenshot | Sends a literal Ctrl+V to the running program |

## Why

Some terminal programs bind **Ctrl+V to image paste**. One is [Claude Code](https://code.claude.com), whose Ctrl+V on Linux reads only an image from the clipboard. With text in the clipboard it inserts nothing, and you have to remember Ctrl+Shift+V for text.

This extension decides on the VS Code side, where the clipboard lives. Text goes in as a paste. Otherwise Ctrl+V is forwarded so the program can paste the image.

## Install

Download the `.vsix` from [Releases](https://github.com/ifundeasy/vscode-smart-terminal-paste/releases), then run:

```sh
code --install-extension smart-terminal-paste-0.2.0.vsix
```

Then reload the window: Command Palette → **Developer: Reload Window**.

On first start the extension adds `smartTerminalPaste.paste` to `terminal.integrated.commandsToSkipShell` in your user settings. Without that entry the terminal consumes Ctrl+V before any extension sees it. To manage that setting yourself, turn off `smartTerminalPaste.autoConfigure`.

## Remote windows (Remote-SSH, containers)

The extension runs on the **UI side** (`extensionKind: ui`), so it always reads the clipboard of the machine in front of you, also in remote windows:

- **Text** is pasted into the remote terminal directly.
- **Images** reach the remote program only as a Ctrl+V keystroke. That program then reads the clipboard of the machine it runs on, which is the remote host, not yours.

For image paste **and** selection copy across SSH, install the server-side bridge from this repo. **[docs/remote-clipboard.md](docs/remote-clipboard.md)** is the full tutorial: how it works, requirements, client and server setup, verification, troubleshooting, security and uninstall.

```sh
# on the SSH server
sh bridge/install.sh --host <your-machine> --client-ip <your-ip-as-seen-by-the-server> --setup-client
```

## Repository layout

| Path | What |
|---|---|
| `extension.js`, `package.json` | the VS Code extension (runs on your machine) |
| `bridge/` | clipboard bridge: server shims (`xclip` / `wl-paste` / `wl-copy`, `clip-route`, `clipbridge-ssh`), client forced command (`clipbridge-serve`), `install.sh` / `install-client.sh` / `uninstall.sh`, `config.example` |
| `docs/remote-clipboard.md` | setup tutorial for the bridge |
| `scripts/package.py` | builds the `.vsix` with no dependencies |

## Limitations

- **Linux only.** The keybinding is `ctrl+v` when `terminalFocus && isLinux`. On macOS (Cmd+V) and Windows the terminal's Ctrl+V already behaves differently.
- When the clipboard holds both text and an image (for example an image copied from a browser together with its alt text), the text is pasted.
- In a plain shell, Ctrl+V with an image in the clipboard sends Ctrl+V to the shell. In zsh/bash that is "quoted insert".

## Build

The build needs no dependencies, only the Python standard library:

```sh
python3 scripts/package.py   # -> dist/smart-terminal-paste-<version>.vsix
```

The official tool works too: `npx @vscode/vsce package`.

## License

[MIT](LICENSE)
