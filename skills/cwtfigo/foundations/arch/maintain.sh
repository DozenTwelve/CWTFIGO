#!/bin/sh
# CWTFIGO-FOUNDATION: adapt to this host from its record, then delete this line. cw won't approve it before.
#
# maintain.sh (Arch): updates and cleanup for this host.
#   no argument: dry run. Unread Arch news, pending updates, what each cleanup item would free, orphans.
#                Changes nothing (checkupdates syncs a private copy of the package database).
#   --apply:     keyring, pacman -Syu, AUR, flatpak, clean the items in CLEAN, report space freed, .pacnew, reboot.
#                Uses sudo: the human runs it in their terminal. Read the news from the dry run first;
#                an item there that needs manual intervention comes before --apply.
#   --apply <word>...: only what is named. update = the upgrades in UPDATE; any other word = that cleanup item.
#                --apply trash empties the Trash and upgrades nothing; --apply update journal upgrades, then vacuums.
#
# This is where the host's habits live. Edit CLEAN and UPDATE to fit the machine and its owner;
# an item missing here is never cleaned, whatever the dry run shows. Packages to hold go in IgnorePkg
# in /etc/pacman.conf, with a line in notes.md saying why.
CLEAN="pkgcache aur journal"
UPDATE="pacman aur flatpak"
JOURNAL_MAX=200M
#
# Items the dry run knows (on = in CLEAN):
#   pkgcache    pacman cache: keep 2 versions of installed packages, none of removed ones (paccache)
#   aur         AUR helper clone/build cache (-git packages re-clone next time)
#   journal     systemd journal, vacuumed to JOURNAL_MAX
#   usercache   ~/.cache: all app caches. Apps rebuild them, some log you out. Opt-in.
#   trash       empty the Trash. User data, irreversible. Only when the owner said yes in chat, and only
#               when named after --apply (--apply trash): never from CLEAN.
# Never removed here: orphans (listed only; removal cascades, show the full list and confirm separately).

APPLY=; [ "$1" = --apply ] && APPLY=1 && shift
# Words after --apply are the owner's pick for this run: only what is named runs. `update` is the upgrades in UPDATE,
# every other word a cleanup item, in place of CLEAN. So --apply trash empties the Trash and upgrades nothing, and
# --apply update upgrades and cleans nothing. The pick goes as args, not as an edit: an edit changes the hash and asks
# for approval again. CLEAN and UPDATE stay the habit. A word that is neither is a typo: said, and nothing runs.
# trash only when named after --apply (--apply trash), never from CLEAN: emptying it takes the owner's yes typed in
# chat, and --apply runs on a permission prompt alone. So it is left out of CLEAN even if added there.
# ITEMS: every cleanup item below. One added to this script goes here too, or naming it is refused as a typo.
ITEMS="pkgcache aur journal usercache trash"
NOUP=
if [ $# -gt 0 ]; then
  [ -n "$APPLY" ] && NOUP=1; c=
  for i in "$@"; do
    if [ "$i" = update ]; then NOUP=; continue; fi
    case " $ITEMS " in *" $i "*) c="${c:+$c }$i" ;; *) echo "unknown item: $i"; echo "known: update $ITEMS"; exit 1 ;; esac
  done
  CLEAN=$c
else c=; for i in $CLEAN; do [ "$i" = trash ] || c="${c:+$c }$i"; done; CLEAN=$c; fi
has() { command -v "$1" >/dev/null 2>&1; }
on() { case " $1 " in *" $2 "*) return 0;; esac; return 1; }
sec() { echo; echo "## $1"; }
mb() { du -sk "$@" 2>/dev/null | awk '{s+=$1} END{printf "%dM", s/1024}'; }
free_mb() { df -Pk / | awk 'NR==2{print int($4/1024)}'; }

# AUR helpers refuse to run as root; so does this script's AUR part.
S=sudo; AUR=; has paru && AUR=paru || { has yay && AUR=yay; }
[ "$(id -u)" = 0 ] && { S=; AUR=; }
AURCACHE=${XDG_CACHE_HOME:-$HOME/.cache}/$AUR

# item <name> <size> <clean command>: one dry-run line; on --apply, clean if the item is in CLEAN.
item() {
  [ -n "$2" ] || return
  state=off; on "$CLEAN" "$1" && state=on
  printf '%-10s %-4s %s\n' "$1" "$state" "$2"
  if [ -n "$APPLY" ] && [ $state = on ]; then echo "+ $3"; sh -c "$3" >/dev/null 2>&1 || echo "  failed: $1"; fi
}

if [ -n "$APPLY" ] && [ -n "$S" ]; then
  sudo -v || { echo "--apply needs sudo: run it in a terminal"; exit 1; }
fi
before=$(free_mb)

sec news
echo "last full upgrade: $(sed -n 's/^\[\([0-9-]*\)T.*starting full system upgrade.*/\1/p' /var/log/pacman.log | tail -1)"
if [ -n "$AUR" ]; then
  $AUR -Pw 2>&1   # news newer than the installed packages, or "no new news"
else
  echo "no AUR helper: read https://archlinux.org/news/ for items since the last full upgrade"
fi

sec updates
[ -n "$NOUP" ] && { UPDATE=; echo "updates: not asked for (--apply <items> without update): nothing listed, nothing upgraded"; }
if on "$UPDATE" pacman; then
  if has checkupdates; then
    out=$(checkupdates); rc=$?   # 2 = nothing to update, 1 = error
    case $rc in
      0) echo "repo: $(echo "$out" | wc -l | tr -d ' ') pending"
         echo "$out" | grep -E '^(linux(-[a-z]+)?|systemd|glibc|mesa|nvidia(-[a-z]+)?|grub|archlinux-keyring) ' | sed 's/^/  /' ;;
      2) echo "repo: all current" ;;
      *) echo "repo: checkupdates failed (error above)" ;;
    esac
  else
    echo "repo: no checkupdates (pacman-contrib not installed), count unknown"
  fi
  if [ -n "$APPLY" ]; then
    echo "+ pacman -Sy archlinux-keyring, then pacman -Su"
    $S pacman -Sy --needed --noconfirm archlinux-keyring && $S pacman -Su ||
      { echo "upgrade failed or declined: stopping before AUR and cleanup"; exit 1; }
  fi
fi
if on "$UPDATE" aur && [ -n "$AUR" ]; then
  out=$($AUR -Qua)
  [ -n "$out" ] && { echo "aur: $(echo "$out" | wc -l | tr -d ' ') pending"; echo "$out" | sed 's/^/  /'; } || echo "aur: all current"
  # The helper shows each PKGBUILD diff before building: AUR packages are unreviewed, read them.
  [ -n "$APPLY" ] && [ -n "$out" ] && { echo "+ $AUR -Sua"; $AUR -Sua; }
fi
if on "$UPDATE" flatpak && has flatpak; then
  out=$(flatpak remote-ls --updates)
  [ -n "$out" ] && echo "flatpak: $(echo "$out" | wc -l | tr -d ' ') pending" || echo "flatpak: all current"
  [ -n "$APPLY" ] && [ -n "$out" ] && { echo "+ flatpak update -y"; flatpak update -y; }
fi

sec "cleanup (size, on/off)"
pc() { x=$(paccache -d "$@" | sed -n 's/.*saved: \([^)]*\)).*/\1/p'); echo "${x:-0}"; }
has paccache && item pkgcache "$(pc -k2) old, $(pc -uk0) uninstalled" "$S paccache -rk2 && $S paccache -ruk0"
[ -n "$AUR" ] && [ -d "$AURCACHE" ] && item aur "$(mb "$AURCACHE")" "$AUR -Sca --noconfirm"
# Outside adm/systemd-journal (wheel on Arch), journalctl sees only this user's own journal: its size too.
j=; [ "$(id -u)" != 0 ] && ! id -Gn | grep -qwE 'adm|systemd-journal|wheel' && j=" (this user's only: not in adm/systemd-journal)"
has journalctl && item journal "$(journalctl --disk-usage | grep -o '[0-9.]*[KMGT]' | head -1)$j, to $JOURNAL_MAX" "$S journalctl --vacuum-size=$JOURNAL_MAX"
item usercache "$(mb "${XDG_CACHE_HOME:-$HOME/.cache}")" "rm -rf \"${XDG_CACHE_HOME:-$HOME/.cache}/\"*"
item trash "$(mb "$HOME/.local/share/Trash")" "rm -rf \"$HOME/.local/share/Trash/\"*"

sec "orphans (listed, never removed by --apply)"
pacman -Qdtq || echo "(none)"

sec report
[ -n "$APPLY" ] && echo "mode: applied" || echo "mode: dry run, nothing changed"
echo "free on /: ${before}M before, $(free_mb)M now"
if [ -n "$APPLY" ]; then
  has pacdiff && n=$(pacdiff -o) || n=$(find /etc -name '*.pacnew' 2>/dev/null)
  [ -n "$n" ] && { echo ".pacnew to merge:"; echo "$n" | sed 's/^/  /'; } || echo "no .pacnew"
  pacman -Qqo "/usr/lib/modules/$(uname -r)" >/dev/null 2>&1 || echo "kernel upgraded: reboot"
fi
