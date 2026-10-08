#!/bin/sh
# clipbridge client installer. Run it on YOUR machine (the client).
# (install.sh --setup-client on the server does the same over SSH.)
#
#   bridge/install-client.sh --pubkey "ssh-ed25519 AAAA... clipbridge@server" [--from <server-ip>]
#   bridge/install-client.sh --uninstall
#
# Installs ~/.local/bin/clipbridge-serve and adds the server's dedicated key to
# ~/.ssh/authorized_keys, restricted to that forced command (plus `from=` when given).
# That key can then only list, read and set your clipboard, nothing else.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
PUBKEY=""; FROM=""; UNINSTALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --pubkey) PUBKEY=$2; shift ;;
    --from) FROM=$2; shift ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 2 ;;
  esac
  shift
done

AK="$HOME/.ssh/authorized_keys"
SERVE="$HOME/.local/bin/clipbridge-serve"

if [ "$UNINSTALL" = 1 ]; then
  if [ -f "$AK" ]; then
    grep -v 'command="[^"]*clipbridge-serve"' "$AK" > "$AK.tmp" || true
    cat "$AK.tmp" > "$AK" && rm -f "$AK.tmp"
    echo "removed clipbridge keys from $AK"
  fi
  rm -f "$SERVE" && echo "removed $SERVE"
  exit 0
fi

[ -n "$PUBKEY" ] || { echo "need --pubkey (the server's ~/.ssh/clipbridge_ed25519.pub)" >&2; exit 2; }
case "$PUBKEY" in ssh-ed25519\ *|ssh-rsa\ *|ecdsa-sha2-*) ;; *) echo "--pubkey does not look like an SSH public key" >&2; exit 2 ;; esac

mkdir -p "$HOME/.local/bin"
install -m 755 "$HERE/clipbridge-serve" "$SERVE"
echo "installed: $SERVE"

mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh" && touch "$AK" && chmod 600 "$AK"
body=$(printf '%s' "$PUBKEY" | awk '{print $2}')
opts="restrict,command=\"$SERVE\""
[ -n "$FROM" ] && opts="$opts,from=\"$FROM\""
grep -v "$body" "$AK" > "$AK.tmp" || true          # replace any earlier entry for this key
printf '%s %s\n' "$opts" "$PUBKEY" >> "$AK.tmp"
cat "$AK.tmp" > "$AK" && rm -f "$AK.tmp"
echo "authorized: $opts <key>"
command -v xclip >/dev/null || command -v wl-paste >/dev/null || echo "WARN: install xclip and/or wl-clipboard"
