#!/bin/sh
# CWTFIGO-FOUNDATION: adapt to this host from its record, then delete this line. cw won't approve it before.
#
# check.sh (macOS): READ-ONLY health and drift check. One line per check: OK / BAD / WARN / INFO.
# Grow it per machine: every fix that could silently revert gets a line here.
# No global 2>/dev/null: a command that fails must show its error, never pass as an empty answer (= OK).

ok()  { echo "OK   $1"; }
bad() { echo "BAD  $1"; }
warn() { echo "WARN $1"; }
info() { echo "INFO $1"; }

# Disk: the Data volume is where everything the user does lives.
u=$(df -Pk /System/Volumes/Data | awk 'NR==2{sub("%","",$5); print $5}')
f=$(df -Pk /System/Volumes/Data | awk 'NR==2{print int($4/1048576)}')
if [ -z "$u" ] || [ -z "$f" ]; then warn "disk: no usage from df /System/Volumes/Data (error above)"
elif [ "$u" -ge 90 ]; then bad "disk ${u}% full, ${f}G free"; else ok "disk ${u}%, ${f}G free"; fi

# Memory: pressure, not "used". macOS fills RAM with cache on purpose.
p=$(memory_pressure | awk -F': ' '/free percentage/{sub("%","",$2); print $2}')
if [ -z "$p" ]; then warn "memory: no free percentage from memory_pressure (error above)"
elif [ "$p" -le 10 ]; then bad "memory free ${p}%"; else ok "memory free ${p}%"; fi
s=$(sysctl -n vm.swapusage | awk '{print $6}')
[ -n "$s" ] && info "swap $s used" || warn "swap: no answer from sysctl vm.swapusage (error above)"

# Thermal throttling since boot.
t=$(pmset -g therm)
if [ -z "$t" ]; then warn "thermal: no answer from pmset -g therm (error above)"
elif echo "$t" | grep -q 'No thermal warning level has been recorded'; then ok "no thermal warning since boot"
else warn "thermal: $(echo "$t" | grep -v '^Note' | tr '\n' ' ')"; fi

# Battery (laptops): the same "Maximum Capacity" System Settings shows.
b=$(system_profiler SPPowerDataType | awk -F': ' '/Cycle Count/{c=$2} /Condition/{k=$2} /Maximum Capacity/{m=$2} END{if(c!="") print (m=="" ? "?" : m), c, (k=="" ? "?" : k)}')
if [ -n "$b" ]; then
  set -- $b
  # Older macOS has no Maximum Capacity line: say so instead of comparing an empty value.
  if [ "$1" = "?" ]; then warn "battery: no Maximum Capacity in system_profiler SPPowerDataType, $2 cycles, $3"
  else [ "$3" = Normal ] && [ "${1%\%}" -ge 80 ] && ok "battery $1, $2 cycles, $3" || warn "battery $1, $2 cycles, $3"; fi
fi

# Homebrew: brew doctor exits 1 on any warning; that's the finding, not a failure. Warnings go to stderr.
# Exit 1 with no warning is brew doctor itself failing.
if command -v brew >/dev/null; then
  d=$(brew doctor 2>&1) && ok "brew doctor clean" || {
    w=$(echo "$d" | sed -n 's/^Warning: //p')
    [ -n "$w" ] && echo "$w" | while read -r l; do warn "brew doctor: $l"; done || warn "brew doctor failed: $(echo "$d" | tail -1)"; }
fi

# mise: only problems count. Its warnings (new mise version, shadowed shims) are routine.
if command -v mise >/dev/null; then
  d=$(mise doctor 2>&1); x=$?; n=$(echo "$d" | sed -n 's/^\([0-9]*\) problems* found.*/\1/p')
  if [ -n "$n" ]; then bad "mise doctor: $n problem(s)"
  elif [ $x = 0 ]; then ok "mise doctor: no problems"
  else warn "mise doctor failed: $(echo "$d" | tail -1)"; fi
fi

info "load $(sysctl -n vm.loadavg | awk '{print $2}') on $(sysctl -n hw.ncpu) cores, up $(uptime | sed 's/.*up \([^,]*\),.*/\1/')"

# Host-specific checks go below this line.
