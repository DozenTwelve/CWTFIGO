#!/bin/sh
# First-visit collector: what this machine is, nothing more. POSIX sh, read-only, no deps.
# No logs, ports, processes or sensors: those are probes/, run only when a request needs them.
# Usage: ssh <alias> sh -s < collect.sh   |   sh collect.sh
# Output: Markdown, one "## section" per block with raw output fenced; stable order so two runs diff cleanly.

exec 2>/dev/null

has() { command -v "$1" >/dev/null 2>&1; }
sec() { [ -n "$open" ] && echo '```'; echo; echo "## $1"; echo '```'; open=1; }
cnt() { wc -l | tr -d ' '; }
hash() { if has sha256sum; then sha256sum; else shasum -a 256; fi | cut -c1-16; }

sec identity
echo "hostname: $(hostname 2>/dev/null || uname -n)"
echo "uid: $(id -u)"
# Only a hash is printed: enough to tell "same machine?", useless as a tracker.
# machine-id / hardware UUID survive NIC swaps; MAC is the fallback for routers that have neither.
id=$(cat /etc/machine-id 2>/dev/null)
has ioreg && id=$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformUUID/{print $4}')
[ -z "$id" ] && for d in /sys/class/net/*; do [ -e "$d/device" ] && id="$id$(cat "$d/address")"; done
# None of them (a container, a box without NICs): no id line. The hash of nothing would be one id every such box shares.
[ -n "$id" ] && echo "id: $(printf '%s' "$id" | hash)"

sec os
uname -srm
[ -r /etc/os-release ] && grep -E '^(PRETTY_NAME|ID|ID_LIKE|VERSION_ID)=' /etc/os-release
has sw_vers && sw_vers
[ -r /etc/openwrt_release ] && grep -E '^DISTRIB_(ID|RELEASE|TARGET)=' /etc/openwrt_release
has steamos-readonly && echo "steamos-readonly: $(steamos-readonly status)"

sec hardware
for f in sys_vendor product_name product_version; do
  [ -r /sys/class/dmi/id/$f ] && echo "$f: $(cat /sys/class/dmi/id/$f)"
done
[ -r /proc/device-tree/model ] && echo "model: $(tr -d '\0' < /proc/device-tree/model)"
[ -r /tmp/sysinfo/model ] && echo "model: $(cat /tmp/sysinfo/model)"
has sysctl && sysctl hw.model machdep.cpu.brand_string hw.memsize 2>/dev/null
[ -r /proc/cpuinfo ] && grep -m1 'model name' /proc/cpuinfo
[ -r /proc/meminfo ] && grep MemTotal /proc/meminfo
has lspci && lspci | grep -i -E 'vga|3d|display'

sec packages
has pacman && echo "pacman: $(pacman -Q | cnt)"
for h in paru yay; do has $h && echo "aur helper: $h"; done
has dpkg && echo "dpkg: $(dpkg -l | grep -c '^ii')"
has rpm && echo "rpm: $(rpm -qa | cnt)"
has opkg && echo "opkg: $(opkg list-installed | cnt)"
has apk && echo "apk: $(apk list --installed | cnt)"
has brew && echo "brew: $(brew list --formula | cnt) formulae, $(brew list --cask | cnt) casks"
has flatpak && echo "flatpak: $(flatpak list --app | cnt)"
has snap && echo "snap: $(snap list | tail -n +2 | cnt)"

echo '```'
exit 0
