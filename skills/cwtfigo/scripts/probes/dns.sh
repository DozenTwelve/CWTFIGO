#!/bin/sh
# Probe: DNS. Which resolvers this machine uses, what dnsmasq and AdGuardHome forward to, and whether each answers.
# Read-only: a few lookups of example.com, one of them via 1.1.1.1 as an outside reference.
# Run for "sites don't load", slow first loads, ad blocking stopped. Private upstream IDs in DoH/DoT URLs are masked.
exec 2>/dev/null
has() { command -v "$1" >/dev/null 2>&1; }
sec() { [ -n "$open" ] && echo '```'; echo; echo "## $1"; echo '```'; open=1; }
ip_only() { grep -E '^[0-9.]+$|^[0-9a-fA-F:]+$'; }
# answers after the "Name:" line; the server's own "Address:" line comes before it
look() { t0=$(date +%s); r=$(nslookup example.com "$1" | sed -n '/^Name:/,$p' | grep -c '^Address'); echo "$1: answers=$r secs=$(( $(date +%s) - t0 ))"; }

sec resolvers
grep -E '^(nameserver|search|options)' /etc/resolv.conf
has resolvectl && resolvectl status --no-pager | grep -E 'Link|resolv.conf mode|Current DNS|DNS Servers|DNS over TLS|DNSSEC' | head -20
has scutil && scutil --dns | awk '/^resolver/{ r = $0 } /nameserver\[/{ print r ": " $3 }' | sort -u | head -12
if [ -r /tmp/resolv.conf.d/resolv.conf.auto ]; then echo "--- from upstream (resolv.conf.auto)"; cat /tmp/resolv.conf.d/resolv.conf.auto; fi
has uci && uci -q show dhcp.@dnsmasq[0] | grep -E '\.(server|noresolv|port|localuse|rebind_protection|resolvfile)='

# AdGuardHome: uci names its config `config_file` since OpenWrt 25.12 (`config` before); else the -c argument, else a search.
y=$(uci -q get adguardhome.config.config_file || uci -q get adguardhome.config.config)
[ -n "$y" ] || y=$({ ps -A -o args || ps w; } | grep -i '[A]dGuardHome' | grep -o -- '-c [^ ]*' | head -1 | cut -c4-)
[ -n "$y" ] || y=$(find /etc /opt /var/snap -maxdepth 3 -iname 'adguardhome.yaml' | head -1)
if [ -f "$y" ]; then
  sec "AdGuardHome dns section ($y)"
  sed -n '/^dns:/,/^[a-z]/p' "$y" |
    grep -E 'bind_hosts|^  port:|upstream|fallback|bootstrap|all_servers|fastest_addr|timeout|cache|ratelimit|^    - ' |
    grep -v -i -E 'pass|token|key|user|secret|auth' |
    sed -E 's#(https?://[^/ ]+/).+#\1<path>#; s#((tls|quic|h3|sdns)://)[^./ ]+(\.[^./ ]+\.[^./ ]+\.[^./ ]+)#\1<id>\3#' | head -50
fi

sec lookups
{
  sed -n 's/^nameserver[[:space:]]*//p' /etc/resolv.conf /tmp/resolv.conf.d/resolv.conf.auto
  uci -q get dhcp.@dnsmasq[0].server | tr ' ' '\n' | ip_only
  [ -f "$y" ] && sed -n '/^  upstream_dns:/,/^  [a-z]/s/^    - //p' "$y" | ip_only
  echo 1.1.1.1
} | awk '!seen[$0]++' | head -8 | while read -r s; do look "$s"; done

echo '```'
exit 0
