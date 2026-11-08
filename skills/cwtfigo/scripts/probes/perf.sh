#!/bin/sh
# Probe: why slow, hot or stuttering right now. Top processes, memory pressure and swap, CPU and GPU clocks and
# throttling, temperatures and fans, power source and battery; on macOS also hang and spin reports. Read-only.
# One snapshot: run it while the problem is happening, and again when it's fine, then compare.
exec 2>/dev/null
has() { command -v "$1" >/dev/null 2>&1; }
sec() { [ -n "$open" ] && echo '```'; echo; echo "## $1"; echo '```'; open=1; }
k() { awk '{ printf "%d", $1 / 1000 }' "$1"; }   # milli- or kilo- units to whole ones
mac=; [ "$(uname)" = Darwin ] && mac=1

sec load
uptime

sec top-cpu
if [ -n "$mac" ]; then ps -Ao pcpu,pmem,comm -r | head -12 | sed 's|/.*/||'
elif ps -eo pcpu,pmem,comm --sort=-pcpu >/dev/null; then ps -eo pcpu,pmem,comm --sort=-pcpu | head -12
else top -b -n1 | head -15; fi

sec top-memory
if [ -n "$mac" ]; then ps -Ao pmem,rss,comm -m | head -11 | sed 's|/.*/||'
else ps -eo pmem,rss,comm --sort=-rss | head -11; fi

sec memory-pressure
if [ -n "$mac" ]; then
  memory_pressure | tail -1
  sysctl -n vm.swapusage
  vm_stat | grep -E 'compressor|Swapins|Swapouts'
else
  # PSI: share of time tasks waited on CPU, memory or I/O. "some avg10" above ~10 is felt.
  for r in cpu memory io; do [ -r /proc/pressure/$r ] && echo "$r: $(tr '\n' ' ' < /proc/pressure/$r)"; done
  tail -n +2 /proc/swaps
  echo "swappiness $(cat /proc/sys/vm/swappiness)"
  has zramctl && zramctl
fi

sec cpu
if [ -n "$mac" ]; then
  pmset -g therm | grep -v '^$'
else
  c=/sys/devices/system/cpu/cpu0/cpufreq
  [ -d $c ] && echo "driver=$(cat $c/scaling_driver) governor=$(cat $c/scaling_governor) epp=$(cat $c/energy_performance_preference || echo -) max=$(k $c/scaling_max_freq)MHz hw_max=$(k $c/cpuinfo_max_freq)MHz"
  [ -r /sys/devices/system/cpu/intel_pstate/no_turbo ] && echo "intel_pstate no_turbo=$(cat /sys/devices/system/cpu/intel_pstate/no_turbo)"
  [ -r /sys/devices/system/cpu/cpufreq/boost ] && echo "boost=$(cat /sys/devices/system/cpu/cpufreq/boost)"
  echo "now MHz: $(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq | awk '{ printf "%d ", $1 / 1000 }')"
  for t in core package; do
    cat /sys/devices/system/cpu/cpu*/thermal_throttle/${t}_throttle_count | awk -v t=$t '{ s += $1 } END { if (NR) print t " throttle events since boot: " s }'
  done
  # Intel RAPL power limits (long term / short term), the usual cap on sustained load
  for z in /sys/class/powercap/intel-rapl:[0-9]; do
    [ -r $z/constraint_0_power_limit_uw ] || continue
    l="$(cat $z/name):"
    for i in 0 1; do [ -r $z/constraint_${i}_power_limit_uw ] && l="$l $(cat $z/constraint_${i}_name)=$(awk '{ print int($1 / 1000000) }' $z/constraint_${i}_power_limit_uw)W"; done
    echo "$l"
  done
fi

if [ -z "$mac" ]; then
  sec gpu
  for g in /sys/class/drm/card[0-9]; do
    d=$g/device; drv=$(readlink $d/driver); l="${g##*/} ${drv##*/}"
    [ -r $d/gpu_busy_percent ] && l="$l busy=$(cat $d/gpu_busy_percent)%"
    [ -r $d/pp_dpm_sclk ] && l="$l sclk=$(awk '/\*/{ print $2 }' $d/pp_dpm_sclk)"
    [ -r $g/gt_act_freq_mhz ] && l="$l now=$(cat $g/gt_act_freq_mhz)MHz max=$(cat $g/gt_max_freq_mhz)MHz"
    echo "$l"
  done
  # nvidia-smi hangs on a wedged driver or a GPU fallen off the bus, which is when this probe runs: 15 s.
  T=; has timeout && T="timeout 15"
  has nvidia-smi && $T nvidia-smi --query-gpu=name,utilization.gpu,clocks.sm,power.draw,temperature.gpu,memory.used,memory.total --format=csv,noheader

  sec temps-fans
  for z in /sys/class/thermal/thermal_zone*; do [ -r $z/temp ] && echo "$(cat $z/type) $(k $z/temp)C"; done
  for h in /sys/class/hwmon/hwmon*; do
    t=$(cat $h/temp*_input | sort -n | tail -1); f=$(cat $h/fan*_input | tr '\n' ' ')
    [ -n "$t$f" ] && echo "hwmon $(cat $h/name):${t:+ max $(echo $t | awk '{ print int($1 / 1000) }')C}${f:+ fan rpm $f}"
  done
  grep -E '^(speed|level)' /proc/acpi/ibm/fan
fi

sec power
if [ -n "$mac" ]; then
  pmset -g batt | tail -n +2
  pmset -g | grep -i lowpowermode
else
  for p in /sys/class/power_supply/*; do
    [ "$(cat $p/scope)" = Device ] && continue   # a mouse or headset battery
    case $(cat $p/type) in
      Mains) echo "${p##*/} online=$(cat $p/online)" ;;
      Battery)
        f=$(cat $p/energy_full || cat $p/charge_full); fd=$(cat $p/energy_full_design || cat $p/charge_full_design)
        h=$(echo "$f $fd" | awk '$2 > 0 { printf "%d%%", 100 * $1 / $2 }')
        echo "${p##*/} $(cat $p/status) $(cat $p/capacity)% health=${h:--} cycles=$(cat $p/cycle_count || echo -) thresholds=$(cat $p/charge_control_start_threshold || echo -)-$(cat $p/charge_control_end_threshold || echo -)" ;;
    esac
  done
  has powerprofilesctl && echo "power profile: $(powerprofilesctl get)"
fi

if [ -n "$mac" ]; then
  # Hang = app froze, spin = beachball, cpu_resource/diskwrites = macOS flagged a hog.
  sec "diagnostic reports, last 30 days, by process and type"
  find /Library/Logs/DiagnosticReports "$HOME/Library/Logs/DiagnosticReports" -type f -mtime -30 | grep -v -E '/(Analytics|SFA-|proactive_event)' |
    sed 's|.*/||' | sed -E 's/[-_][0-9]{4}-[0-9]{2}-[0-9]{2}.*\.([a-z_.]+)$/ \1/' | sort | uniq -c | sort -rn | head -20
fi

echo '```'
exit 0
