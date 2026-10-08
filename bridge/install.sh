#!/bin/sh
# clipbridge installer. Run it on the SSH SERVER, the machine your terminal programs
# (e.g. Claude Code) run on.
#
#   bridge/install.sh --host <ssh-destination-of-your-machine> --client-ip <ip> [options]
#
#   --host H           how this server reaches YOUR machine over SSH (alias / DNS name / IP)
#   --client-ip IP     source IP of your machine's SSH sessions as seen here (repeatable)
#   --idle-ms N        desktop-idle threshold for rule 2 (default 4000)
#   --no-desktop-rule  disable rule 2 (only display-less SSH sessions use your clipboard)
#   --ssh-port N       port this server's sshd listens on (default 22)
#   --prefix DIR       where to install the shims (default ~/.local/bin)
#   --force            overwrite existing non-clipbridge files of the same name
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX="$HOME/.local/bin"; HOST=""; IPS=""; IDLE=4000; DESK=1; PORT=22; FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST=$2; shift ;;
    --client-ip) IPS="${IPS:+$IPS }$2"; shift ;;
    --idle-ms) IDLE=$2; shift ;;
    --no-desktop-rule) DESK=0 ;;
    --ssh-port) PORT=$2; shift ;;
    --prefix) PREFIX=$2; shift ;;
    --force) FORCE=1 ;;
    -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 2 ;;
  esac
  shift
done
[ -n "$HOST" ] && [ -n "$IPS" ] || { echo "need --host and at least one --client-ip (see --help)" >&2; exit 2; }

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

CONF_DIR="$HOME/.config/clipbridge"
mkdir -p "$CONF_DIR"
cat > "$CONF_DIR/config" <<EOF
# clipbridge config, written by install.sh. See bridge/config.example for every option.
CLIPBRIDGE_HOST=$HOST
CLIPBRIDGE_CLIENT_IPS="$IPS"
CLIPBRIDGE_IDLE_MS=$IDLE
CLIPBRIDGE_DESKTOP_RULE=$DESK
CLIPBRIDGE_SSH_PORT=$PORT
CLIPBRIDGE_CLIENT_DISPLAY=:0
CLIPBRIDGE_CLIENT_WAYLAND_DISPLAY=wayland-0
EOF
echo "config:    $CONF_DIR/config"

echo "--- checks"
ok=1
for t in xclip wl-paste wl-copy; do
  [ -x "/usr/bin/$t" ] || echo "note: /usr/bin/$t not installed here; local use of $t will fail (remote use still works)"
done
first=$(command -v xclip 2>/dev/null || true)
if [ "$first" != "$PREFIX/xclip" ]; then
  echo "WARN: '$PREFIX' is not first in PATH for this shell (xclip resolves to: ${first:-nothing})."
  echo "      Programs must find the shims before /usr/bin. Put $PREFIX at the front of PATH."
  ok=0
fi
if ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST" true 2>/dev/null; then
  echo "ok:   ssh $HOST works without a prompt"
  remote_tools=$(ssh -o BatchMode=yes "$HOST" 'for t in xclip wl-paste; do command -v $t >/dev/null && printf "%s " $t; done' 2>/dev/null || true)
  echo "ok:   clipboard tools on $HOST: ${remote_tools:-NONE (install xclip and/or wl-clipboard there)}"
else
  echo "FAIL: 'ssh -o BatchMode=yes $HOST true' failed. Add this server's public key to"
  echo "      ~/.ssh/authorized_keys on your machine, and make sure it is reachable."
  ok=0
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
