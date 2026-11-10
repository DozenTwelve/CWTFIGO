#!/bin/sh
# CWTFIGO-FOUNDATION: adapt to this host from its record, then delete this line. cw won't approve it before.
#
# maintain.sh (macOS): updates and cleanup for this host.
#   no argument: dry run. Lists pending updates and what each cleanup item would free. Changes nothing
#                except refreshing Homebrew's package index.
#   --apply:     upgrade, clean the items in CLEAN (or only those named after --apply), report space freed.
#
# This is where the host's habits live. Edit CLEAN and UPDATE to fit the machine and its owner;
# an item missing here is never cleaned, whatever the dry run shows.
CLEAN="brew logs xcode simulators npm pnpm"
UPDATE="brew mas mise npm"
# yes = APFS local snapshot before --apply, only if the owner asked for one. It pins every
# byte freed after it, so a cleanup frees nothing until the snapshot is deleted.
SNAPSHOT=no
#
# Items the dry run knows (on = in CLEAN):
#   brew        old Homebrew versions and downloads (keeps 30 days)
#   logs        files in ~/Library/Logs older than 30 days, not DiagnosticReports (the crash, hang and panic
#               reports the logs, perf and boot probes read)
#   xcode       Xcode DerivedData (rebuilt on next build)
#   simulators  simulators whose runtime is gone
#   npm pnpm yarn pip go   package manager caches (re-downloaded when needed)
#   caches      ~/Library/Caches: all app caches. Apps rebuild them, some log you out. Opt-in.
#   docker      stopped containers, dangling images, build cache. Stopped containers may matter. Opt-in.
#   trash       empty the Trash. User data, irreversible. Only when the owner said yes in chat, and only
#               when named after --apply (--apply trash): never from CLEAN.
# Never touched: Xcode Archives (dSYMs), iOS backups, anything under ~/Documents or ~/Desktop.

APPLY=; [ "$1" = --apply ] && APPLY=1 && shift
# Items named after --apply are the owner's pick for this run, in place of CLEAN (none: clean nothing). The pick goes
# as args, not as an edit: an edit changes the hash and asks for approval again. CLEAN stays the habit.
# trash only when named after --apply (--apply trash), never from CLEAN: emptying it takes the owner's yes typed in
# chat, and --apply runs on a permission prompt alone. So it is left out of CLEAN even if added there.
[ $# -gt 0 ] && CLEAN="$*" || { c=; for i in $CLEAN; do [ "$i" = trash ] || c="${c:+$c }$i"; done; CLEAN=$c; }
has() { command -v "$1" >/dev/null 2>&1; }
on() { case " $1 " in *" $2 "*) return 0;; esac; return 1; }
sec() { echo; echo "## $1"; }
mb() { du -sk "$@" 2>/dev/null | awk '{s+=$1} END{printf "%dM", s/1024}'; }
free_mb() { df -Pk "$HOME" | awk 'NR==2{print int($4/1024)}'; }
# lst <command...>: its output in $out. Some list commands exit 1 when they found something (npm outdated): only an
# exit with nothing on stdout is a failure, said with its last error line, never read as "all current".
E=$(mktemp); trap 'rm -f "$E"' EXIT
lst() { out=$("$@" 2>"$E") || [ -n "$out" ] || { echo "$1: $2 failed: $(tail -1 "$E")"; return 1; }; }
clt() { xcode-select -p >/dev/null 2>&1; }   # without it, xcrun and /usr/bin stubs pop an install dialog

# item <name> <size> <clean command> [<dir>]: one dry-run line; on --apply, clean if the item is in CLEAN.
# A failed clean of <dir> (files in use or protected: rm of ~/Library/Caches always exits non-zero) is partly, with what's left.
item() {
  [ -n "$2" ] || return
  state=off; on "$CLEAN" "$1" && state=on
  printf '%-11s %-4s %s\n' "$1" "$state" "$2"
  if [ -n "$APPLY" ] && [ $state = on ]; then echo "+ $3"; sh -c "$3" >/dev/null 2>&1 ||
    { [ -n "${4:-}" ] && echo "  partly: $1, $(mb "$4") left (in use or protected)" || echo "  failed: $1"; }; fi
}

before=$(free_mb)

if [ -n "$APPLY" ] && [ "$SNAPSHOT" = yes ]; then
  sec snapshot
  tmutil localsnapshot 2>&1 | tail -1
  echo "pins freed space until removed: tmutil deletelocalsnapshots <date from above>"
fi

sec updates
if on "$UPDATE" brew && has brew; then
  e=$(brew update -q 2>&1 >/dev/null) || echo "brew update failed, the list is from the last index: $(echo "$e" | tail -1)"
  if lst brew outdated --verbose; then
    [ -n "$out" ] && echo "brew: $(echo "$out" | wc -l | tr -d ' ') outdated" || echo "brew: all current"
  fi
  [ -n "$out" ] && echo "$out" | sed 's/^/  /'
  [ -n "$APPLY" ] && [ -n "$out" ] && { echo "+ brew upgrade"; brew upgrade 2>&1 | grep -E '^==> (Upgrading|Pouring)|Error' ; }
fi
if on "$UPDATE" mas && has mas; then
  if lst mas outdated; then
    [ -n "$out" ] && echo "App Store:" && echo "$out" | sed 's/^/  /' || echo "App Store: all current"
  fi
  [ -n "$APPLY" ] && [ -n "$out" ] && { echo "+ mas upgrade"; mas upgrade; }
fi
if on "$UPDATE" mise && has mise; then
  if lst mise outdated; then
    [ -n "$out" ] && echo "mise:" && echo "$out" | sed 's/^/  /' || echo "mise: all current"
  fi
  [ -n "$APPLY" ] && [ -n "$out" ] && { echo "+ mise upgrade"; mise upgrade; }
fi
if on "$UPDATE" npm && has npm; then
  if lst npm outdated -g; then
    [ -n "$out" ] && echo "npm global:" && echo "$out" | sed 's/^/  /' || echo "npm global: all current"
  fi
  [ -n "$APPLY" ] && [ -n "$out" ] && { echo "+ npm update -g"; npm update -g; }
fi
# softwareupdate -l asks Apple's server and can hang behind a stuck softwareupdated: 120 s. macOS has no timeout(1),
# so a background job and a killer; the killer's output goes nowhere, so its leftover sleep holds no pipe open.
softwareupdate -l >"$E" 2>&1 & p=$!
( sleep 120; kill $p ) >/dev/null 2>&1 & k=$!
if wait $p; then
  out=$(sed -n 's/.*\* Label: /  /p' "$E")
  [ -n "$out" ] && printf 'macOS (list only, installing reboots):\n%s\n' "$out" || echo "macOS (list only, installing reboots): all current"
else echo "macOS: softwareupdate -l failed or gave no answer in 120 s: $(tail -1 "$E")"; fi
kill $k 2>/dev/null

sec "cleanup (size, on/off)"
has brew && item brew "$(brew cleanup -n --prune=30 2>/dev/null | sed -n 's/.*free approximately \([^ ]*\).*/\1/p')" "brew cleanup --prune=30"
L=$HOME/Library/Logs; old="find \"$L\" -path \"$L/DiagnosticReports\" -prune -o -type f -mtime +30"
item logs "$(eval "$old -exec du -k {} +" 2>/dev/null | awk '{s+=$1} END{printf "%dM", s/1024}')" "$old -exec rm -f {} +"
[ -d "$HOME/Library/Developer/Xcode/DerivedData" ] && item xcode "$(mb "$HOME/Library/Developer/Xcode/DerivedData")" "rm -rf \"$HOME/Library/Developer/Xcode/DerivedData/\"*" "$HOME/Library/Developer/Xcode/DerivedData"
clt && [ -d "$HOME/Library/Developer/CoreSimulator" ] && item simulators "$(xcrun simctl list devices unavailable 2>/dev/null | grep -c '(unavailable')" "xcrun simctl delete unavailable"
has npm && item npm "$(mb "$HOME/.npm/_cacache")" "npm cache clean --force"
has pnpm && item pnpm "$(mb "$(pnpm store path 2>/dev/null)")" "pnpm store prune"
has yarn && item yarn "$(mb "$(yarn cache dir 2>/dev/null)")" "yarn cache clean"
has pip3 && [ "$(command -v pip3)" != /usr/bin/pip3 ] && item pip "$(mb "$(pip3 cache dir 2>/dev/null)")" "pip3 cache purge"
has go && item go "$(mb "$(go env GOMODCACHE 2>/dev/null)")" "go clean -modcache"
item caches "$(mb "$HOME/Library/Caches")" "rm -rf \"$HOME/Library/Caches/\"*" "$HOME/Library/Caches"
has docker && docker info >/dev/null 2>&1 && item docker "$(docker system df --format '{{.Reclaimable}}' | tr '\n' ' ')" "docker system prune -f"
# Without Full Disk Access for the app running this, macOS won't list the Trash: du reads 0M and rm fails. Said as such,
# and never cleaned, instead of a "partly" with 0M left.
if [ -d "$HOME/.Trash" ] && ! ls "$HOME/.Trash" >/dev/null 2>&1; then
  state=off; on "$CLEAN" trash && state=on
  printf '%-11s %-4s %s\n' trash $state "skipped, macOS blocks reading the Trash here. To include it: System Settings > Privacy & Security > Full Disk Access, turn on the terminal app (over SSH: Sharing > Remote Login, allow full disk access for remote users)"
else item trash "$(mb "$HOME/.Trash")" "rm -rf \"$HOME/.Trash/\"*" "$HOME/.Trash"; fi

sec report
[ -n "$APPLY" ] && echo "mode: applied" || echo "mode: dry run, nothing changed"
echo "free: ${before}M before, $(free_mb)M now"
