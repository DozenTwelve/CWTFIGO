#!/bin/sh
# Probe: where the disk space went. Biggest directories on the root filesystem, in /var, in home and its caches.
# Read-only, sizes only. Without root, du skips unreadable dirs and undercounts them silently. Can take a minute.
# On macOS the terminal may ask once for access to Desktop/Documents/Downloads.
exec 2>/dev/null
sec() { [ -n "$open" ] && echo '```'; echo; echo "## $1"; echo '```'; open=1; }
h() { awk '{ s = $1; $1 = ""; if (s < 1048576) printf "%7dM %s\n", s / 1024, $0; else printf "%7.1fG %s\n", s / 1048576, $0 }'; }
top() { n=$1; shift; du -xsk "$@" | sort -rn | head -"$n" | h; }
# one level under a dir, same filesystem only (other mounts show as their mountpoint's few K); first line is the total
sub() { du -xk -d1 "$2" | sort -rn | head -"$1" | h; }

sec filesystems
df -h | grep -v -E '^(tmpfs|devtmpfs|overlay|shm|map |devfs)'

if [ "$(uname)" = Darwin ]; then
  sec home
  top 15 "$HOME"/* "$HOME"/.[!.]*
  sec "~/Library"
  top 10 "$HOME/Library"/*
  sec "~/Library/Caches"
  top 8 "$HOME/Library/Caches"/*
  sec trash
  top 1 "$HOME/.Trash"
else
  sec root
  sub 13 /
  sec /var
  sub 9 /var
  sec home
  top 15 "$HOME"/* "$HOME"/.[!.]*
  sec "~/.cache"
  top 8 "${XDG_CACHE_HOME:-$HOME/.cache}"/*
  sec trash
  top 1 "$HOME/.local/share/Trash"
fi

echo '```'
exit 0
