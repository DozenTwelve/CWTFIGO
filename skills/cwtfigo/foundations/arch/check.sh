#!/bin/sh
# CWTFIGO-FOUNDATION: adapt to this host from its record, then delete this line. cw won't approve it before.
#
# check.sh (Arch): READ-ONLY health and drift check. One line per check: OK / BAD / WARN / INFO.
# Grow it per machine: every fix that could silently revert gets a line here.
# No global 2>/dev/null: a command that fails must show its error, never pass as an empty answer (= OK).

has() { command -v "$1" >/dev/null 2>&1; }
ok()   { echo "OK   $1"; }
bad()  { echo "BAD  $1"; }
warn() { echo "WARN $1"; }
info() { echo "INFO $1"; }

# Disk: each of / /boot /home once (often the same filesystem). /boot is usually a small ESP: show M there.
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

# Reboot pending: is the running kernel still owned by an installed package? Not "is its modules dir gone":
# kernel-modules-hook keeps old module dirs after an upgrade. A self-built kernel no package owns warns here: drop the line.
k=$(uname -r)
if pacman -Qqo "/usr/lib/modules/$k" >/dev/null 2>&1; then ok "running kernel $k is installed"
else warn "running kernel $k was replaced by an upgrade: reboot pending"; fi
if pacman -Q kernel-modules-hook >/dev/null 2>&1; then
  systemctl is-enabled -q linux-modules-cleanup.service || warn "kernel-modules-hook without linux-modules-cleanup.service enabled: old /usr/lib/modules copies pile up"
fi

# .pacnew: pacdiff reads the package database; find is the fallback (it can't see into root-only dirs).
if has pacdiff; then n=$(pacdiff -o) || warn "pacdiff -o failed (error above)"
else n=$(find /etc -name '*.pacnew' 2>/dev/null); fi
n=$(echo "$n" | awk 'NF{printf " %s", $0}')
[ -n "$n" ] && warn "to merge:$n" || ok "no .pacnew"

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
if systemctl is-active -q sshd; then
  p=$(cat /etc/ssh/sshd_config.d/*.conf /etc/ssh/sshd_config 2>/dev/null | awk 'tolower($1)=="passwordauthentication"{print $2; exit}')
  info "sshd active, PasswordAuthentication ${p:-yes (default)}"
fi

# Journal and coredumps.
# Outside adm/systemd-journal (wheel on Arch), journalctl sees only this user's own journal: its size too.
j=; [ "$(id -u)" != 0 ] && ! id -Gn | grep -qwE 'adm|systemd-journal|wheel' && j=" (this user's only: not in adm/systemd-journal)"
has journalctl && info "journal $(journalctl --disk-usage | grep -o '[0-9.]*[KMGT]' | head -1)$j"
[ -d /var/lib/systemd/coredump ] && { c=$(ls /var/lib/systemd/coredump | wc -l); [ "$c" -gt 0 ] && info "coredumps: $c (coredumpctl list)"; }

# Battery (laptops): what a full charge holds now against new, from the kernel. cycle_count 0 means not reported.
for b in /sys/class/power_supply/BAT*; do
  [ -f "$b/type" ] || continue
  n=${b##*/}; f=$(cat "$b/energy_full" 2>/dev/null || cat "$b/charge_full" 2>/dev/null)
  d=$(cat "$b/energy_full_design" 2>/dev/null || cat "$b/charge_full_design" 2>/dev/null)
  c=$(cat "$b/cycle_count" 2>/dev/null); case $c in ''|0|*[!0-9]*) c= ;; *) c=", $c cycles" ;; esac
  case $f$d in *[!0-9]*|'') warn "battery $n: no full and design capacity in $b"; continue ;; esac
  [ "$d" -gt 0 ] || { warn "battery $n: design capacity 0 in $b"; continue; }
  p=$((f * 100 / d)); [ "$p" -ge 80 ] && ok "battery $n holds ${p}% of new$c" || warn "battery $n holds ${p}% of new$c"
done

info "load $(cut -d' ' -f1-3 /proc/loadavg) on $(nproc) cores, $(uptime -p)"

# Host-specific checks go below this line: drift checks for this host's tweaks (a masked unit, a fan daemon,
# boot entries it relies on, a firewall rule) and parked issues' recheck lines from notes.md.
