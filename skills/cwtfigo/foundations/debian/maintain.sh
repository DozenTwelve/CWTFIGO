#!/bin/sh
# CWTFIGO-FOUNDATION: adapt to this host from its record, then delete this line. cw won't approve it before.
#
# maintain.sh (Debian, Ubuntu and derivatives): updates and cleanup for this host.
#   no argument: dry run. Last upgrade, pending updates (from fresh package lists in a private dir), held and kept-back
#                packages, what each cleanup item would free, autoremove candidates. Changes nothing.
#   --apply:     apt-get update, apt-get upgrade --with-new-pkgs (apt asks before it changes anything), snap, flatpak,
#                clean the items in CLEAN (or only those named after --apply), report space freed, .dpkg-dist, reboot.
#                Uses sudo: the human runs it in their terminal.
#
# This is where the host's habits live. Edit CLEAN and UPDATE to fit the machine and its owner;
# an item missing here is never cleaned, whatever the dry run shows. Packages to hold: sudo apt-mark hold <pkg>,
# with a line in notes.md saying why; apt upgrade never touches them. A package autoremove must never take:
# sudo apt-mark manual <pkg>.
CLEAN="aptcache journal snaprev"
UPDATE="apt snap flatpak"
JOURNAL_MAX=200M
#
# UPDATE items: apt, snap, flatpak; full = dist-upgrade instead of upgrade. Off by default: it may remove packages
# (apt lists them and asks). Add it only when notes.md says this host takes it, e.g. for packages kept back.
#
# Items the dry run knows (on = in CLEAN):
#   aptcache    downloaded .deb files in /var/cache/apt/archives (apt-get clean)
#   journal     systemd journal, vacuumed to JOURNAL_MAX
#   snaprev     disabled snap revisions, kept for snap revert (snapd keeps 2 or 3 per snap)
#   usercache   ~/.cache: all app caches. Apps rebuild them, some log you out. Opt-in.
#   trash       empty the Trash. User data, irreversible. Only when the owner asked.
# Never removed here: autoremove candidates (listed only; removal cascades and can take a kernel or driver this host
# keeps on purpose: show the full list, check notes.md, confirm separately).

APPLY=; [ "$1" = --apply ] && APPLY=1 && shift
# Items named after --apply are the owner's pick for this run, in place of CLEAN (none: clean nothing). The pick goes
# as args, not as an edit: an edit changes the hash and asks for approval again. CLEAN stays the habit.
[ $# -gt 0 ] && CLEAN="$*"
has() { command -v "$1" >/dev/null 2>&1; }
on() { case " $1 " in *" $2 "*) return 0;; esac; return 1; }
sec() { echo; echo "## $1"; }
mb() { du -sk "$@" 2>/dev/null | awk '{s+=$1} END{printf "%dM", s/1024}'; }
free_mb() { df -Pk / | awk 'NR==2{print int($4/1024)}'; }

S=sudo; [ "$(id -u)" = 0 ] && S=

# item <name> <size> <clean command>: one dry-run line; on --apply, clean if the item is in CLEAN.
# eval, not sh -c: a command may use this script's functions and variables.
item() {
  [ -n "$2" ] || return
  state=off; on "$CLEAN" "$1" && state=on
  printf '%-10s %-4s %s\n' "$1" "$state" "$2"
  if [ -n "$APPLY" ] && [ $state = on ]; then echo "+ $3"; eval "$3" >/dev/null 2>&1 || echo "  failed: $1"; fi
}

if [ -n "$APPLY" ] && [ -n "$S" ]; then
  # Debian set up with a root password has no sudo at all.
  has sudo || { echo "--apply: no sudo here: run it as root (su -)"; exit 1; }
  sudo -v || { echo "--apply needs sudo: run it in a terminal"; exit 1; }
fi
before=$(free_mb)

sec news
[ -r /var/log/apt/history.log ] && echo "last upgrade: $(awk '/^Start-Date:/{d=$2} /^Upgrade:/{u=d} END{print u ? u : "none in /var/log/apt/history.log"}' /var/log/apt/history.log)"
case $(sed -n 's/^ID=//p' /etc/os-release) in
  ubuntu) echo "security notices: https://ubuntu.com/security/notices" ;;
  *) echo "security notices: https://www.debian.org/security/ (derivatives: their own list)" ;;
esac

sec updates
if on "$UPDATE" apt; then
  # The system's lists are as old as the last root apt-get update. The dry run fetches fresh ones into a private dir
  # (no root, no lock, like checkupdates on Arch); --apply updates the real ones.
  if [ -n "$APPLY" ]; then
    o=; echo "+ apt-get update"; $S apt-get update -qq || { echo "apt-get update failed: stopping"; exit 1; }
  else
    T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; mkdir -p "$T/lists/partial" "$T/cache/archives/partial"
    # apt.conf.d's update hooks would still run (Ubuntu's 15update-stamp, update-notifier and command-not-found write
    # to /var/lib, as root when run as root): cleared for this update, so the dry run changes nothing.
    printf '#clear APT::Update::%s;\n' Pre-Invoke Post-Invoke Post-Invoke-Success > "$T/apt.conf"
    o="-c $T/apt.conf -o Dir::State::Lists=$T/lists -o Dir::Cache=$T/cache -o Debug::NoLocking=1"
    # As root apt downloads as _apt, which can't write a mktemp dir: no sandbox for this private copy.
    [ -z "$S" ] && o="$o -o APT::Sandbox::User=root"
    apt-get $o update -qq || { echo "apt: fetching fresh lists failed (error above): counts from the system's lists"; o="-o Debug::NoLocking=1"; }
  fi
  # A failed listing says so: it is not "0 pending".
  if s=$(apt-get $o -s upgrade --with-new-pkgs); then
    echo "apt: $(echo "$s" | grep -c '^Inst ') pending, $(echo "$s" | grep -c '^Inst .*-security') from security"
  else echo "apt: listing pending upgrades failed (error above)"; fi
  echo "$s" | awk '$1=="Inst" && $2 ~ /^(linux-image|linux-firmware|firmware-|systemd$|libc6$|nvidia|grub|openssh-server$)/{print "  " $2}'
  # Kept back: needs a new or removed package (dist-upgrade), or a phased update Ubuntu rolls out slowly. Not done here.
  k=$(echo "$s" | awk '/kept back:/{f=1; next} /^[^ ]/{f=0} f' | tr -s ' \n' ' ')
  [ -n "${k# }" ] && echo "kept back:$k"
  h=$(apt-mark showhold | tr '\n' ' ')
  [ -n "$h" ] && echo "held (never upgraded here): $h"
  if [ -n "$APPLY" ]; then
    u=upgrade; on "$UPDATE" full && u=dist-upgrade
    echo "+ apt-get $u --with-new-pkgs"
    $S apt-get $u --with-new-pkgs || { echo "upgrade failed or declined: stopping before snap and cleanup"; exit 1; }
  fi
fi
if on "$UPDATE" snap && has snap; then
  out=$(snap refresh --list 2>&1 | grep -v '^Name\|All snaps up to date')
  [ -n "$out" ] && { echo "snap: $(echo "$out" | wc -l | tr -d ' ') pending"; echo "$out" | sed 's/^/  /'; } || echo "snap: all current"
  [ -n "$APPLY" ] && [ -n "$out" ] && { echo "+ snap refresh"; $S snap refresh; }
fi
if on "$UPDATE" flatpak && has flatpak; then
  if out=$(flatpak remote-ls --updates); then
    [ -n "$out" ] && echo "flatpak: $(echo "$out" | wc -l | tr -d ' ') pending" || echo "flatpak: all current"
  else echo "flatpak: listing updates failed (error above)"; fi
  [ -n "$APPLY" ] && [ -n "$out" ] && { echo "+ flatpak update -y"; flatpak update -y; }
fi

sec "cleanup (size, on/off)"
item aptcache "$(mb /var/cache/apt/archives)" "$S apt-get clean"
# Outside adm/systemd-journal (wheel on Arch), journalctl sees only this user's own journal: its size too.
j=; [ "$(id -u)" != 0 ] && ! id -Gn | grep -qwE 'adm|systemd-journal|wheel' && j=" (this user's only: not in adm/systemd-journal)"
has journalctl && item journal "$(journalctl --disk-usage | grep -o '[0-9.]*[KMGT]' | head -1)$j, to $JOURNAL_MAX" "$S journalctl --vacuum-size=$JOURNAL_MAX"
if has snap; then
  rev=$(snap list --all | awk '$NF ~ /disabled/{print $1 "_" $3}')
  snaprev() { for r in $rev; do $S snap remove "${r%_*}" --revision="${r##*_}" || return; done; }
  [ -n "$rev" ] && item snaprev "$(cd /var/lib/snapd/snaps && mb $(echo "$rev" | sed 's/$/.snap/')), $(echo "$rev" | wc -l | tr -d ' ') revisions" snaprev
fi
item usercache "$(mb "${XDG_CACHE_HOME:-$HOME/.cache}")" "rm -rf \"${XDG_CACHE_HOME:-$HOME/.cache}/\"*"
item trash "$(mb "$HOME/.local/share/Trash")" "rm -rf \"$HOME/.local/share/Trash/\"*"

sec "autoremove (listed, never removed by --apply)"
if r=$(apt-get -s -o Debug::NoLocking=1 autoremove); then
  r=$(echo "$r" | sed -n 's/^Remv \([^ ]*\).*/\1/p' | tr '\n' ' '); echo "${r:-(none)}"
else echo "listing failed (error above)"; fi

sec report
[ -n "$APPLY" ] && echo "mode: applied" || echo "mode: dry run, nothing changed"
echo "free on /: ${before}M before, $(free_mb)M now"
if [ -n "$APPLY" ]; then
  n=$(find /etc \( -name '*.dpkg-dist' -o -name '*.dpkg-new' -o -name '*.ucf-dist' -o -name '*.ucf-new' \) 2>/dev/null)
  [ -n "$n" ] && { echo "config to merge:"; echo "$n" | sed 's/^/  /'; } || echo "no .dpkg-dist"
  [ -f /run/reboot-required ] && echo "reboot required by: $(sort -u /run/reboot-required.pkgs 2>/dev/null | tr '\n' ' ')"
fi
# Not the last test's status: no reboot pending is a good --apply too.
exit 0
