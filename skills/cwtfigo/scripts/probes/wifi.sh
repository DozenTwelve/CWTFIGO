#!/bin/sh
# Probe: Wi-Fi. A client: link quality (signal, noise, rate, channel), power saving, what else takes airtime or the path
# (AWDL, VPN, proxy). An access point (OpenWrt): each radio's channel, power and stations with their signal and rates.
# Read-only. Run for slow or dropping Wi-Fi; run once while it's bad and once while it's fine.
#   wifi.sh <client MAC>  on an AP: show only that station
#   wifi.sh --test        on macOS: also Apple's networkQuality twice (default path, then bound to Wi-Fi, past any VPN).
#                         Moves a few hundred MB.
exec 2>/dev/null
has() { command -v "$1" >/dev/null 2>&1; }
sec() { [ -n "$open" ] && echo '```'; echo; echo "## $1"; echo '```'; open=1; }
want=; case $1 in *:*:*) want=$(echo "$1" | tr 'A-F' 'a-f') ;; esac

if [ "$(uname)" = Darwin ]; then
  w=$(networksetup -listallhardwareports | awk '/^Hardware Port: Wi-Fi/{ f = 1 } f && /^Device:/{ print $2; exit }')
  sec "wifi link ($w)"
  system_profiler SPAirPortDataType | awk '/Current Network Information:/{ f = 1; next } f && /Other Local Wi-Fi Networks:/{ exit } f' |
    grep -E 'PHY Mode|Channel|Signal / Noise|Transmit Rate|MCS Index|Security' | sed 's/^ *//' | head -8
  # AWDL (AirDrop, Handoff, AirPlay) hops channels and takes airtime from the main link while active.
  sec "awdl / llw"
  for i in awdl0 llw0; do echo "$i: $(ifconfig $i | awk '/status:/{ print $2 }')"; done
  sec "path: default route, proxy, VPN"
  echo "v4 default: $(route -n get default | awk '/interface:/{ print $2 }')  v6 default: $(route -n get -inet6 default | awk '/interface:/{ print $2 }')"
  scutil --proxy | grep -E 'Enable : 1|Proxy :|Port :|ProxyAutoConfigURLString' | sed 's/^ *//'
  echo "utun with an address: $(ifconfig | awk '/^utun/{ i = $1 } /inet / && i { printf "%s ", i; i = "" }')"
  ps -axo comm | grep -i -E 'clash|mihomo|surge|stash|v2ray|xray|sing-box|shadowrocket|quantumult|hiddify|tailscale|wireguard|openvpn|zerotier|warp|little ?snitch|lulu' | sed 's|.*/||' | sort -u
  pmset -g | grep -i lowpowermode
  if [ "$1" = --test ]; then
    sec "networkQuality, default path"
    networkQuality -s | grep -E 'Downlink capacity|Uplink capacity|Responsiveness'
    sec "networkQuality, bound to $w"
    networkQuality -s -I "$w" | grep -E 'Downlink capacity|Uplink capacity|Responsiveness'
  fi
elif has iw; then
  for i in $(iw dev | awk '/Interface/{ print $2 }'); do
    sec "$i"
    iw dev "$i" info | grep -E 'type|ssid|channel|txpower' | sed 's/^[[:space:]]*//'
    if iw dev "$i" info | grep -q 'type AP'; then
      # one line per station, numbered; the MAC only when asked for
      iw dev "$i" station dump | awk -v want="$want" '
        /^Station/{ m = tolower($2); show = (want == "" || m == want); if (show) printf "%sstation %s:", (n++ ? "\n" : ""), (want == "" ? n : m); next }
        show && /signal:|tx bitrate:|rx bitrate:|connected time:|inactive time:|tx retries:|tx failed:/{ gsub(/^[ \t]+|[ \t]+$/, ""); gsub(/[ \t]+/, " "); printf " %s;", $0 }
        END { if (n) print ""; else print "no stations" }'
    else
      iw dev "$i" link | grep -E 'SSID|freq|signal|bitrate' | sed 's/^[[:space:]]*//'
      iw dev "$i" get power_save
    fi
  done
  sec regulatory
  iw reg get | grep -m2 country
elif has iwinfo; then
  sec radios
  iwinfo | grep -v -E 'Access Point|Encryption|Supports VAPs'
fi
if has nmcli; then
  sec networkmanager
  # --rescan no: the cached scan. A rescan takes the radio off its channel for seconds, on the link being measured.
  nmcli -t -f active,ssid,chan,rate,signal,security dev wifi list --rescan no | grep '^yes'
fi
[ -d /sys/class/rfkill ] && { sec rfkill; for r in /sys/class/rfkill/*; do echo "$(cat $r/name) $(cat $r/type) soft=$(cat $r/soft) hard=$(cat $r/hard)"; done; }

[ -n "$open" ] && echo '```'
exit 0
