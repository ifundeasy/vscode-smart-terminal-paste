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
3. A session started by a background supervisor (for example a session manager or agent view running under this host's desktop) inherits the **server's desktop environment**. It therefore looks local even while you view it from your laptop.

## How it works

Shims named `xclip`, `wl-paste` and `wl-copy` are placed in `~/.local/bin` on the server, ahead of `/usr/bin` in `PATH`. For every clipboard call, `clip-route` decides who owns the clipboard right now:

| Rule | Condition | Clipboard used |
|---|---|---|
| 1 | The process has **no display** and `$SSH_CONNECTION` comes from one of your `CLIPBRIDGE_CLIENT_IPS` | **yours**, over SSH |
| 2 | The process has the server's desktop env, your machine holds a **live SSH connection** to the server, **and** the server's GNOME desktop has been **idle** > `CLIPBRIDGE_IDLE_MS` | **yours**, over SSH |
| - | anything else (you are at the server's own keyboard, other users, ...) | the server's own clipboard, through the real tool |

"Over SSH" means `clipbridge-ssh` runs the same tool on your machine, e.g. `ssh my-laptop xclip -selection clipboard -t image/png -o`, with your desktop's `DISPLAY`/`XAUTHORITY`/`WAYLAND_DISPLAY` set up.

- Writes go through `xclip -i` on your X/XWayland display. GNOME syncs that to the Wayland clipboard.
- An SSH ControlMaster keeps it fast: the first call takes about 250 ms, later ones about 40–100 ms.

Two more protections:
- In a display-less SSH session that is **not** from your machine, the `wl-paste` shim fails fast instead of hanging.
- Local `wl-paste` calls get a timeout.

## Requirements

| Where | What |
|---|---|
| Server (runs Claude Code) | Linux, POSIX `sh`, OpenSSH client, `ss` (iproute2). `gdbus` + GNOME for rule 2 (optional). |
| Your machine (client) | Linux desktop (tested: GNOME on Wayland), **`sshd` running**, `xclip` (X/XWayland) and/or `wl-clipboard`. |
| Network | The **server must be able to SSH back to your machine.** On a home LAN that often works directly. Elsewhere use a VPN such as [Tailscale](https://tailscale.com): both machines join the same tailnet, and the server reaches you by your MagicDNS name. |

Tested with: Ubuntu 26.04 GNOME/Wayland on both ends, Tailscale, VS Code Remote-SSH, Claude Code 2.1.x, on LAN and over a phone hotspot.

## Setup

### 1. Your machine (client)

```sh
sudo apt install openssh-server xclip wl-clipboard
```

Allow the **server** to SSH into your machine with a key. On the server run `cat ~/.ssh/id_ed25519.pub`, then append that line to `~/.ssh/authorized_keys` on your machine.

Find the address the server should use to reach you. With Tailscale that is your machine's MagicDNS name, e.g. `my-laptop` (or `my-laptop.<tailnet>.ts.net`).

### 2. Find your client IP as the server sees it

Open a terminal on the server **from your machine** (e.g. a VS Code Remote-SSH terminal) and run:

```sh
echo "${SSH_CONNECTION%% *}"     # e.g. 100.64.0.2 (your Tailscale IP)
```

If you also connect over the LAN by IP, note that address too. Every route you connect through needs its own `--client-ip`.

### 3. Server

```sh
git clone https://github.com/ifundeasy/vscode-smart-terminal-paste.git
cd vscode-smart-terminal-paste
sh bridge/install.sh --host my-laptop --client-ip 100.64.0.2
```

The installer:
- copies the shims to `~/.local/bin`;
- writes `~/.config/clipbridge/config`;
- checks `PATH` order and passwordless `ssh` back to your machine;
- runs a self-test that reads your clipboard.

It refuses to replace existing `xclip`/`wl-paste`/`wl-copy` files that are not its own unless you pass `--force`.

**`PATH` order matters.** Everything that runs Claude Code must find `~/.local/bin` before `/usr/bin`. That includes login shells, VS Code server terminals and user services. Check with `command -v xclip`, which must print `~/.local/bin/xclip`.

### 4. VS Code on your machine (optional but recommended)

Install the extension from this repo (see the [README](../README.md)), so one **Ctrl+V** pastes text *and* images.

For copying with a normal terminal selection, also set this in your VS Code user settings:

```json
"terminal.integrated.copyOnSelection": true
```

In Claude Code's fullscreen UI, plain drag-select is copied by Claude itself, and the bridge forwards it. **Shift+drag** makes a native VS Code selection, which `copyOnSelection` then copies.

## Verify

On the server, in a terminal opened from your machine:

```sh
xclip -selection clipboard -t TARGETS -o     # lists YOUR clipboard's formats
printf 'hello from the server' | wl-copy      # now paste on your machine
```

In Claude Code:
1. Take a screenshot to the clipboard on your machine and press **Ctrl+V**. It shows up as `[Image #1]`.
2. Select some output text and paste it on your machine.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Still stuck on "Pasting..." | The shim isn't used. `command -v wl-paste` must be `~/.local/bin/wl-paste` for the process running the app. Restart sessions started before install whose `PATH` lacks it. |
| "No image found in clipboard" | Your clipboard has no image, or `clip-route` chose the server. Test with `~/.local/bin/clip-route; echo $?` inside that session: 0 means your machine. |
| Rule 2 never picks your machine | No live SSH connection from a listed IP (`ss -tn state established '( sport = :22 )'`), the desktop isn't GNOME, or you touched the server's keyboard less than `CLIPBRIDGE_IDLE_MS` ago. |
| `ssh: ... Host key verification failed` / password prompt | Add the server's key to your machine and accept your machine's host key once interactively (`ssh my-laptop true`). The bridge uses `BatchMode=yes`, so it never prompts. |
| Text pastes but images don't, inside VS Code | Use the extension or press the app's image-paste key. On Linux VS Code's own terminal paste (Ctrl+Shift+V) only handles text. |
| `zsh: no matches found` while testing | zsh aborts on unmatched globs; run the test command under `bash -c '...'`. |

## Security notes

- While a rule matches, **the server can read and write your clipboard** through SSH. This is the point of the bridge. Install it only on servers you trust as much as your own machine.
- The server needs SSH access **to your machine**. For tighter control, give the server a dedicated key restricted in your `authorized_keys`, e.g. with `from="<server-ip>"` and `no-port-forwarding,no-agent-forwarding,no-X11-forwarding`.
- Nothing is stored. Clipboard data only flows through the SSH channel when a tool is called.

## Uninstall

```sh
sh bridge/uninstall.sh --purge      # on the server
```

Only files carrying the clipbridge marker are removed. After that the real `/usr/bin` tools are used again.
