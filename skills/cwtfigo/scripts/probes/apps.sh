#!/bin/sh
# Probe: what's installed and how big. macOS: every app with last-used date, size and source (App Store, brew, other);
# Linux: the biggest packages and Flatpaks. Plus what was installed on purpose. Read-only. Run for cleanup and "what can go".
exec 2>/dev/null
has() { command -v "$1" >/dev/null 2>&1; }
sec() { [ -n "$open" ] && echo '```'; echo; echo "## $1"; echo '```'; open=1; }

if [ "$(uname)" = Darwin ]; then
  casks=" $(brew list --cask | tr '\n' ' ') "
  # Last used is Spotlight's; "never" can also mean Spotlight is off for that volume.
  sec "apps: last used, size MB, source, name (oldest first)"
  for a in /Applications/*.app /Applications/*/*.app "$HOME"/Applications/*.app; do
    [ -d "$a" ] || continue
    case $a in /Applications/Utilities/*) continue ;; esac
    n=$(basename "$a" .app)
    used=$(mdls -raw -name kMDItemLastUsedDate "$a" | cut -c1-10); [ "$used" = "(null)" ] && used=never
    src=other
    [ -d "$a/Contents/_MASReceipt" ] && src=appstore
    case $casks in *" $(echo "$n" | tr 'A-Z ' 'a-z-') "*) src=brew ;; esac
    printf '%s %6s %-8s %s\n' "$used" "$(du -sm "$a" | cut -f1)" "$src" "$n"
  done | sort
  if has brew; then
    sec "brew formulae installed on request (leaves)"
    brew leaves | tr '\n' ' '; echo
    sec "brew casks"
    echo "$casks"
  fi
else
  sec "biggest packages (MB)"
  if has pacman; then
    LC_ALL=C pacman -Qi | awk -F': ' '/^Name/{ n = $2 } /^Installed Size/{ split($2, a, " "); m = a[1]
      if (a[2] == "KiB") m /= 1024; else if (a[2] == "GiB") m *= 1024; else if (a[2] == "B") m /= 1048576
      printf "%8.0f %s\n", m, n }' | sort -rn | head -20
  elif has dpkg-query; then
    dpkg-query -W -f='${Installed-Size} ${Package}\n' | sort -rn | head -20 | awk '{ printf "%8.0f %s\n", $1 / 1024, $2 }'
  elif has rpm; then
    rpm -qa --qf '%{SIZE} %{NAME}\n' | sort -rn | head -20 | awk '{ printf "%8.0f %s\n", $1 / 1048576, $2 }'
  fi

  sec "installed on purpose (not as a dependency)"
  if has pacman; then echo "pacman explicit: $(pacman -Qeq | wc -l)"; echo "foreign (AUR/local): $(pacman -Qmq | tr '\n' ' ')"
  elif has apt-mark; then echo "apt manual: $(apt-mark showmanual | wc -l)"
  # -C: from the local cache. Without it dnf refreshes stale repo metadata over the network first.
  elif has dnf; then echo "dnf user-installed: $(dnf -C repoquery --userinstalled -q | wc -l)"; fi

  # OpenWrt: what was added to the firmware image, and packages doing the same job twice (a common clash).
  if [ -f /etc/openwrt_release ]; then
    if [ -f /usr/lib/opkg/status ]; then
      names() { awk '/^Package:/ { print $2 }' "$1"; }
      st=/usr/lib/opkg/status; rom=/rom/usr/lib/opkg/status
      sec "opkg: installed or upgraded beyond the firmware image"
      [ -f "$rom" ] || { echo "no $rom (not a squashfs image): every package counts"; rom=/dev/null; }
      awk -v rom="$rom" '/^Package:/ { p = $2 } /^Version:/ { if (FILENAME == rom) r[p] = $2
          else if (!(p in r)) print p, $2; else if (r[p] != $2) print p, $2, "(image has " r[p] ")" }' "$rom" "$st" | sort
    else
      names() { awk -F: '/^P:/ { print $2 }' /lib/apk/db/installed; }
      sec "apk: asked for beyond the firmware image (/etc/apk/world)"
      if [ -f /rom/etc/apk/world ]; then grep -vxF -f /rom/etc/apk/world /etc/apk/world
      else echo "no /rom/etc/apk/world (not a squashfs image)"; cat /etc/apk/world; fi
    fi
    sec "same job, two packages"
    inst=" $(names "$st" | tr '\n' ' ') "
    for set in "dropbear openssh-server" "wget-nossl wget-ssl wget" "dnsmasq dnsmasq-full dnsmasq-dhcpv6"; do
      got=; for p in $set; do case $inst in *" $p "*) got="$got $p" ;; esac; done
      set -- $got; [ $# -gt 1 ] && echo "both:$got"
    done
    case $inst in *" docker "*|*" dockerd "*) echo "docker installed: its own iptables/nft rules and bridge sit beside fw4" ;; esac
  fi

  if has flatpak; then
    sec flatpak
    flatpak list --columns=application,size,installation
  fi
  if has snap; then
    sec snap
    snap list
  fi
fi

echo '```'
exit 0
