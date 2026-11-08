#!/bin/sh
# Probe: sleep and wake. What blocks sleep now, sleep settings and wake sources, the last two weeks of sleep/wake events.
# Read-only. Run for "won't sleep", "drains asleep", "doesn't wake on lid open", "wakes by itself".
exec 2>/dev/null
has() { command -v "$1" >/dev/null 2>&1; }
sec() { [ -n "$open" ] && echo '```'; echo; echo "## $1"; echo '```'; open=1; }

if [ "$(uname)" = Darwin ]; then
  sec "what keeps it awake now (assertions)"
  pmset -g assertions | sed -n '/Listed by owning process/,$p' | grep -v -E '^\s*$' | head -25
  sec settings
  pmset -g | tail -n +2
  sec scheduled-wakes
  pmset -g sched
  # The power log keeps a few days. DarkWake = woke for maintenance with the screen off.
  sec "sleep and wake log (newest last)"
  pmset -g log | awk '$4 ~ /^(Sleep|Wake|DarkWake|Start|Shutdown)$/ && $5 != "Requests"' | cut -c1-180 | tail -30
else
  sec "what blocks sleep now (inhibitors)"
  has systemd-inhibit && systemd-inhibit --list --no-pager
  sec "sleep mode and wake sources"
  echo "mem_sleep: $(cat /sys/power/mem_sleep)"   # [s2idle] = modern standby, [deep] = S3
  [ -r /sys/power/pm_wakeup_irq ] && echo "last wakeup irq: $(cat /sys/power/pm_wakeup_irq)"
  grep enabled /proc/acpi/wakeup
  sec "lid and idle settings (logind)"
  grep -h -E '^[^#]*(HandleLid|LidSwitch|HoldoffTimeout|IdleAction|HandleSuspendKey|HandlePowerKey)' \
    /usr/lib/systemd/logind.conf /etc/systemd/logind.conf /etc/systemd/logind.conf.d/*.conf
  grep -h -E '^[^#]*(AllowSuspend|SuspendState|HibernateMode|HibernateDelaySec)' /etc/systemd/sleep.conf /etc/systemd/sleep.conf.d/*.conf
  sec "sleep and wake events, last 14 days"
  has journalctl && journalctl --since -14d --no-pager -q -o short-iso \
    -g 'Lid (closed|opened)|PM: suspend (entry|exit)|PM: hibernation|Power key pressed|Suspending system|System returned from sleep|Wakeup cause|failed to suspend|Freezing of tasks failed' |
    cut -c1-160 | tail -60
fi

echo '```'
exit 0
