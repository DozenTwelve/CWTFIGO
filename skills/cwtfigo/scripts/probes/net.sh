#!/bin/sh
# Probe: addresses, listening ports, running services, containers. Read-only. Run for network or "what's running" requests.
exec 2>/dev/null
has() { command -v "$1" >/dev/null 2>&1; }
sec() { [ -n "$open" ] && echo '```'; echo; echo "## $1"; echo '```'; open=1; }

sec addresses
# BusyBox ip (OpenWrt) has no -br: one line per address from -o instead, then ifconfig.
a=$(ip -br addr || ip -o addr | awk '$3 ~ /^inet/ { print $2, $4 }')
[ -n "$a" ] || a=$(ifconfig | grep -E '^[a-z]|inet ')
echo "$a"

sec listening
# BusyBox netstat (OpenWrt, no ss or lsof) names the program and lists UDP too; on a UDP line the program is still the last field.
if netstat --help 2>&1 | grep -q BusyBox && l=$(netstat -tulnp); then echo "$l" | awk 'NR>2 {print $1, $4, $NF}' | sort -u
elif has ss; then ss -Htlnp | awk '{print $4, $6}' | sort -u
elif has lsof; then lsof -nP -iTCP -sTCP:LISTEN | awk 'NR>1{print $9, $1}' | sort -u
elif has netstat; then netstat -tln | awk 'NR>2{print $4}' | sort -u; fi

sec services
if has systemctl; then systemctl list-units --type=service --state=running --no-legend --plain | awk '{print $1}'
# OpenWrt (procd): "/etc/init.d/<name> enabled" checks for its S link in /etc/rc.d; read the links, run no init script.
elif [ -d /etc/rc.d ]; then echo "enabled at boot (procd), not necessarily running:"; ls /etc/rc.d | sed -n 's/^S[0-9][0-9]//p'; fi
has docker && docker ps -a --format '{{.Names}}\t{{.State}}'

echo '```'
exit 0
