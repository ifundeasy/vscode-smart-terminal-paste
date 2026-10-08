#!/bin/sh
# clipbridge installer. Run it on the SSH SERVER, the machine your terminal programs
# (e.g. Claude Code) run on.
#
#   bridge/install.sh --host <ssh-destination-of-your-machine> --client-ip <ip> [options]
#
#   --host H          how this server reaches YOUR machine over SSH (alias / DNS name / IP)
#   --client-ip IP    source IP of your machine's SSH sessions as seen here (repeatable)
#   --setup-client    also set up your machine over SSH. Needs normal passwordless SSH to
#                     it once. Installs clipbridge-serve and authorizes the dedicated key,
#                     locked to that forced command and to this server's IP.
#   --desktop-rule    enable rule 2 (desktop-env sessions while this desktop is idle);
#                     off by default, see docs/remote-clipboard.md before enabling
#   --idle-ms N       desktop-idle threshold for rule 2 (default 4000)
#   --ssh-port N      port this server's sshd listens on (default 22)
#   --key PATH        dedicated key (default ~/.ssh/clipbridge_ed25519; created if missing)
#   --prefix DIR      where to install the shims (default ~/.local/bin)
#   --force           overwrite existing non-clipbridge files of the same name
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX="$HOME/.local/bin"; HOST=""; IPS=""; IDLE=4000; DESK=0; PORT=22; FORCE=0; SETUP=0
KEY="$HOME/.ssh/clipbridge_ed25519"
while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST=$2; shift ;;
    --client-ip) IPS="${IPS:+$IPS }$2"; shift ;;
    --setup-client) SETUP=1 ;;
    --desktop-rule) DESK=1 ;;
    --idle-ms) IDLE=$2; shift ;;
    --ssh-port) PORT=$2; shift ;;
    --key) KEY=$2; shift ;;
    --prefix) PREFIX=$2; shift ;;
    --force) FORCE=1 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 2 ;;
  esac
  shift
done
[ -n "$HOST" ] && [ -n "$IPS" ] || { echo "need --host and at least one --client-ip (see --help)" >&2; exit 2; }

# 1. Shims
FILES="clip-route clipbridge-ssh xclip wl-paste wl-copy"
mkdir -p "$PREFIX"
for f in $FILES; do
  t="$PREFIX/$f"
  if [ -e "$t" ] && ! grep -q 'clipbridge' "$t" 2>/dev/null && [ "$FORCE" = 0 ]; then
    echo "refusing to overwrite $t: it is not a clipbridge file (re-run with --force)" >&2
    exit 1
  fi
done
for f in $FILES; do install -m 755 "$HERE/$f" "$PREFIX/$f"; done
echo "installed: $FILES -> $PREFIX"

# 2. Dedicated key (only ever accepted by clipbridge-serve on your machine)
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
if [ ! -f "$KEY" ]; then
  ssh-keygen -q -t ed25519 -N '' -C "clipbridge@$(hostname)" -f "$KEY"
  echo "created key: $KEY"
fi
PUB=$(cat "$KEY.pub")

# 3. Config
CONF_DIR="$HOME/.config/clipbridge"
mkdir -p "$CONF_DIR"
cat > "$CONF_DIR/config" <<EOF
# clipbridge config, written by install.sh. See bridge/config.example for every option.
CLIPBRIDGE_HOST=$HOST
CLIPBRIDGE_CLIENT_IPS="$IPS"
CLIPBRIDGE_KEY=$KEY
CLIPBRIDGE_DESKTOP_RULE=$DESK
CLIPBRIDGE_IDLE_MS=$IDLE
CLIPBRIDGE_SSH_PORT=$PORT
EOF
echo "config:    $CONF_DIR/config (desktop rule: $([ "$DESK" = 1 ] && echo ON || echo off))"

# 4. Close control masters left by older versions. They may have been authenticated
#    with an unrestricted key, and reusing them would bypass the forced command.
for s in "$HOME"/.ssh/cm-clipbridge-* "$HOME"/.ssh/cm-clip-*; do
  [ -e "$s" ] || continue
  ssh -o ControlPath="$s" -O exit placeholder >/dev/null 2>&1 || true
  rm -f "$s"
done

# 5. Your machine
if [ "$SETUP" = 1 ]; then
  echo "--- setting up $HOST (using your normal SSH access once)"
  seen=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST" 'printf %s "${SSH_CONNECTION%% *}"')
  chome=$(ssh -o BatchMode=yes "$HOST" 'printf %s "$HOME"')
  ssh -o BatchMode=yes "$HOST" 'mkdir -p ~/.local/bin && cat > ~/.local/bin/clipbridge-serve && chmod 755 ~/.local/bin/clipbridge-serve' < "$HERE/clipbridge-serve"
  body=$(printf '%s' "$PUB" | awk '{print $2}')
  line="restrict,command=\"$chome/.local/bin/clipbridge-serve\",from=\"$seen\" $PUB"
  printf '%s\n' "$line" | ssh -o BatchMode=yes "$HOST" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && { grep -v '$body' ~/.ssh/authorized_keys || true; cat; } > ~/.ssh/authorized_keys.clipbridge.tmp && cat ~/.ssh/authorized_keys.clipbridge.tmp > ~/.ssh/authorized_keys && rm -f ~/.ssh/authorized_keys.clipbridge.tmp"
  echo "client:    clipbridge-serve installed; key authorized with restrict,command=...,from=\"$seen\""
else
  echo "--- next: on YOUR machine, from a clone of this repo, run:"
  echo "    sh bridge/install-client.sh --pubkey \"$PUB\" --from <this-server's-IP-as-your-machine-sees-it>"
fi

# 6. Checks
echo "--- checks"
ok=1
first=$(command -v xclip 2>/dev/null || true)
if [ "$first" != "$PREFIX/xclip" ]; then
  echo "WARN: '$PREFIX' is not first in PATH for this shell (xclip resolves to: ${first:-nothing})."
  echo "      Programs must find the shims before /usr/bin. Put $PREFIX at the front of PATH."
fi
if out=$("$PREFIX/clipbridge-ssh" ping 2>&1) && [ "$out" = "clipbridge-serve ok" ]; then
  echo "ok:   dedicated key reaches clipbridge-serve on $HOST"
else
  echo "FAIL: '$PREFIX/clipbridge-ssh ping' -> $out"
  ok=0
fi
if denied=$(ssh -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ControlPath=none "$HOST" id 2>&1); then
  echo "FAIL: the dedicated key ran an arbitrary command on $HOST: it is NOT locked down"
  ok=0
else
  case "$denied" in *denied*) echo "ok:   the dedicated key cannot run other commands ($denied)" ;; *) echo "note: lock test -> $denied" ;; esac
fi
if [ "$ok" = 1 ]; then
  ip1=${IPS%% *}
  printf 'self-test (as a display-less SSH session from %s): ' "$ip1"
  if out=$(env -u DISPLAY -u WAYLAND_DISPLAY SSH_CONNECTION="$ip1 50000 127.0.0.1 $PORT" \
        "$PREFIX/xclip" -selection clipboard -t TARGETS -o 2>&1); then
    echo "OK, your machine's clipboard offers: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-80)"
  else
    echo "FAILED: $out"
  fi
fi
