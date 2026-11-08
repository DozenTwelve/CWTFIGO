#!/bin/sh
# Probe: recent errors, crashes, and what packages changed lately. Read-only.
# Logs can hold names, paths and tokens: redact before quoting or storing.
exec 2>/dev/null
has() { command -v "$1" >/dev/null 2>&1; }
sec() { [ -n "$open" ] && echo '```'; echo; echo "## $1"; echo '```'; open=1; }

if [ "$(uname)" = Darwin ]; then
  # Unified log: last boot is too slow and huge; faults for 1h take ~3 s, errors for 10m ~1 s but are mostly noise, so count them.
  f=$(/usr/bin/log show --last 1h --predicate 'messageType == fault' --style compact | awk 'NR > 1')
  sec "faults, last hour, by process"
  [ -n "$f" ] && echo "$f" | sed 's/^[^ ]* [^ ]* [^ ]* *//; s/\[.*//' | sort | uniq -c | sort -rn | head -10
  sec "faults, last 10"
  echo "$f" | tail -10 | cut -c1-200
  sec "errors, last 10 minutes, by process"
  /usr/bin/log show --last 10m --predicate 'messageType == error' --style compact |
    sed '1d; s/^[^ ]* [^ ]* [^ ]* *//; s/\[.*//' | sort | uniq -c | sort -rn | head -10

  sec "crash reports (system, then user)"
  ls -t /Library/Logs/DiagnosticReports | head -10
  ls -t "$HOME/Library/Logs/DiagnosticReports" | head -10

  sec "recent installs (system and pkg)"
  grep 'Installed "' /var/log/install.log | tail -10 | cut -c1-160
  if has brew; then
    sec "brew, last changed (Cellar mtime)"
    { ls -ltD '%F %R' "$(brew --cellar)" | awk 'NF >= 8 { print $6, $7, $8 }'
      ls -ltD '%F %R' "$(brew --prefix)/Caskroom" | awk 'NF >= 8 { print $6, $7, $8, "(cask)" }'; } | sort -r | head -15
  fi
else
  sec errors
  # Outside adm/systemd-journal, journalctl shows only this user's messages and says so on stderr, which is dropped here:
  # an empty section would read as "no errors".
  if has journalctl && [ "$(id -u)" != 0 ] && ! id -Gn | grep -qwE 'adm|systemd-journal|wheel'; then
    echo "journal: system messages not readable as $(id -un) (not in adm/systemd-journal): empty below means unknown, not clean"
  fi
  has journalctl && journalctl -p err -b --no-pager -q | tail -20
  # One daemon can fill the small logread buffer with one error: count per daemon ("... daemon.err name[pid]: ..."), then a short tail.
  if has logread; then
    e=$(logread | grep -i -E 'err|fail')
    echo "logread, by daemon:"
    [ -n "$e" ] && echo "$e" | awk '{ p = $7; sub(/\[.*/, "", p); sub(/:$/, "", p); print p }' | sort | uniq -c | sort -rn | head -10
    sec "errors, last 10 (logread)"
    echo "$e" | tail -10 | cut -c1-200
  fi
  # After a freeze or crash the user has usually rebooted already: this boot's log knows nothing about it.
  if has journalctl; then
    sec "errors, previous boot"
    journalctl -p err -b -1 --no-pager -q | tail -20
  fi

  if has coredumpctl; then
    sec "core dumps (systemd-coredump)"
    coredumpctl list --no-pager -q | tail -10
    sec "newest core dump: what, when, stack"
    coredumpctl info -1 --no-pager | awk '/^ *(Executable|Signal|Timestamp):/ { print } /Stack trace/ && !s { n = 26; s = 1 } n && n--'
  fi

  sec "recent package changes"
  [ -r /var/log/pacman.log ] && grep -E '\[ALPM\] (installed|upgraded|downgraded|removed) ' /var/log/pacman.log | tail -15
  [ -r /var/log/dpkg.log ] && grep -E '^[^ ]+ [^ ]+ (install|upgrade|remove|purge) ' /var/log/dpkg.log | tail -15
  # opkg keeps no log; a package's control file is written when it is installed. apk keeps none either: world's mtime is the last explicit add/del.
  [ -d /usr/lib/opkg/info ] && ls -lt /usr/lib/opkg/info/*.control | head -15 | awk '{ print $6, $7, $8, $9 }' | sed 's|/usr/lib/opkg/info/||; s|\.control$||'
  [ -f /etc/apk/world ] && ls -l /etc/apk/world
fi

# An upgrade isn't running until the processes using it restart: compare the last package change with the boot.
when() { date -d "@$1" '+%F %R' || date -r "$1" '+%F %R'; }
mt() { stat -c %Y "$1" || stat -f %m "$1"; }
boot=$(awk '/^btime/ { print $2 }' /proc/stat) || boot=
[ -n "$boot" ] || boot=$(sysctl -n kern.boottime | sed 's/^{ sec = \([0-9]*\).*/\1/')
pkg=; how=
for f in /var/lib/pacman/local:pacman /var/lib/dpkg/status:dpkg /usr/lib/opkg/status:opkg /lib/apk/db/installed:apk; do
  [ -e "${f%:*}" ] && pkg=$(mt "${f%:*}") && how=${f#*:} && break
done
if [ -z "$pkg" ] && has brew; then pkg=$(for d in "$(brew --cellar)"/*; do mt "$d"; done | sort -n | tail -1); how=brew; fi
if [ -n "$pkg" ] && [ -n "$boot" ]; then
  sec "reboot since the last package change"
  [ "$pkg" -gt "$boot" ] && r="NOT rebooted since" || r="rebooted since"
  echo "$r: last $how change $(when "$pkg"), boot $(when "$boot")"
fi

echo '```'
exit 0
