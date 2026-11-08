#!/bin/sh
# Probe: SMART health of every physical disk. Read-only, starts no self-test. Run for disk errors, I/O hangs, an old disk.
# Needs root: run it from a terminal so sudo can ask (cw gives it a tty). Serial numbers and WWNs are never printed.
# Each smartctl call gets a 30 s timeout where `timeout` exists, so a dying disk can't hang the probe.
# A disk in standby or sleep is left there (-n standby): the probe says so instead of spinning it up.
has() { command -v "$1" >/dev/null 2>&1; }
sec() { [ -n "$open" ] && echo '```'; echo; echo "## $1"; echo '```'; open=1; }

has smartctl || { echo "no smartctl (package smartmontools)"; exit 0; }
S=; [ "$(id -u)" = 0 ] || S=sudo
if [ -n "$S" ] && ! sudo -n true 2>/dev/null; then
  { [ -t 0 ] && sudo -v; } || { echo "needs sudo: run it from a terminal"; exit 0; }
fi
exec 2>/dev/null
T=; has timeout && T="timeout 30"

if has diskutil; then disks=$(diskutil list physical | awk '/^\/dev\/disk/{print $1}')
else
  for b in /sys/block/*; do
    case ${b##*/} in mmcblk*boot*|mmcblk*rpmb) ;; sd*|hd*|nvme*n*|mmcblk*) disks="$disks /dev/${b##*/}" ;; esac
  done
fi

for d in $disks; do
  sec "$d"
  out=$($S $T smartctl -n standby -a "$d")
  echo "$out" | grep -q -E 'Device is in (STANDBY|SLEEP)' && echo "asleep, not woken for this: run again while the disk is in use"
  echo "$out" | grep -v -i -E 'serial|wwn|eui|oui' | grep -i -E 'Model|Firmware Version|User Capacity|Total NVM Capacity|Rotation Rate|Form Factor|SATA Version|overall-health|SMART Health|Critical Warning|Reallocated|Pending|Uncorrect|CRC_Error|Power_On|Power On Hours|Wear|Percentage Used|Available Spare|Lifetime|Total_LBAs_Written|Data Units Written|Temperature|Program_Fail|Erase_Fail|Media|Unsafe Shutdowns|Error Information Log|Error Count|No Errors Logged'
  echo "$out" | awk '/^Num /{n=4} n&&n--'   # newest self-test results, if any were ever run
done

[ -n "$open" ] && echo '```'
exit 0
