#!/bin/sh
# CWTFIGO-FOUNDATION: adapt to this host from its record, then delete this line. cw won't approve it before.
#
# check.sh (OpenWrt): READ-ONLY health and drift check. One line per check: OK / BAD / WARN / INFO.
# Grow it per machine: every fix that could silently revert gets a line here. A sysupgrade can reset package
# options (a renamed uci key, a service back on its default config): those fixes need a line most of all.
# BusyBox ash: no bash-isms, no `timeout`. No global 2>/dev/null: a command that fails must show its error,
# never pass as an empty answer (= OK).

has() { command -v "$1" >/dev/null 2>&1; }
ok()   { echo "OK   $1"; }
bad()  { echo "BAD  $1"; }
warn() { echo "WARN $1"; }
info() { echo "INFO $1"; }
# Enabled services that may legitimately have no running process (cron with no crontab).
QUIET="cron"

. /etc/openwrt_release
info "$DISTRIB_ID $DISTRIB_RELEASE $DISTRIB_REVISION ($DISTRIB_TARGET), kernel $(uname -r)"

# Flash: /overlay holds config and added packages (/rom is squashfs, always 100%). /tmp is RAM.
o=/overlay; [ -d $o ] || o=/
df -Pk $o /tmp | awk 'NR>1 && !seen[$6]++ { u=$5+0
  printf "%s disk %s %d%%, %dM free\n", (u>=90 ? "BAD " : (u>=80 ? "WARN" : "OK  ")), $6, u, $4/1024 }'
awk '/^MemTotal/{t=$2} /^MemAvailable/{a=$2} END{ p=int(100*a/t)
  printf "%s memory %d%% available (%dM)\n", (p<10 ? "WARN" : "OK  "), p, a/1024 }' /proc/meminfo

t=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -n | tail -1)
[ -n "$t" ] && { [ "$t" -ge 80000 ] && warn "SoC $((t/1000))C" || ok "SoC $((t/1000))C"; }
c=/proc/sys/net/netfilter
[ -r $c/nf_conntrack_count ] && awk -v n="$(cat $c/nf_conntrack_count)" -v m="$(cat $c/nf_conntrack_max)" 'BEGIN{
  printf "%s conntrack %d/%d\n", (n*100>=m*80 ? "WARN" : "OK  "), n, m }'

# Daemons everything depends on, then any enabled service whose procd instance isn't running.
for d in netifd dnsmasq; do pidof $d >/dev/null && ok "$d running" || bad "$d not running"; done
pidof dropbear >/dev/null || pidof sshd >/dev/null || warn "no SSH daemon running"
# Enabled = an S link in /etc/rc.d, what "/etc/init.d/<name> enabled" checks: read the links, run no init script.
down=; en=" $(ls /etc/rc.d | sed -n 's/^S[0-9][0-9]//p' | tr '\n' ' ') "
for s in /etc/init.d/*; do
  n=${s##*/}
  case " $QUIET " in *" $n "*) continue ;; esac
  case $en in *" $n "*) ;; *) continue ;; esac
  grep -q procd_open_instance "$s" || continue
  ubus call service list "{\"name\":\"$n\"}" | grep -q '"running": true' || down="$down $n"
done
[ -n "$down" ] && warn "enabled but not running:$down" || ok "every enabled service is running"

# DNS through the router itself: what every client using it gets. BusyBox nslookup prints the server's own
# Address line before Name:, so only lines after Name: are answers.
if nslookup example.com 127.0.0.1 2>/dev/null | sed -n '/^Name:/,$p' | grep -q '^Address'; then ok "DNS via 127.0.0.1 resolves"
else bad "DNS via 127.0.0.1 does not resolve example.com: clients using the router for DNS are offline"; fi
s=$(uci -q get dhcp.@dnsmasq[0].server)
info "dnsmasq forwards to: ${s:-the DNS servers from WAN (resolv.conf.auto)}"

# AdGuardHome, only when installed. 25.12 renamed its uci option config -> config_file: after that upgrade it
# started on an empty default config (setup wizard, no DNS) until the option was set again.
if [ -x /etc/init.d/adguardhome ] || has AdGuardHome; then
  y=$(uci -q get adguardhome.config.config_file || uci -q get adguardhome.config.config)
  pidof AdGuardHome >/dev/null && ok "AdGuardHome running" || bad "AdGuardHome not running"
  if [ -z "$y" ]; then
    warn "AdGuardHome config path not set in uci (adguardhome.config.config_file)"
  elif [ ! -s "$y" ]; then
    bad "AdGuardHome config $y missing or empty: it runs the setup wizard and serves no DNS"
  else
    p=$(sed -n '/^dns:/,/^[a-z]/s/^  port: *//p' "$y" | head -1)
    n=$(sed -n '/^  upstream_dns:/,/^  [a-z]/p' "$y" | grep -c '^    - ')
    [ "$n" -gt 0 ] && ok "AdGuardHome $y: port ${p:-?}, $n upstreams" || bad "AdGuardHome $y has no upstream_dns: default config?"
    if [ -n "$p" ]; then
      netstat -lnu | grep -q ":$p " || bad "AdGuardHome not listening on :$p"
      [ "$p" = 53 ] || echo "$s" | grep -q "127.0.0.1#$p" ||
        warn "AdGuardHome is on :$p but dnsmasq doesn't forward to 127.0.0.1#$p: nothing is filtered"
    fi
  fi
  # Dead upstreams flood the small log buffer and push real errors out.
  n=$(logread | tail -100 | grep -c 'i/o timeout')
  [ "$n" -gt 20 ] && warn "AdGuardHome upstream timeouts in the last 100 log lines: $n ($(logread | tail -100 |
    grep 'i/o timeout' | grep -o 'addr=[^ ]*' | sort | uniq -c | sort -rn | head -3 | awk '{printf "%s %s ", $2, $1}'))"
fi

# Firewall: the wan zone must refuse what nobody asked for. Stock rules (DHCP, ping, ICMPv6, IPsec) are left out.
z=$(uci -q show firewall | sed -n "s/^firewall\.\([^.]*\)\.name='wan'$/\1/p" | head -1)
if [ -n "$z" ]; then
  for k in input forward; do
    v=$(uci -q get firewall.$z.$k)
    case $v in REJECT|DROP) ok "wan $k $v" ;; *) bad "wan zone $k is ${v:-unset}: the internet gets in" ;; esac
  done
else
  warn "no firewall zone named wan"
fi
r=$(uci -q show firewall | sed -n "s/^firewall\.\([^.]*\)\.src='wan'$/\1/p" | while read -r x; do
  [ "$(uci -q get firewall.$x)" = rule ] && [ "$(uci -q get firewall.$x.target)" = ACCEPT ] || continue
  m=$(uci -q get firewall.$x.name)
  echo "$m" | grep -qxE 'Allow-(DHCP-Renew|Ping|IGMP|DHCPv6|MLD|ICMPv6-Input|ICMPv6-Forward|IPSec-ESP|ISAKMP)' && continue
  printf ' %s(%s)' "${m:-$x}" "$(uci -q get firewall.$x.dest_port || echo any)"
done)
info "non-stock rules accepting from wan:${r:- none}"
f=$(uci -q show firewall | sed -n 's/^firewall\.\([^.=]*\)=redirect$/\1/p' | while read -r x; do
  printf ' %s(%s->%s:%s)' "$(uci -q get firewall.$x.name || echo $x)" "$(uci -q get firewall.$x.src_dport)" \
    "$(uci -q get firewall.$x.dest_ip)" "$(uci -q get firewall.$x.dest_port)"
done)
info "port forwards:${f:- none}"

# SSH: dropbear on every interface with password login is fine only while wan input stays REJECT.
if [ -f /etc/config/dropbear ]; then
  i=$(uci -q get dropbear.@dropbear[0].Interface); pa=$(uci -q get dropbear.@dropbear[0].PasswordAuth)
  k=$(grep -c . /etc/dropbear/authorized_keys 2>/dev/null)
  info "dropbear on ${i:-all interfaces}, port $(uci -q get dropbear.@dropbear[0].Port || echo 22), PasswordAuth ${pa:-on}, ${k:-0} authorized keys"
fi

# Wi-Fi radios: configured and not disabled should be up.
if [ -f /etc/config/wireless ]; then
  st=$(ubus call network.wireless status)
  for d in $(uci -q show wireless | sed -n 's/^wireless\.\([^.=]*\)=wifi-device$/\1/p'); do
    if [ "$(uci -q get wireless.$d.disabled)" = 1 ]; then info "$d disabled"
    elif echo "$st" | awk -v r="$d" '$0 ~ "^\t\"" r "\": \\{" { f = 1 } f && /^\t\t"up": true/{ u = 1 } f && /^\t}/{ f = 0 } END { exit !u }'
    then ok "$d up"; else warn "$d enabled but not up"; fi
  done
fi

# Log flood: logread is a small RAM ring; a noisy daemon pushes real errors out within minutes.
e=$(logread | tail -100 | grep -c -i -E 'err|fail')
[ "$e" -gt 30 ] && warn "$e of the last 100 log lines are errors, mostly: $(logread | tail -100 | grep -i -E 'err|fail' |
  awk '{print $7}' | sed 's/\[.*//; s/:$//' | sort | uniq -c | sort -rn | head -3 | awk '{printf "%s(%s) ", $2, $1}')" || ok "log not flooded ($e/100 error lines)"

if has tailscale; then
  pidof tailscaled >/dev/null || warn "tailscaled not running"
  b=$(tailscale status --json | grep -o '"BackendState": *"[^"]*"' | cut -d'"' -f4)
  [ "$b" = Running ] && ok "tailscale Running" || warn "tailscale ${b:-not answering}"
fi

info "load $(cut -d' ' -f1-3 /proc/loadavg) on $(grep -c ^processor /proc/cpuinfo) cores, up $(awk '{printf "%dd %dh", $1/86400, $1%86400/3600}' /proc/uptime)"

# Host-specific checks go below this line: the DNS chain this router is meant to have, its port forwards and
# rules by name, VPN routes, packages a sysupgrade must bring back, parked issues' recheck lines from notes.md.
