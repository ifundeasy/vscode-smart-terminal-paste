#!/bin/sh
# clipbridge uninstaller. Run it on the SSH server.
#   bridge/uninstall.sh [--prefix DIR] [--client] [--purge]
# Removes the clipbridge shims from the prefix (default ~/.local/bin); only files carrying
# the clipbridge marker are touched.
#   --client  also remove clipbridge-serve and the dedicated key's authorized_keys entry
#             from your machine, over your normal SSH access (CLIPBRIDGE_HOST)
#   --purge   also remove ~/.config/clipbridge, the dedicated key and SSH control sockets
set -eu
PREFIX="$HOME/.local/bin"; PURGE=0; CLIENT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX=$2; shift ;;
    --client) CLIENT=1 ;;
    --purge) PURGE=1 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
CONF="$HOME/.config/clipbridge/config"
# shellcheck disable=SC1090
[ -r "$CONF" ] && . "$CONF"
KEY="${CLIPBRIDGE_KEY:-$HOME/.ssh/clipbridge_ed25519}"

if [ "$CLIENT" = 1 ] && [ -n "${CLIPBRIDGE_HOST:-}" ]; then
  ssh -o BatchMode=yes "$CLIPBRIDGE_HOST" "grep -v 'command=\"[^\"]*clipbridge-serve\"' ~/.ssh/authorized_keys > ~/.ssh/authorized_keys.clipbridge.tmp || true; cat ~/.ssh/authorized_keys.clipbridge.tmp > ~/.ssh/authorized_keys; rm -f ~/.ssh/authorized_keys.clipbridge.tmp ~/.local/bin/clipbridge-serve" \
    && echo "removed clipbridge-serve and its key from $CLIPBRIDGE_HOST"
fi
for f in clip-route clipbridge-ssh xclip wl-paste wl-copy; do
  t="$PREFIX/$f"
  if [ -f "$t" ] && grep -q 'clipbridge' "$t"; then rm -f "$t" && echo "removed $t"; fi
done
if [ "$PURGE" = 1 ]; then
  for s in "$HOME"/.ssh/cm-clipbridge-*; do
    [ -e "$s" ] && { ssh -o ControlPath="$s" -O exit placeholder >/dev/null 2>&1 || true; rm -f "$s"; }
  done
  rm -f "$KEY" "$KEY.pub" && echo "removed $KEY"
  rm -rf "$HOME/.config/clipbridge" && echo "removed ~/.config/clipbridge"
fi
echo "done; the real /usr/bin tools are used again"
