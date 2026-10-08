#!/bin/sh
# clipbridge uninstaller. Run it on the SSH server.
#   bridge/uninstall.sh [--prefix DIR] [--purge]
# Removes the clipbridge files from the prefix (default ~/.local/bin). Only files that
# carry the clipbridge marker are touched. --purge also removes
# ~/.config/clipbridge and the SSH control sockets.
set -eu
PREFIX="$HOME/.local/bin"; PURGE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX=$2; shift ;;
    --purge) PURGE=1 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
for f in clip-route clipbridge-ssh xclip wl-paste wl-copy; do
  t="$PREFIX/$f"
  if [ -f "$t" ] && grep -q 'clipbridge' "$t"; then rm -f "$t" && echo "removed $t"; fi
done
if [ "$PURGE" = 1 ]; then
  rm -rf "$HOME/.config/clipbridge" && echo "removed ~/.config/clipbridge"
  for s in "$HOME"/.ssh/cm-clipbridge-*; do [ -e "$s" ] && rm -f "$s"; done
fi
echo "done; the real /usr/bin tools are used again"
