#!/bin/sh
# Probe: wired ports. Negotiated speed and duplex, driver, error and drop counters; what the uplink port
# advertises and its partner offers. Read-only. Run for "slow wired", "stuck at 100M", flapping links.
# Counters count since boot or link up: a growing rx_crc means cable, plug or port.
exec 2>/dev/null
has() { command -v "$1" >/dev/null 2>&1; }
sec() { [ -n "$open" ] && echo '```'; echo; echo "## $1"; echo '```'; open=1; }
c() { cat "$1" || echo -; }

sec ports
if [ -d /sys/class/net ]; then
  for d in /sys/class/net/*; do
    n=${d##*/}
    # physical NICs and switch (DSA) ports only; Wi-Fi is the wifi probe
    [ -e "$d/device" ] || [ -e "$d/dsa" ] || [ -n "$(cat "$d/phys_port_name")" ] || continue
    [ -e "$d/wireless" ] || [ -e "$d/phy80211" ] && continue
    drv=$(readlink "$d/device/driver"); drv=${drv##*/}
    s=$d/statistics
    echo "$n: state=$(c $d/operstate) speed=$(c $d/speed) duplex=$(c $d/duplex) driver=${drv:--} rx_err=$(c $s/rx_errors) rx_crc=$(c $s/rx_crc_errors) rx_drop=$(c $s/rx_dropped) tx_err=$(c $s/tx_errors)"
  done
elif has networksetup; then
  networksetup -listallhardwareports | awk '/^Hardware Port:/{sub(/^Hardware Port: /, ""); p=$0} /^Device:/{print $2 "\t" p}' |
  while IFS="$(printf '\t')" read -r dev port; do
    case $port in Wi-Fi|*Bluetooth*|*Bridge*) continue ;; esac
    i=$(ifconfig "$dev") || continue
    m=$(echo "$i" | sed -n 's/^[[:space:]]*media: //p')
    st=$(echo "$i" | awk '/status:/{print $2}')
    # count fields from the end: the address column is missing on some interfaces
    e=$(netstat -I "$dev" | awk 'NR>1 && /<Link/{print "in_err=" $(NF-3), "out_err=" $(NF-1), "coll=" $NF; exit}')
    echo "$dev ($port): status=${st:--} media=${m:--} $e"
  done
fi

sec default-route
ip -4 route show default || route -n get default | grep -E 'gateway|interface'

# The uplink: the router's WAN device, else the default route's.
w=$(uci -q get network.wan.device)
[ -n "$w" ] || w=$(ip -4 route show default | awk '{for (i = 1; i < NF; i++) if ($i == "dev") { print $(i+1); exit }}')
if [ -n "$w" ] && has ethtool; then
  sec "ethtool $w"
  ethtool "$w" | awk '/:/{p = /[Ll]ink modes|Speed|Duplex|Auto-negotiation|Link detected/} p'
fi

echo '```'
exit 0
