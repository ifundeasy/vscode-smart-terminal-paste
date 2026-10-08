# Remote clipboard bridge (clipbridge)

This setup makes image paste and selection copy work when your terminal program runs on a **remote host over SSH**. The example program is Claude Code; the target is VS Code Remote-SSH.

**Paste a screenshot from your machine:**
- Without the bridge: Ctrl+V hangs on "Pasting..." or says "No image found".
- With the bridge: the image is attached.

**Select text in the remote session:**
- Without the bridge: nothing reaches your clipboard.
- With the bridge: the text is on your clipboard.

The VS Code extension in this repo handles the keyboard side (one Ctrl+V for text and images). `bridge/` handles the server side.

## The problem

Claude Code on Linux reads and writes the clipboard by running local tools. It reads with `xclip ... -o` and then falls back to `wl-paste`. It writes with `wl-copy`, or `xclip`/`xsel`, or OSC 52.

Over SSH those tools run on the **server**, so:

1. They see the server's clipboard, never yours. Your screenshot is on your machine.
2. With no display, `xclip` fails, and `wl-paste` can **hang**. On GNOME it may also hang when called from a background process. The app then waits forever ("Pasting...").
3. A session started by a background supervisor (for example a session manager running under the server's desktop) inherits the **server's desktop environment**. It therefore looks local even while you view it from your machine.

## How it works

```
 server (runs Claude Code)                          your machine (client)
 ─────────────────────────                          ─────────────────────
 app ─► xclip / wl-paste / wl-copy  (shims in ~/.local/bin)
          │  clip-route: is the user on the client right now?
          ├─ no  ─► real /usr/bin tool (server's clipboard)
          └─ yes ─► clipbridge-ssh ── ssh, dedicated key ──► clipbridge-serve (forced command)
                     "targets clipboard"                     validates the request, then runs
                     "get clipboard image/png"               xclip / wl-paste / wl-copy on
                     "set clipboard"  (+stdin)               your desktop session
```

`clip-route` rules:

| Rule | Condition | Clipboard used |
|---|---|---|
| 1 | The process has **no display** and `$SSH_CONNECTION` comes from one of your `CLIPBRIDGE_CLIENT_IPS`. This is a terminal opened from your machine. | **yours** |
| 2 (opt-in) | The process has the server's desktop env, your machine holds a **live SSH connection** to the server, **and** the server's GNOME desktop has been **idle** > `CLIPBRIDGE_IDLE_MS` | **yours** |
| - | anything else (you are at the server's own keyboard, other users, ...) | the server's own, via the real tool |

The server talks to your machine with a **dedicated key**. On your machine that key is locked in `authorized_keys`:

```
restrict,command="/home/you/.local/bin/clipbridge-serve",from="<server-ip>" ssh-ed25519 AAAA... clipbridge@server
```

- `clipbridge-serve` accepts exactly four requests and rejects everything else:
  - `ping`;
  - `targets <clipboard|primary>`;
  - `get <clipboard|primary> <type>`;
  - `set <clipboard|primary>`.
- `restrict` disables forwarding and PTYs, and `from=` accepts the key only from the server's address.
- An SSH ControlMaster keeps it fast: the first call takes about 250 ms, later ones about 40–100 ms.
- In a display-less SSH session that is **not** from your machine, the `wl-paste` shim fails fast instead of hanging.
- Local `wl-paste` calls get a timeout.

## Requirements

| Where | What |
|---|---|
| Server (runs Claude Code) | Linux, POSIX `sh`, OpenSSH client + `ssh-keygen`, `ss` (iproute2). `gdbus` + GNOME only for rule 2. |
| Your machine (client) | Linux desktop (tested: GNOME on Wayland), **`sshd` running**, `xclip` (X/XWayland) and/or `wl-clipboard`. |
| Network | The **server must be able to SSH back to your machine.** On a home LAN that often works directly. Elsewhere use a VPN such as [Tailscale](https://tailscale.com): both machines join the same tailnet, and the server reaches you by your MagicDNS name. |

Tested with: Ubuntu 26.04 GNOME/Wayland on both ends, Tailscale, VS Code Remote-SSH, Claude Code 2.1.x, on LAN and over a phone hotspot.

## Setup

### 1. Your machine (client)

```sh
sudo apt install openssh-server xclip wl-clipboard
```

With Tailscale, note your machine's MagicDNS name (e.g. `my-laptop`). The server will reach you by that name.

### 2. Find your client IP as the server sees it

Open a terminal on the server **from your machine** (e.g. a VS Code Remote-SSH terminal) and run:

```sh
echo "${SSH_CONNECTION%% *}"     # e.g. 100.64.0.2 (your Tailscale IP)
```

Every route you connect through needs its own `--client-ip`, for example Tailscale and LAN.

### 3. Server

```sh
git clone https://github.com/ifundeasy/vscode-smart-terminal-paste.git
cd vscode-smart-terminal-paste
sh bridge/install.sh --host my-laptop --client-ip 100.64.0.2 --setup-client
```

What the installer does:
- Installs the shims to `~/.local/bin`.
- Creates the dedicated key `~/.ssh/clipbridge_ed25519`.
- Writes `~/.config/clipbridge/config`.
- Closes control connections left by older versions.
- Checks the setup: `PATH` order, `ping` through the dedicated key, a test that the key **cannot** run other commands, and a self-test read of your clipboard.

`--setup-client` uses your **normal** SSH access to your machine **once**. It installs `~/.local/bin/clipbridge-serve` there and authorizes the dedicated key, locked as shown above, with `from=` set to the server address your machine sees.

**Without normal SSH access from the server to your machine** (or if you'd rather not grant it), leave out `--setup-client`. Then run the command the installer prints, on your machine, from a clone of this repo:

```sh
sh bridge/install-client.sh --pubkey "ssh-ed25519 AAAA... clipbridge@server" --from <server-ip>
```

The installer refuses to replace existing `xclip`/`wl-paste`/`wl-copy` files that are not its own unless you pass `--force`.

**`PATH` order matters.** Everything that runs Claude Code must find `~/.local/bin` before `/usr/bin`. That includes login shells, VS Code server terminals and user services. Check with `command -v xclip`, which must print `~/.local/bin/xclip`.

### 4. Rule 2 (optional): sessions run by a background supervisor

Use this if your sessions are started by something running under the server's desktop, for example a session manager you attach to from your machine. Re-run the installer with `--desktop-rule`.

**Trade-off:** while your machine is connected and the server's desktop is idle, *any* process of your user on the server that has the desktop environment can read and write your clipboard. Enable it only on a single-user server you fully trust.

### 5. VS Code on your machine (optional but recommended)

Install the extension from this repo (see the [README](../README.md)), so one **Ctrl+V** pastes text *and* images.

For copying with a normal terminal selection, also set this in your VS Code user settings:

```json
"terminal.integrated.copyOnSelection": true
```

In Claude Code's fullscreen UI, plain drag-select is copied by Claude itself, and the bridge forwards it. **Shift+drag** makes a native VS Code selection, which `copyOnSelection` then copies.

## Verify

On the server, in a terminal opened from your machine:

```sh
~/.local/bin/clipbridge-ssh ping                 # clipbridge-serve ok
xclip -selection clipboard -t TARGETS -o          # lists YOUR clipboard's formats
printf 'hello from the server' | wl-copy          # now paste on your machine
```

In Claude Code:
1. Take a screenshot to the clipboard on your machine and press **Ctrl+V**. It shows up as `[Image #1]`.
2. Select some output text and paste it on your machine.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Still stuck on "Pasting..." | The shim isn't used. `command -v wl-paste` must be `~/.local/bin/wl-paste` for the process running the app. Restart sessions started before the install. |
| "No image found in clipboard" | Your clipboard has no image, or `clip-route` chose the server. Run `~/.local/bin/clip-route; echo $?` inside that session: 0 means your machine. |
| `clipbridge-serve: denied: ...` | The shim sent a request the client doesn't accept, e.g. an unusual type or selection. Use a normal MIME type; the secondary selection is not bridged. |
| `ping` fails / `Permission denied (publickey)` | The dedicated key isn't authorized on your machine (re-run with `--setup-client`, or `install-client.sh`), or `from=` doesn't match the server's address as your machine sees it. |
| `Host key verification failed` | Accept your machine's host key once interactively: `ssh my-laptop true`. The bridge uses `BatchMode=yes`, so it never prompts. |
| Sessions from a supervisor still use the server clipboard | Rule 2 is off by default (`--desktop-rule`), it needs GNOME, and you must not have touched the server's keyboard for `CLIPBRIDGE_IDLE_MS`. |
| `zsh: no matches found` while testing | zsh aborts on unmatched globs; run the test under `bash -c '...'`. |

## Security notes

- **What the server can do on your machine:** list, read and replace your clipboard, and nothing else.
  - The dedicated key only runs `clipbridge-serve` (`restrict,command=`), and only from the server's address (`from=`).
  - A compromised server cannot get a shell, forward ports or read files through it.
- **When:** whenever the server can reach your machine. The key does not know about `clip-route`. The routing rules only decide which clipboard legitimate programs use, they don't limit the key.
  - If the server ever becomes untrusted, remove the `clipbridge-serve` line from `~/.ssh/authorized_keys` on your machine, or run `bridge/uninstall.sh --client` from the server.
- `--setup-client` needs your normal SSH access to your machine once. If you never want the server to hold such access, use `install-client.sh` on your machine instead.
- **Rule 2 is off by default.** When on, any process of your user on the server that has the desktop environment can use your clipboard while the server's desktop is idle and your machine is connected.
- Nothing is stored. Clipboard data only flows through the SSH channel when a tool is called.

## Uninstall

```sh
sh bridge/uninstall.sh --client --purge   # on the server
```

What this does:
- `--client` removes `clipbridge-serve` and the key's `authorized_keys` line from your machine, over your normal SSH.
- `--purge` also deletes the dedicated key, the config and the control sockets.
- Only files carrying the clipbridge marker are removed.

To remove the client side by hand on your machine, run `sh bridge/install-client.sh --uninstall`.
