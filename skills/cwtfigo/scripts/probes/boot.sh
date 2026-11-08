#!/bin/sh
# Probe: boot and login. How long boot took and what held it up, what starts at boot and login,
# recent reboots and how the last one ended, kernel panics. Read-only. Run for slow boot, unexpected reboots, "what runs at startup".
exec 2>/dev/null
has() { command -v "$1" >/dev/null 2>&1; }
sec() { [ -n "$open" ] && echo '```'; echo; echo "## $1"; echo '```'; open=1; }

if [ "$(uname)" = Darwin ]; then
  sec reboots
  last reboot shutdown | head -8

  # btn_rst / forceReset = power button held; ResetCounter = watchdog or power loss.
  sec "panic and reset reports, last 30 days"
  find /Library/Logs/DiagnosticReports \( -name '*.panic' -o -name 'panic-*' -o -name 'ResetCounter*' -o -name 'forceReset*' \) -mtime -30 |
    while IFS= read -r f; do printf '%s  %s\n' "${f##*/}" "$(grep -o 'panic([^"]*' "$f" | head -1 | sed 's/\\n.*//' | cut -c1-80)"; done

  for d in "$HOME/Library/LaunchAgents" /Library/LaunchAgents /Library/LaunchDaemons; do
    sec "non-Apple plists in $d"
    ls "$d" | grep -v '^com\.apple\.'
  done

  sec "loaded launchd jobs, non-Apple (pid status label)"
  launchctl list | awk 'NR > 1 && $3 !~ /^com\.apple\./' | sort -k3
else
  if has systemd-analyze; then
    sec boot-time
    systemd-analyze
    sec slowest-units
    systemd-analyze blame --no-pager | head -12
    sec critical-chain
    systemd-analyze critical-chain --no-pager | head -15
  fi

  if has journalctl; then
    sec boots
    journalctl --list-boots --no-pager | tail -6
    # A clean shutdown ends with systemd-shutdown / "Reached target ... Shutdown"; anything else ended abruptly.
    sec "how the previous boot ended"
    journalctl -b -1 -n 6 --no-pager -q -o short-iso | cut -c1-200
  fi

  sec "kernel panic dumps (pstore)"
  ls /sys/fs/pstore /var/lib/systemd/pstore

  if has systemctl; then
    sec enabled-services
    systemctl list-unit-files --state=enabled --type=service --no-legend --no-pager | awk '{ printf "%s ", $1 } END { print "" }'
    sec enabled-user-units
    systemctl --user list-unit-files --state=enabled --no-legend --no-pager | awk '{ printf "%s ", $1 } END { print "" }'
  fi

  sec autostart
  ls /etc/xdg/autostart "${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
fi

echo '```'
exit 0
