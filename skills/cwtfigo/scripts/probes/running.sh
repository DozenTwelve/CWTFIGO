#!/bin/sh
# Probe: what actually runs, versus what is installed. Programs still running from a binary replaced on disk,
# commands shadowed on PATH, modules loaded from DKMS, where user units come from, what the desktop starts,
# compositor versions, this user's processes. Read-only, except that the user's shell rc files run (see PATH below).
# Run when an update "didn't take", for desktop, tray and window oddities, or before blaming the software's code.
#   running.sh [name...]   each name is checked as a command, a kernel module and a user unit, whichever it is
exec 2>/dev/null
has() { command -v "$1" >/dev/null 2>&1; }
sec() { [ -n "$open" ] && echo '```'; echo; echo "## $1"; echo '```'; open=1; }
# A non-interactive SSH shell has a shorter PATH than the user's terminals: ask their interactive login shell
# (its rc files run, as when they open a terminal; env, because fish quotes lists with spaces). An rc file that
# waits on something gets 10 s. ponytail: no timeout command (older macOS, some routers): no limit.
t=; has timeout && t="timeout 10"
P=$($t "${SHELL:-sh}" -lic env </dev/null | sed -n 's/^PATH=//p' | tail -1)
[ -n "$P" ] || P=$PATH
pathdirs() { echo "$P" | tr ':' '\n' | awk 'NF && !seen[$0]++'; }

if [ "$(uname)" = Darwin ]; then
  # No "(deleted)" here: a binary changed (ctime, which unpacking can't backdate the way it does mtime)
  # after its process started, or gone (old brew Cellar version cleaned up).
  sec "running from a binary changed or removed since start (this user)"
  now=$(date +%s)
  ps -U "$(id -u)" -o etime=,comm= | awk '{ e = $1; sub(/^ *[^ ]+ +/, ""); n = split(e, a, /[-:]/)
      s = a[n] + a[n-1] * 60 + (n > 2 ? a[n-2] * 3600 : 0) + (n > 3 ? a[n-3] * 86400 : 0); print s "\t" $0 }' |
    sort -t "$(printf '\t')" -k2,2 -k1,1nr | awk -F '\t' '!seen[$2]++' | while IFS="$(printf '\t')" read -r el p; do
      case $p in /*) ;; *) continue ;; esac
      if [ ! -e "$p" ]; then echo "gone: $p"
      else m=$(stat -f %c "$p"); [ "$m" -gt $((now - el)) ] && echo "changed $(date -r "$m" '+%F %R'): $p"; fi
    done | head -20
else
  sec "running from a deleted (replaced) binary"
  for d in /proc/[0-9]*; do
    l=$(readlink "$d/exe") || continue
    case $l in *' (deleted)') case $l in /memfd:*|/dev/*) ;; *) echo "${l% (deleted)} pid ${d#/proc/}" ;; esac ;; esac
  done | sort -u -k1,1 | head -20

  if has lsmod && has modinfo; then
    # updates/ and extra/ are where DKMS and other out-of-tree builds go; they win over the kernel's own module.
    sec "loaded modules from outside the kernel tree"
    lsmod | awk 'NR > 1 { print $1 }' | while read -r m; do
      f=$(modinfo -n "$m"); case $f in */updates/*|*/extra/*) echo "$m $f" ;; esac
    done
    has dkms && dkms status
  fi

  if has systemctl; then
    # Unit file and drop-ins: ~/.config overrides a package's unit of the same name.
    sec "running user services: unit file, drop-ins"
    systemctl --user show -p Id -p FragmentPath -p DropInPaths \
      $(systemctl --user list-units --type=service --state=running --no-legend --no-pager --plain | awk '{ print $1 }') |
      awk -F= '/^Id=/{ id = $2 } /^FragmentPath=/{ f = $2 } /^DropInPaths=/{ print id, f, $2 }' | sed 's/ *$//'
  fi

  c=${XDG_CONFIG_HOME:-$HOME/.config}
  sec "desktop autostart (Hyprland exec-once, niri spawn-at-startup, XDG autostart)"
  grep -rH -E '^[[:space:]]*exec(-once)?[[:space:]]*=' "$c/hypr" | sed "s|^$HOME|~|"
  grep -rH -E '^[[:space:]]*spawn-(sh-)?at-startup' "$c/niri" | sed "s|^$HOME|~|"
  grep -H '^Exec=' "$c"/autostart/*.desktop | sed "s|^$HOME|~|"

  sec "compositor and shell: running, version"
  ps -e -o comm= | grep -x -E 'Hyprland|niri|gamescope|sway|kwin_wayland|kwin_x11|gnome-shell|labwc|river|quickshell|qs|waybar' | sort -u | tr '\n' ' '; echo
  for b in Hyprland niri gamescope sway kwin_wayland gnome-shell quickshell; do has "$b" && echo "$b: $("$b" --version 2>&1 | head -1)"; done
fi

# Names on PATH more than once: the first one wins, and it may not be the one an update just replaced.
sec "commands on PATH more than once (first dir wins)"
pathdirs | while IFS= read -r d; do for f in "$d"/*; do [ -x "$f" ] && [ ! -d "$f" ] && echo "${f##*/}"; done; done | sort | uniq -d | head -40 | tr '\n' ' '; echo

for n in "$@"; do
  sec "$n"
  pathdirs | while IFS= read -r d; do [ -x "$d/$n" ] && ls -ld "$d/$n" | awk '{ $1 = $2 = $3 = $4 = $5 = ""; sub(/^ +/, ""); print }'; done
  has modinfo && modinfo -n "$n" | sed 's/^/module: /'
  has systemctl && systemctl --user cat "$n" | grep '^# /' | sed 's/^# /user unit: /'
done

sec "this user's processes"
{ ps -U "$(id -u)" -o comm= || cat /proc/[0-9]*/comm; } | sed 's|.*/||' | sort -u | tr '\n' ' '; echo

echo '```'
exit 0
