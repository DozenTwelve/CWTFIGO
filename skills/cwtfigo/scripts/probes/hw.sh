#!/bin/sh
# Probe: hardware and drivers (Linux). PCI and USB devices with the driver bound to each (NO-DRIVER = nothing claimed it),
# kernel firmware and driver complaints this boot, radio kill switches. Read-only, sysfs only (lspci adds names if present).
# Run for "device not working", missing Wi-Fi/Bluetooth/webcam/fingerprint, firmware errors. Serial numbers are not read.
exec 2>/dev/null
has() { command -v "$1" >/dev/null 2>&1; }
sec() { [ -n "$open" ] && echo '```'; echo; echo "## $1"; echo '```'; open=1; }
drv() { d=$(readlink "$1/driver"); echo "${d##*/}"; }

[ -d /sys/bus/pci ] || [ -d /sys/bus/usb ] || { echo "no sysfs: Linux only"; exit 0; }

sec "PCI (slot class vendor:device driver)"
for d in /sys/bus/pci/devices/*; do
  s=${d##*/}; v=$(drv "$d"); n=
  [ -z "$v" ] && has lspci && n="  $(lspci -s "$s" | cut -d' ' -f2-)"
  echo "$s $(cat $d/class) $(cut -c3- $d/vendor):$(cut -c3- $d/device) ${v:-NO-DRIVER}$n"
done

sec "USB (bus-port vendor:product name, interface drivers)"
for d in /sys/bus/usb/devices/*; do
  [ -f $d/idVendor ] || continue
  [ "$(cat $d/idVendor)" = 1d6b ] && continue   # root hubs
  v=; for i in "$d":*; do x=$(drv "$i"); [ -n "$x" ] && v="$v $x"; done
  echo "${d##*/} $(cat $d/idVendor):$(cat $d/idProduct) $(cat $d/product | tr ' ' _) drivers:${v:- NONE}"
done

sec "kernel: firmware and driver complaints this boot"
{ journalctl -k -b -p warning --no-pager -q -o cat || dmesg; } |
  grep -i -E 'firmware|failed|no driver|not supported|missing|unknown|timeout' | sort | uniq -c | sort -rn | head -25

sec rfkill
for r in /sys/class/rfkill/*; do echo "$(cat $r/name) $(cat $r/type) soft=$(cat $r/soft) hard=$(cat $r/hard)"; done

echo '```'
exit 0
