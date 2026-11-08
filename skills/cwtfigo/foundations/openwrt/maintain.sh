#!/bin/sh
# CWTFIGO-FOUNDATION: adapt to this host from its record, then delete this line. cw won't approve it before.
#
# maintain.sh (OpenWrt): package and firmware updates for this router. Runs as root, no sudo.
#   no argument: dry run. Release and whether a newer build exists, package lists refreshed (into RAM),
#                what's upgradable, packages added since flashing, free flash. Writes nothing to flash.
#   --apply:     upgrade the packages in UPGRADE that have an update, one at a time, then report.
#
# Never a bulk `opkg upgrade` / `apk upgrade`: kernel modules, core libraries and procd move together with the
# firmware image; a bulk upgrade breaks ABI or fills the flash. A new release comes by sysupgrade (LuCI Attended
# Sysupgrade, owut, or an image), done by the human: back up first (sysupgrade -b to a file that leaves the router),
# bake the "added since flashing" packages into the image or reinstall them after, and read the release notes
# before a major version: package options can be renamed and a service start again on its default config.
# OpenWrt 25.12 replaced opkg with apk; both are handled.
#
# This is where the host's habits live. UPGRADE lists the packages --apply may upgrade; empty = none.
# Core packages (kernel, kmod-*, base-files, busybox, libc, procd, ...) are refused even when listed.
UPGRADE=""
MIN_FREE_KB=8192   # flash that must stay free; --apply stops before going under it
# Nothing to clean: logs, package lists and /tmp live in RAM and go at reboot.

APPLY=; [ "$1" = --apply ] && APPLY=1
has() { command -v "$1" >/dev/null 2>&1; }
on() { case " $1 " in *" $2 "*) return 0;; esac; return 1; }
sec() { echo; echo "## $1"; }
O=/overlay; [ -d $O ] || O=/
free_kb() { df -Pk $O | awk 'NR==2{print $4}'; }
core() { echo "$1" | grep -qxE 'kernel|kmod-.*|base-files|busybox.*|libc|musl.*|procd.*|ubus.*|ubox|libubox.*|uci|libuci.*|netifd|fstools|mtd|apk.*|opkg'; }

if has apk; then PM=apk; elif has opkg; then PM=opkg; else echo "neither apk nor opkg: not an OpenWrt package system"; exit 1; fi
[ -n "$APPLY" ] && [ "$(id -u)" != 0 ] && { echo "--apply needs root"; exit 1; }

# Package lists go to /var (RAM on OpenWrt): refreshing writes nothing to flash. Mirrors are flaky: three tries.
refresh() { i=0; until $PM update >/dev/null 2>&1; do i=$((i+1)); [ $i -ge 3 ] && return 1; sleep 5; done; }
# One line per upgradable package: "name old -> new".
upgradable() {
  if [ $PM = apk ]; then apk upgrade --simulate 2>/dev/null | sed -n 's/.*Upgrading \([^ ]*\) (\(.*\)).*/\1 \2/p'
  else opkg list-upgradable 2>/dev/null | awk -F' - ' '{print $1, $2, "->", $3}'; fi
}
# Explicitly installed packages that aren't in the firmware image (/rom): a plain sysupgrade drops them.
added() {
  if [ $PM = apk ]; then
    if [ -f /rom/etc/apk/world ]; then grep -vxF -f /rom/etc/apk/world /etc/apk/world; else cat /etc/apk/world; fi
  else
    t=/tmp/cw-rom.$$
    ui() { awk '/^Package:/{p=$2} /^Status:.*user installed/{print p}' "$1" 2>/dev/null; }
    ui /rom/usr/lib/opkg/status > $t; ui /usr/lib/opkg/status | grep -vxF -f $t; rm -f $t
  fi
}
# What --apply would refuse for package $1: an upgrade of one package drags in newer dependencies, and a core one
# among them (libubox, kmod-*, libc) breaks the image's ABI the same way. Simulated first; empty = fine.
blocked() {
  if [ $PM = apk ]; then sim=$(apk upgrade --simulate "$1" 2>&1); else sim=$(opkg upgrade --noaction "$1" 2>&1); fi ||
    { echo "simulation failed: $(echo "$sim" | tail -1)"; return; }
  # apk: "(1/2) Upgrading libubox20240329 (...)"; opkg: "Upgrading libubox on root from ...", "Installing ...".
  x=$(echo "$sim" | awk '$1 ~ /^\([0-9]+\/[0-9]+\)$/ {print $3} $1 ~ /^(Upgrading|Installing|Downgrading|Removing)$/ {print $2}' |
    while read -r q; do [ "$q" != "$1" ] && core "$q" && printf ' %s' "$q"; done)
  [ -z "$x" ] || echo "would also change core:$x"
}
installed() { if [ $PM = apk ]; then grep -c '^P:' /lib/apk/db/installed; else opkg list-installed | wc -l; fi; }

before=$(free_kb); before=${before:-0}

sec firmware
. /etc/openwrt_release
echo "$DISTRIB_ID $DISTRIB_RELEASE $DISTRIB_REVISION $DISTRIB_TARGET, kernel $(uname -r)"
grep -h -o 'https\?://[^ ]*' /etc/apk/repositories.d/distfeeds.list /etc/opkg/distfeeds.conf 2>/dev/null | head -1 | sed 's/^/feed: /'
# owut / auc ask the sysupgrade server whether a newer build exists for this device; they install nothing.
if has owut; then owut check 2>&1 | head -20
elif has auc; then auc -c 2>&1 | head -20
else echo "newer release: no owut or auc here; see https://openwrt.org/releases/start or the fork's site"; fi

sec packages
refresh || echo "$PM update failed 3 times: the list below may be stale or empty"
echo "manager: $PM, installed: $(installed)"
up=$(upgradable)
if [ -n "$up" ]; then
  echo "upgradable: $(echo "$up" | wc -l | tr -d ' ')"
  echo "$up" | while read -r n rest; do
    if core "$n"; then f="  (core: comes with the firmware)"
    elif on "$UPGRADE" "$n"; then b=$(blocked "$n"); f="  (in UPGRADE${b:+, --apply skips it: $b})"; else f=; fi
    echo "  $n $rest$f"
  done
else
  echo "upgradable: none"
fi

sec "added since flashing (lost on a plain sysupgrade unless baked into the image)"
a=$(added | tr '\n' ' '); echo "${a:-(none)}"

if [ -n "$APPLY" ]; then
  sec apply
  [ -n "$UPGRADE" ] || echo "UPGRADE is empty: nothing to upgrade"
  for p in $UPGRADE; do
    if core "$p"; then echo "skip $p: core package, comes with the firmware"; continue; fi
    echo "$up" | grep -q "^$p " || { echo "$p: current"; continue; }
    b=$(blocked "$p"); [ -n "$b" ] && { echo "skip $p: $b"; continue; }
    [ "$(free_kb)" -lt "$MIN_FREE_KB" ] && { echo "stop: under ${MIN_FREE_KB}K free on flash"; break; }
    echo "+ $PM upgrade $p"
    $PM upgrade "$p" || echo "  failed: $p"
  done
fi

sec report
[ -n "$APPLY" ] && echo "mode: applied" || echo "mode: dry run, nothing changed on flash"
echo "free on $O: $((before/1024))M before, $(free_kb | awk '{print int($1/1024)}')M now; /tmp (RAM): $(df -Pk /tmp | awk 'NR==2{print int($4/1024)}')M free"
# A package upgrade keeps edited config files and puts the new default beside them.
n=$(find /etc -name '*-opkg' -o -name '*.apk-new' 2>/dev/null)
[ -n "$n" ] && { echo "config to merge:"; echo "$n" | sed 's/^/  /'; } || echo "no new config files to merge"
