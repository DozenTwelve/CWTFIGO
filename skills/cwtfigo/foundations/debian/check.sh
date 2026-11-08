#!/bin/sh
# CWTFIGO-FOUNDATION: adapt to this host from its record, then delete this line. cw won't approve it before.
#
# check.sh (Debian, Ubuntu and derivatives): READ-ONLY health and drift check. One line per check: OK / BAD / WARN / INFO.
# Grow it per machine: every fix that could silently revert gets a line here.
# No global 2>/dev/null: a command that fails must show its error, never pass as an empty answer (= OK).

has() { command -v "$1" >/dev/null 2>&1; }
ok()   { echo "OK   $1"; }
bad()  { echo "BAD  $1"; }
warn() { echo "WARN $1"; }
info() { echo "INFO $1"; }

# Disk: each of / /boot /home once (often the same filesystem). A separate /boot is small and fills with old kernels.
df -Pk / /boot /home | awk 'NR>1 && !seen[$6]++ {
  u=$5+0; f=($4>=1048576) ? int($4/1048576) "G" : int($4/1024) "M"
  printf "%s disk %s %d%%, %s free\n", (u>=90 ? "BAD " : "OK  "), $6, u, f }'

# Failed units. If systemctl itself fails (no user manager, no bus), say so instead of reporting none.
units() {
  if out=$(systemctl $2 --failed --no-legend --plain); then
    out=$(echo "$out" | awk 'NF{printf " %s", $1}')
    [ -n "$out" ] && warn "failed $1 units:$out" || ok "no failed $1 units"
  else
    warn "systemctl $2 --failed did not answer (error above)"
  fi
}
units system
units user --user

# Reboot pending. Packages that need one write /run/reboot-required (Ubuntu always, Debian when the package or
# unattended-upgrades does). Debian's kernel packages don't always: also compare the running kernel to the newest installed.
if [ -f /run/reboot-required ]; then
  warn "reboot required by:$(sort -u /run/reboot-required.pkgs 2>/dev/null | awk '{printf " %s", $0}')"
fi
# Flavours sit side by side (Pi OS rpi-v8 and rpi-2712, Ubuntu generic and lowlatency, Debian amd64 and rt-amd64):
# compare only with kernels of the running one's flavour, the part after the version (6.12.25+rpt-rpi-v8: rpi-v8).
fl() { echo "$1" | sed -E 's/^[0-9.]+(-[0-9]+)?(\+[a-z0-9]+)?-//'; }
k=$(uname -r); f=$(fl "$k")
n=$(for v in /boot/vmlinuz-*; do v=${v#/boot/vmlinuz-}; [ "$(fl "$v")" = "$f" ] && echo "$v"; done | sort -V | tail -1)
if [ -z "$n" ]; then info "running kernel $k, no /boot/vmlinuz-* of its flavour ($f) to compare (Raspberry Pi firmware kernel, container)"
elif [ "$n" = "$k" ]; then ok "running the newest installed kernel $k"
else warn "running kernel $k, newest installed $n: reboot pending"; fi

# dpkg: half-installed or unconfigured packages block every later apt run. --audit is silent when all is well.
out=$(dpkg --audit) && { [ -n "$out" ] && warn "dpkg --audit: $(echo "$out" | head -3 | tr '\n' ' ')(sudo dpkg --configure -a)" || ok "dpkg state clean"; } ||
  warn "dpkg --audit failed (error above)"

# Pending upgrades, from the local package lists: only as fresh as the last apt-get update (needs root, not run here).
# Simulation needs no root. Held packages (apt-mark showhold) are never in it: apt upgrade leaves them alone.
if [ -z "$(find /var/lib/apt/lists -maxdepth 1 -name '*Packages*' 2>/dev/null)" ]; then
  warn "no apt package lists: pending upgrades unknown (sudo apt-get update)"
else
  age=; [ -z "$(find /var/lib/apt/lists -maxdepth 1 -name '*Packages*' -mtime -7)" ] && age=", lists older than 7 days"
  if ! s=$(apt-get -s -o Debug::NoLocking=1 upgrade --with-new-pkgs); then warn "apt-get -s upgrade failed (error above)"
  elif p=$(echo "$s" | grep -c '^Inst '); sec=$(echo "$s" | grep -c '^Inst .*-security'); [ "$sec" -gt 0 ]; then
    warn "apt: $p pending, $sec from security$age"
  elif [ "$p" -gt 0 ]; then info "apt: $p pending$age"
  else ok "apt: all current$age"; fi
fi
h=$(apt-mark showhold | awk 'NF{printf " %s", $1}')
[ -n "$h" ] && info "held:$h"

# Unattended upgrades: on by default on Ubuntu, opt-in on Debian. Say which, so a missing security update has a reason.
if [ -f /usr/bin/unattended-upgrade ]; then
  case $(apt-config shell u APT::Periodic::Unattended-Upgrade) in
    *"'0'"|'') info "unattended-upgrades installed, APT::Periodic::Unattended-Upgrade off" ;;
    *) info "unattended-upgrades on" ;;
  esac
fi

# Config files dpkg left beside the live one: the package's new version (.dpkg-dist, .ucf-dist) was not installed
# because the local one was changed. Like .pacnew: merge by hand. find can't see into root-only dirs.
n=$(find /etc \( -name '*.dpkg-dist' -o -name '*.dpkg-new' -o -name '*.ucf-dist' -o -name '*.ucf-new' \) 2>/dev/null | awk 'NF{printf " %s", $0}')
[ -n "$n" ] && warn "to merge:$n" || ok "no .dpkg-dist"

# Firewall: installed is not enabled. ufw with ENABLED=no means no rules even while ufw.service is active.
if [ -f /etc/ufw/ufw.conf ]; then
  if ! grep -q '^ENABLED=yes' /etc/ufw/ufw.conf; then warn "ufw installed but ENABLED=no: no firewall, even with ufw.service active (sudo ufw enable)"
  elif systemctl is-active -q ufw; then ok "ufw enabled and active"
  else warn "ufw ENABLED=yes but ufw.service not active: rules not loaded (sudo systemctl enable --now ufw)"; fi
  systemctl is-active -q nftables && warn "nftables.service active alongside ufw: two firewalls"
elif has firewall-cmd; then
  systemctl is-active -q firewalld && ok "firewalld active" || warn "firewalld installed but not active: no firewall"
elif systemctl is-active -q nftables; then ok "nftables.service active (rules from /etc/nftables.conf)"
else info "no firewall (ufw, firewalld, nftables.service): fine behind NAT, not on open Wi-Fi or with open ports"; fi

# sshd password auth: first setting wins, drop-ins are included at the top of sshd_config. Unset = yes.
# Read from the files (sshd -T needs root); a Match block can still override it.
# The unit is ssh here; Ubuntu 22.10+ starts it from ssh.socket, so the service is inactive until a login.
if systemctl is-active -q ssh.service ssh.socket; then
  p=$(cat /etc/ssh/sshd_config.d/*.conf /etc/ssh/sshd_config 2>/dev/null | awk 'tolower($1)=="passwordauthentication"{print $2; exit}')
  info "sshd active, PasswordAuthentication ${p:-yes (default)}"
fi

# Journal and coredumps.
# Outside adm/systemd-journal (wheel on Arch), journalctl sees only this user's own journal: its size too.
j=; [ "$(id -u)" != 0 ] && ! id -Gn | grep -qwE 'adm|systemd-journal|wheel' && j=" (this user's only: not in adm/systemd-journal)"
has journalctl && info "journal $(journalctl --disk-usage | grep -o '[0-9.]*[KMGT]' | head -1)$j"
[ -d /var/lib/systemd/coredump ] && { c=$(ls /var/lib/systemd/coredump | wc -l); [ "$c" -gt 0 ] && info "coredumps: $c (coredumpctl list)"; }

info "load $(cut -d' ' -f1-3 /proc/loadavg) on $(nproc) cores, $(uptime -p)"

# Host-specific checks go below this line: drift checks for this host's tweaks (a held kernel, a pinned repo, a masked
# unit, a firewall rule) and parked issues' recheck lines from notes.md.
