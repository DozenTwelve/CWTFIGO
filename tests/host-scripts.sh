#!/bin/sh
# Stub-based checks for the host scripts (foundations, probes, collect). Each script runs as a copy whose absolute
# paths (/boot, /etc, /run, ...) point into a temp dir, with a PATH of a few basic tools and fake commands only, and
# HOME in a temp dir: nothing on this machine is read or changed. Never --apply, never sudo.
#   sh tests/host-scripts.sh            scripts run under sh
#   SH=dash sh tests/host-scripts.sh    under dash (Debian's sh), or SH="busybox ash"
set -u
S=$(cd "$(dirname "$0")/.." && pwd)/skills/cwtfigo
F=$S/foundations; P=$S/scripts/probes
SH=${SH:-sh}; SH="$(command -v ${SH%% *})${SH#${SH%% *}}"   # absolute: the scripts run with PATH=$D/bin
# python3 by its real path, found before HOME moves: a version manager's shim (mise, pyenv) breaks under a temp HOME.
PY=$(python3 -c 'import sys; print(sys.executable)') || { echo "FAIL: the kinds.json check needs python3"; exit 1; }
T=$(mktemp -d); export HOME="$T/home"; mkdir "$HOME"
unset XDG_CACHE_HOME XDG_DATA_HOME   # the scripts' cache and Trash paths follow them: here they stay under the temp HOME
fail() { echo "FAIL: $* (copy: ${D:-}/script)"; exit 1; }

# fresh: a new fake root $D whose bin/ holds basic tools; stub <command> <sh body>: a fake command there.
fresh() {
  D=$(mktemp -d "$T/r.XXXXXX"); mkdir "$D/bin"
  for c in awk sed grep sort head tail cut ls tr cat wc find mkdir mktemp rm du sleep touch; do ln -s "$(command -v $c)" "$D/bin/$c"; done
}
# The link fresh made goes first: writing through it would rewrite the real command.
stub() { rm -f "$D/bin/$1"; printf '#!/bin/sh\n%s\n' "$2" > "$D/bin/$1"; chmod +x "$D/bin/$1"; }
# run <script> [args]: the copy runs, PATH=$D/bin. A placeholder first: $D itself may be under /var.
run() {
  f=$1; shift; e=
  for d in boot etc run var proc sys rom lib overlay; do e="$e -e s,\([[:space:]\"'(=<>#]\)/$d\([/[:space:];\"')]\),\1@ROOT@/$d\2,g"; done
  set -f; sed $e -e "s,@ROOT@,$D,g" "$f" > "$D/script"; set +f
  PATH=$D/bin $SH "$D/script" "$@"
}

# debian check: a reboot is pending only for a newer kernel of the running one's flavour.
fresh; mkdir "$D/boot"; stub uname 'echo 6.12.25+rpt-rpi-v8'
touch "$D/boot/vmlinuz-6.12.25+rpt-rpi-v8" "$D/boot/vmlinuz-6.12.34+rpt-rpi-2712"
out=$(run "$F/debian/check.sh" 2>/dev/null)
echo "$out" | grep -qx 'OK   running the newest installed kernel 6.12.25+rpt-rpi-v8' || fail "debian check: a newer rpi-2712 kernel is no reboot for rpi-v8: $out"
touch "$D/boot/vmlinuz-6.12.34+rpt-rpi-v8"
out=$(run "$F/debian/check.sh" 2>/dev/null)
echo "$out" | grep -qx 'WARN running kernel 6.12.25+rpt-rpi-v8, newest installed 6.12.34+rpt-rpi-v8: reboot pending' || fail "debian check: newer rpi-v8 kernel: $out"
fresh; mkdir "$D/boot"; stub uname 'echo 6.1.0-28-amd64'; touch "$D/boot/vmlinuz-6.1.0-28-amd64" "$D/boot/vmlinuz-6.1.0-28-rt-amd64"
run "$F/debian/check.sh" 2>/dev/null | grep -qx 'OK   running the newest installed kernel 6.1.0-28-amd64' || fail "debian check: rt-amd64 beside amd64"

# debian maintain: the dry run's private apt-get update runs none of apt.conf.d's update hooks, and nothing uses sudo.
fresh; stub id 'echo 1000'; stub sudo 'touch "$0.ran"'
stub apt-get 'echo "$*" >> "$0.log"; while [ $# -gt 0 ]; do [ "$1" = -c ] && cat "$2" >> "$0.conf"; shift; done; exit 0'
run "$F/debian/maintain.sh" >/dev/null 2>&1
grep -q ' update' "$D/bin/apt-get.log" || fail "debian maintain: the dry run should fetch fresh lists: $(cat "$D/bin/apt-get.log")"
for h in Pre-Invoke Post-Invoke Post-Invoke-Success; do
  grep -qx "#clear APT::Update::$h;" "$D/bin/apt-get.conf" 2>/dev/null || fail "debian maintain: dry run's apt-get update should clear APT::Update::$h"
done
[ -e "$D/bin/sudo.ran" ] && fail "debian maintain: the dry run used sudo"
# A listing that fails says so, never "0 pending", "all current" or "(none)".
fresh; stub id 'echo 1000'; stub apt-get 'case " $* " in *" -s "*) echo "E: broken" >&2; exit 100 ;; esac'; stub flatpak 'exit 1'
out=$(run "$F/debian/maintain.sh" 2>/dev/null)
echo "$out" | grep -q '0 pending\|all current\|(none)' && fail "debian maintain: failed listing read as nothing to do: $out"
[ "$(echo "$out" | grep -c 'failed (error above)$')" = 3 ] || fail "debian maintain: apt, flatpak and autoremove listings failed: $out"
# --apply without sudo installed (Debian with a root password): only its sudo check runs, cut out of the script.
fresh; stub id 'echo 1000'
{ echo APPLY=1; sed -n '/^has()/p; /^S=sudo/,/^before=/p' "$F/debian/maintain.sh"; } > "$D/apply-start.sh"
run "$D/apply-start.sh" 2>&1 | grep -q 'no sudo here: run it as root' || fail "debian maintain --apply without sudo: $(run "$D/apply-start.sh" 2>&1)"
# snaprev takes only the disabled revisions of a snap that also has an active one: `snap remove --revision` of a snap's
# only revision (one the owner turned off with snap disable) removes the whole snap. The dry run names what would go.
fresh; stub id 'echo 1000'; stub apt-get 'exit 0'; mkdir -p "$D/var/lib/snapd/snaps"
stub snap 'case "$*" in "list --all") cat <<EOF
Name    Version  Rev    Tracking       Publisher   Notes
core20  2023a    2015   latest/stable  canonical   base,disabled
core20  2023b    2105   latest/stable  canonical   base,disabled
core20  2024a    2200   latest/stable  canonical   base
hello   2.10     42     latest/stable  canonical   disabled
EOF
;; refresh*) ;; *) echo "$*" >> "$0.log" ;; esac'
out=$(run "$F/debian/maintain.sh" 2>/dev/null | grep '^snaprev')
echo "$out" | grep -Eq '^snaprev +on .*, 2 revisions: core20 2015, core20 2105$' || fail "debian maintain: snaprev should name core20's two old revisions and leave the disabled snap hello: $out"
# The apply path: only the snaprev lines, cut out of the script; snap is the stub.
{ echo 'APPLY=1; S=; CLEAN=snaprev'; sed -n '/^has()/p; /^on()/p; /^mb()/p; /^item()/,/^}/p; /^if has snap; then/,/^fi/p' "$F/debian/maintain.sh"; } > "$D/snaprev.sh"
run "$D/snaprev.sh" >/dev/null 2>&1
[ "$(cat "$D/bin/snap.log" 2>/dev/null)" = "remove core20 --revision=2015
remove core20 --revision=2105" ] || fail "debian maintain --apply snaprev should remove core20's two old revisions only: $(cat "$D/bin/snap.log" 2>&1)"
# Its --apply ends on a test that is false when no reboot is pending: the script must still exit 0 (not run here).
[ "$(tail -1 "$F/debian/maintain.sh")" = "exit 0" ] || fail "debian maintain should end with exit 0"

# debian and arch: outside adm/systemd-journal the journal size is this user's only, and says so.
for g in 'u staff' 'u adm'; do
  fresh; stub id "case \$1 in -u) echo 1000 ;; -Gn) echo $g ;; *) echo u ;; esac"
  stub journalctl 'echo "Archived and active journals take up 8.0M in the file system."'
  for s in debian/check debian/maintain arch/check arch/maintain; do
    l=$(run "$F/$s.sh" 2>/dev/null | grep '^\(INFO \)*journal')
    case $g in
      *adm) echo "$l" | grep -q "user's only" && fail "$s: groups $g read the whole journal: $l" ;;
      *) echo "$l" | grep -q "8.0M (this user's only: not in adm/systemd-journal)" || fail "$s: journal size outside adm: $l" ;;
    esac
  done
done

# macos check: a command that fails shows its error and reads as WARN, never as an empty OK.
fresh; for c in df memory_pressure sysctl pmset; do stub $c "echo '$c: broken' >&2; exit 1"; done
out=$(run "$F/macos/check.sh" 2>"$D/err")
grep -q '^df: broken' "$D/err" || fail "macos check: df's error should show: $(cat "$D/err")"
echo "$out" | grep -q '^OK' && fail "macos check: OK from failed commands: $out"
for w in disk memory swap thermal; do echo "$out" | grep -q "^WARN $w: no .*(error above)" || fail "macos check: failed $w should WARN: $out"; done

# macos check: failed background jobs are this user's that exited with an error, Apple's own and running ones aside.
fresh; stub launchctl 'printf "PID\tStatus\tLabel\n-\t78\tcom.apple.foo\n-\t1\torg.example.broken\n123\t2\torg.example.running\n-\t-9\torg.example.killed\n-\t0\torg.example.fine\n"'
out=$(run "$F/macos/check.sh" 2>/dev/null | grep 'background jobs')
[ "$out" = "WARN failed background jobs: org.example.broken (exit 1)" ] || fail "macos check: failed jobs: $out"
stub launchctl 'printf "PID\tStatus\tLabel\n-\t78\tcom.apple.foo\n"'
out=$(run "$F/macos/check.sh" 2>/dev/null | grep 'background jobs')
[ "$out" = "OK   no failed background jobs" ] || fail "macos check: only Apple's jobs failed: $out"
stub launchctl 'echo "launchctl: broken" >&2; exit 1'
run "$F/macos/check.sh" 2>/dev/null | grep -qx 'WARN launchctl list did not answer (error above)' || fail "macos check: launchctl failing should WARN"

# debian and arch check: battery health from sysfs, full against design; one with no numbers says so; none, no line.
for s in debian arch; do
  fresh; B=$D/sys/class/power_supply; mkdir -p "$B/BAT0" "$B/BAT1" "$B/AC"
  echo Battery > "$B/BAT0/type"; echo 30000000 > "$B/BAT0/energy_full"; echo 50000000 > "$B/BAT0/energy_full_design"; echo 412 > "$B/BAT0/cycle_count"
  echo Battery > "$B/BAT1/type"; echo Mains > "$B/AC/type"
  out=$(run "$F/$s/check.sh" 2>/dev/null | grep battery)
  echo "$out" | grep -qx 'WARN battery BAT0 holds 60% of new, 412 cycles' || fail "$s check: battery at 60%: $out"
  echo "$out" | grep -qx "WARN battery BAT1: no full and design capacity in $B/BAT1" || fail "$s check: battery without numbers: $out"
  echo 4800000 > "$B/BAT1/charge_full"; echo 5000000 > "$B/BAT1/charge_full_design"; echo 0 > "$B/BAT1/cycle_count"
  run "$F/$s/check.sh" 2>/dev/null | grep -qx 'OK   battery BAT1 holds 96% of new' || fail "$s check: charge_full battery, no cycles"
  rm -r "$B/BAT0" "$B/BAT1"; run "$F/$s/check.sh" 2>/dev/null | grep -q battery && fail "$s check: no battery, no line"
done

# macos maintain: logs counts only files older than 30 days, never DiagnosticReports (the probes read them).
fresh; L=$HOME/Library/Logs; mkdir -p "$L/DiagnosticReports" "$L/app"
for f in DiagnosticReports/old.ips app/old.log app/new.log; do head -c 1048576 /dev/zero > "$L/$f"; done
touch -t 202601010000 "$L/DiagnosticReports/old.ips" "$L/app/old.log"
out=$(run "$F/macos/maintain.sh" 2>/dev/null)
echo "$out" | grep -Eqx 'logs +on +1M' || fail "macos maintain: logs should count app/old.log only: $(echo "$out" | grep '^logs')"
# A failed listing says so, never "all current"; npm outdated's exit 1 with a list is an answer.
fresh; for c in mas mise; do stub $c "echo '$c: broken' >&2; exit 1"; done
stub brew 'case $1 in update) echo "Error: Failed to fetch" >&2; exit 1 ;; outdated) echo "Error: boom" >&2; exit 1 ;; esac'
stub npm 'echo "npm error network" >&2; exit 1'
out=$(run "$F/macos/maintain.sh" 2>/dev/null)
echo "$out" | grep -E '^(brew|App Store|mise|npm global): all current' && fail "macos maintain: failed listing read as all current: $out"
for l in 'brew update failed, .*: Error: Failed to fetch' 'brew: outdated failed: Error: boom' 'mas: outdated failed: mas: broken' \
  'mise: outdated failed: mise: broken' 'npm: outdated failed: npm error network'; do
  echo "$out" | grep -qx "$l" || fail "macos maintain: missing '$l': $out"
done
stub npm 'echo "Package  Current  Wanted  Latest"; echo "pnpm     9.0.0    9.0.0   10.0.0"; exit 1'
run "$F/macos/maintain.sh" 2>/dev/null | grep -qx '  pnpm     9.0.0    9.0.0   10.0.0' || fail "macos maintain: npm outdated's list (exit 1) should show"
# softwareupdate -l is bounded (here 1 s instead of 120): a hang says so and the dry run goes on.
fresh; sed 's/sleep 120;/sleep 1;/' "$F/macos/maintain.sh" > "$D/m.sh"; stub softwareupdate 'exec sleep 20'
t0=$(date +%s); out=$(run "$D/m.sh" 2>/dev/null); t1=$(date +%s)
[ $((t1 - t0)) -lt 10 ] || fail "macos maintain: a hanging softwareupdate -l held the dry run $((t1 - t0)) s"
echo "$out" | grep -q '^macOS: softwareupdate -l failed or gave no answer' || fail "macos maintain: softwareupdate hang: $out"
echo "$out" | grep -q '^## report' || fail "macos maintain: the dry run should go on after the hang: $out"
stub softwareupdate 'echo "Software Update Tool"; echo "* Label: macOS Tahoe 26.1-25B78"'
run "$D/m.sh" 2>/dev/null | grep -qx '  macOS Tahoe 26.1-25B78' || fail "macos maintain: softwareupdate -l label"

# macos maintain: a Trash macOS won't list (no Full Disk Access) says so and how to allow it, not 0M.
fresh; mkdir "$HOME/.Trash"; chmod 000 "$HOME/.Trash"
out=$(run "$F/macos/maintain.sh" trash 2>/dev/null | grep '^trash'); chmod 755 "$HOME/.Trash"
echo "$out" | grep -Eq '^trash +on +skipped, macOS blocks reading the Trash here\. To include it: .*Full Disk Access' || fail "macos maintain: an unreadable Trash should say macOS blocked it: $out"
run "$F/macos/maintain.sh" 2>/dev/null | grep -Eqx 'trash +off +0M' || fail "macos maintain: a readable empty Trash is 0M, off"
rmdir "$HOME/.Trash"

# macos maintain --apply: a clean of a dir that leaves files in use or protected is "partly", not "failed".
# item() alone, cut out of the script, on a temp dir; nothing else of --apply runs.
fresh; ln -s "${SH%% *}" "$D/bin/sh"; X=$D/cache; mkdir -p "$X/locked"; touch "$X/gone" "$X/locked/f"; chmod 555 "$X/locked"
{ echo 'APPLY=1; CLEAN="caches trash"'; sed -n '/^on()/p; /^mb()/p; /^item()/,/^}/p' "$F/macos/maintain.sh"
  echo "item caches 1M 'rm -rf \"$X/\"*' '$X'"; echo "item trash 1M 'rm -rf \"$X/\"*'"; } > "$D/item.sh"
out=$(PATH=$D/bin $SH "$D/item.sh" 2>&1); chmod 755 "$X/locked"   # not run(): it would rewrite $X under /var
echo "$out" | grep -qx '  partly: caches, [0-9]*M left (in use or protected)' || fail "macos maintain: a partly cleaned dir should say partly: $out"
[ -e "$X/gone" ] && fail "macos maintain: item should still clean what it can"
echo "$out" | grep -qx '  failed: trash' || fail "macos maintain: without a dir a failed clean stays failed: $out"

# maintain: words after --apply are the owner's pick for that run (no edit, no new hash): only what is named runs.
# `update` is the upgrades, any other word a cleanup item in place of CLEAN; words without `update` under --apply
# upgrade nothing (NOUP=1). No words keep CLEAN. A word the script doesn't know (a typo, the old `none`, an --apply
# that isn't first) stops it with exit 1. Only the argument lines run, cut out of each script.
fresh
for s in macos debian arch; do
  { sed -n '/^APPLY=/p; /^ITEMS=/,/^else c=/p' "$F/$s/maintain.sh"; echo 'echo "$APPLY|$NOUP|$CLEAN"'; } > "$D/args.sh"
  c=$(sed -n 's/^CLEAN="\(.*\)"$/\1/p' "$F/$s/maintain.sh"); i=${c%% *}
  { echo "CLEAN=\"$c\""; cat "$D/args.sh"; } > "$D/a.sh"
  # args | APPLY | NOUP | CLEAN after (= the script's own CLEAN)
  for t in "--apply $i trash|1|1|$i trash" "--apply update|1||" "--apply update $i|1||$i" "--apply $i update|1||$i" "--apply|1||=" "|||=" "$i|||$i"; do
    a=${t%%|*}; w=${t#*|}; [ "${w##*|}" = = ] && w="${w%|*}|$c"
    o=$(PATH=$D/bin $SH "$D/a.sh" $a)
    [ "$o" = "$w" ] || fail "$s maintain: args '$a' should give APPLY|NOUP|CLEAN '$w', got '$o'"
  done
  for a in "--apply trahs" "--apply none" "--apply $i trahs" "trahs" "$i --apply"; do
    o=$(PATH=$D/bin $SH "$D/a.sh" $a); [ $? = 1 ] || fail "$s maintain: args '$a' should exit 1: $o"
    [ "$(echo "$o" | sed -n 1p)" = "unknown item: ${a##* }" ] && [ "$(echo "$o" | wc -l)" -eq 2 ] && echo "$o" | grep -q "^known: update $i .*trash\$" ||
      fail "$s maintain: args '$a' should name the unknown word and the known ones, nothing else: $o"
  done
  # ITEMS is what that check knows: it names every item the script has, no more.
  [ "$(sed -n 's/^ITEMS="\(.*\)"$/\1/p' "$F/$s/maintain.sh" | tr ' ' '\n' | sort)" = "$(grep -v '^ *#' "$F/$s/maintain.sh" | grep -o 'item [a-z]* "\$(' | cut -d' ' -f2 | sort)" ] ||
    fail "$s maintain: ITEMS should list exactly the items the script has"
done
# maintain --apply with no items never empties the Trash, even with trash in CLEAN: that takes the owner's yes in chat
# and a run that names it. The CLEAN lines, on, mb, item and the trash item, cut out of each script; rm is a stub.
for s in macos debian arch; do
  fresh; ln -s "${SH%% *}" "$D/bin/sh"; stub rm 'touch "$0.ran"'; mkdir -p "$HOME/.Trash" "$HOME/.local/share/Trash"
  { sed -n 's/^CLEAN="/CLEAN="trash /p' "$F/$s/maintain.sh"; echo 'APPLY=1; S='
    sed -n '/^ITEMS=/,/^else c=/p; /^on()/p; /^mb()/p; /^item()/,/^}/p; /^item trash/p; s/^else \(item trash.*\); fi$/\1/p' "$F/$s/maintain.sh"; } > "$D/trash.sh"
  out=$(run "$D/trash.sh" 2>&1); [ -e "$D/bin/rm.ran" ] && fail "$s maintain --apply with no items emptied the Trash: $out"
  echo "$out" | grep -Eq '^trash +off ' || fail "$s maintain --apply with no items should show trash off: $out"
  run "$D/trash.sh" trash >/dev/null 2>&1; [ -e "$D/bin/rm.ran" ] || fail "$s maintain --apply trash should empty the Trash"
done
# The same for the Recycle Bin on Windows: only its CLEAN lines, where pwsh is installed.
if command -v pwsh >/dev/null; then
  fresh; { sed -n 's/^\$CLEAN = '"'"'/$CLEAN = '"'"'recyclebin /p' "$F/windows/maintain.ps1"
    sed -n '/^\$APPLY = /p; /^\$ITEMS = /,/^} else { \$CLEAN/p' "$F/windows/maintain.ps1"; echo '"$NOUP|$CLEAN"'; } > "$D/rb.ps1"
  pwsh -NoProfile -NonInteractive -File "$D/rb.ps1" --apply | grep -qw recyclebin && fail "windows maintain --apply with no items keeps recyclebin in CLEAN"
  pwsh -NoProfile -NonInteractive -File "$D/rb.ps1" --apply recyclebin | grep -qx 'True|recyclebin' || fail "windows maintain --apply recyclebin should clean it and upgrade nothing"
  # The same words as the sh scripts: update, the items, and a stop at anything else.
  pwsh -NoProfile -NonInteractive -File "$D/rb.ps1" --apply npm update | grep -qx 'False|npm' || fail "windows maintain --apply npm update: the upgrades and npm"
  for a in recyclebni none; do
    o=$(pwsh -NoProfile -NonInteractive -File "$D/rb.ps1" --apply $a); [ $? = 1 ] && [ "$(echo "$o" | sed -n 1p)" = "unknown item: $a" ] && [ "$(echo "$o" | wc -l)" -eq 2 ] ||
      fail "windows maintain --apply $a should stop at the unknown word: $o"
  done
  [ "$(sed -n "s/^\$ITEMS = '\(.*\)'$/\1/p" "$F/windows/maintain.ps1" | tr ' ' '\n' | sort)" = "$(grep -v '^ *#' "$F/windows/maintain.ps1" | grep -o 'item [a-z]* (' | cut -d' ' -f2 | sort)" ] ||
    fail "windows maintain: ITEMS should list exactly the items the script has"
fi
# The dry run shows the pick as on/off too.
fresh; stub id 'case $1 in -u) echo 1000 ;; -Gn) echo adm ;; *) echo u ;; esac'
stub journalctl 'echo "Archived and active journals take up 8.0M in the file system."'
for s in debian arch; do
  run "$F/$s/maintain.sh" usercache 2>/dev/null | grep -Eq '^journal +off ' || fail "$s maintain: journal not in the pick should be off"
  run "$F/$s/maintain.sh" 2>/dev/null | grep -Eq '^journal +on ' || fail "$s maintain: journal is in CLEAN, should be on"
done

# Whole --apply runs, every command a stub that writes its call to $D/bin/log, HOME the temp one: `--apply <item>`
# cleans it, upgrades nothing and says so; `--apply update` upgrades and cleans nothing; a typo stops before anything
# runs; --apply alone still does both. stdin is /dev/null, and apt and pacman have nothing pending: their question
# needs a terminal.
has() { grep -qx -- "$1" "$D/bin/log" 2>/dev/null; }
mac() {   # one outdated formula, one outdated npm package, a file in the Trash
  fresh; ln -s "${SH%% *}" "$D/bin/sh"; mkdir -p "$HOME/.Trash"; touch "$HOME/.Trash/f"
  stub brew 'echo "brew $*" >> "${0%/*}/log"; case $1 in outdated) echo "foo (1.0) < 2.0" ;; cleanup) [ "$2" = -n ] && echo "would free approximately 5MB of disk space." ;; esac'
  stub npm 'echo "npm $*" >> "${0%/*}/log"; [ "$1" != outdated ] || echo "pnpm 9 9 10"'
  stub softwareupdate 'echo "softwareupdate $*" >> "${0%/*}/log"'
}
mac; out=$(run "$F/macos/maintain.sh" --apply trash </dev/null 2>&1) || fail "macos maintain --apply trash: $out"
[ -e "$HOME/.Trash/f" ] && fail "macos maintain --apply trash should empty the Trash: $out"
grep -E ' (update|upgrade|outdated)|softwareupdate|^brew cleanup --prune' "$D/bin/log" && fail "macos maintain --apply trash upgraded, listed or cleaned something else: $out"
echo "$out" | grep -q '^updates: not asked for ' && echo "$out" | grep -qx 'mode: applied' || fail "macos maintain --apply trash should say the upgrades were not asked for: $out"
mac; out=$(run "$F/macos/maintain.sh" --apply update </dev/null 2>&1) || fail "macos maintain --apply update: $out"
has 'brew upgrade' && has 'npm update -g' && has 'softwareupdate -l' || fail "macos maintain --apply update should upgrade: $(cat "$D/bin/log")"
has 'brew cleanup --prune=30' || has 'npm cache clean --force' || [ ! -e "$HOME/.Trash/f" ] && fail "macos maintain --apply update cleaned something: $(cat "$D/bin/log")"
echo "$out" | grep -q 'not asked for' && fail "macos maintain --apply update: the upgrades were asked for: $out"
mac; out=$(run "$F/macos/maintain.sh" --apply trahs </dev/null 2>&1); [ $? = 1 ] || fail "macos maintain --apply trahs should exit 1: $out"
[ "$(echo "$out" | sed -n 1p)" = "unknown item: trahs" ] && [ ! -e "$D/bin/log" ] && [ -e "$HOME/.Trash/f" ] || fail "macos maintain --apply trahs should run nothing: $out $(cat "$D/bin/log" 2>&1)"
mac; out=$(run "$F/macos/maintain.sh" --apply </dev/null 2>&1) || fail "macos maintain --apply: $out"
has 'brew upgrade' && has 'npm update -g' && has 'brew cleanup --prune=30' && has 'npm cache clean --force' && [ -e "$HOME/.Trash/f" ] || fail "macos maintain --apply should upgrade, clean CLEAN and leave the Trash: $(cat "$D/bin/log")"
echo "$out" | grep -qx 'mode: applied' || fail "macos maintain --apply should end applied: $out"
rm -r "$HOME/.Trash"

deb() {   # sudo passes its command on; $1: what apt-get -s upgrade lists
  fresh; stub id 'echo 1000'; stub apt-mark :
  stub sudo 'echo "sudo $*" >> "${0%/*}/log"; [ "$1" = -v ] || exec "$@"'
  stub apt-get 'echo "apt-get $*" >> "${0%/*}/log"; case " $* " in *" -s upgrade "*) echo "'"${1:-}"'" ;; esac'
}
deb; out=$(run "$F/debian/maintain.sh" --apply aptcache </dev/null 2>&1) || fail "debian maintain --apply aptcache: $out"
has 'apt-get clean' || fail "debian maintain --apply aptcache should clean the cache: $(cat "$D/bin/log")"
grep -E 'update|upgrade' "$D/bin/log" && fail "debian maintain --apply aptcache updated or upgraded: $out"
echo "$out" | grep -q '^updates: not asked for ' && echo "$out" | grep -qx 'mode: applied' || fail "debian maintain --apply aptcache should say the upgrades were not asked for: $out"
deb; out=$(run "$F/debian/maintain.sh" --apply update </dev/null 2>&1) || fail "debian maintain --apply update: $out"
has 'apt-get update -qq' && has 'apt-get upgrade --with-new-pkgs' || fail "debian maintain --apply update should upgrade: $(cat "$D/bin/log")"
has 'apt-get clean' && fail "debian maintain --apply update cleaned something: $(cat "$D/bin/log")"
deb; out=$(run "$F/debian/maintain.sh" --apply aptcahce </dev/null 2>&1); [ $? = 1 ] || fail "debian maintain --apply aptcahce should exit 1: $out"
[ "$(echo "$out" | sed -n 1p)" = "unknown item: aptcahce" ] && [ ! -e "$D/bin/log" ] || fail "debian maintain --apply aptcahce should run nothing, not even sudo -v: $out $(cat "$D/bin/log" 2>&1)"
# The one whole run to the end: --apply alone.
deb; out=$(run "$F/debian/maintain.sh" --apply </dev/null 2>&1) || fail "debian maintain --apply should exit 0: $out"
has 'sudo -v' && has 'apt-get update -qq' && has 'apt-get upgrade --with-new-pkgs' && has 'apt-get clean' || fail "debian maintain --apply should upgrade and clean: $(cat "$D/bin/log")"
echo "$out" | grep -qx 'mode: applied' && echo "$out" | grep -qx 'no .dpkg-dist' || fail "debian maintain --apply should end applied: $out"

arch() {   # $1: checkupdates' body (exit 2 = nothing pending)
  fresh; ln -s "${SH%% *}" "$D/bin/sh"; stub id 'echo 1000'; stub uname 'echo 6.1'; stub checkupdates "$1"
  stub sudo 'echo "sudo $*" >> "${0%/*}/log"; [ "$1" = -v ] || exec "$@"'
  for c in pacman paccache; do stub $c "echo \"$c \$*\" >> \"\${0%/*}/log\""; done
}
arch 'exit 2'; out=$(run "$F/arch/maintain.sh" --apply pkgcache </dev/null 2>&1) || fail "arch maintain --apply pkgcache: $out"
has 'paccache -rk2' && has 'paccache -ruk0' || fail "arch maintain --apply pkgcache should clean the cache: $(cat "$D/bin/log")"
grep 'pacman -S' "$D/bin/log" && fail "arch maintain --apply pkgcache synced or upgraded: $out"
echo "$out" | grep -q '^updates: not asked for ' && echo "$out" | grep -qx 'mode: applied' || fail "arch maintain --apply pkgcache should say the upgrades were not asked for: $out"
arch 'exit 2'; out=$(run "$F/arch/maintain.sh" --apply update </dev/null 2>&1) || fail "arch maintain --apply update: $out"
has 'pacman -Sy --needed --noconfirm archlinux-keyring' && has 'pacman -Su' || fail "arch maintain --apply update should upgrade: $(cat "$D/bin/log")"
grep 'paccache -r' "$D/bin/log" && fail "arch maintain --apply update cleaned something: $out"
arch 'exit 2'; out=$(run "$F/arch/maintain.sh" --apply pkgcahce </dev/null 2>&1); [ $? = 1 ] || fail "arch maintain --apply pkgcahce should exit 1: $out"
[ "$(echo "$out" | sed -n 1p)" = "unknown item: pkgcahce" ] && [ ! -e "$D/bin/log" ] || fail "arch maintain --apply pkgcahce should run nothing, not even sudo -v: $out $(cat "$D/bin/log" 2>&1)"
arch 'exit 2'; out=$(run "$F/arch/maintain.sh" --apply </dev/null 2>&1) || fail "arch maintain --apply: $out"
has 'pacman -Su' && has 'paccache -rk2' && echo "$out" | grep -qx 'mode: applied' || fail "arch maintain --apply should upgrade and clean: $out $(cat "$D/bin/log")"

# openwrt maintain: a package in UPGRADE whose upgrade would also move a core package is skipped, and the dry run says so.
for pm in apk opkg; do
  fresh; mkdir "$D/etc"; echo "DISTRIB_ID=OpenWrt" > "$D/etc/openwrt_release"; stub id 'echo 0'
  sed 's/^UPGRADE=""/UPGRADE="luci-app-foo luci-app-bar"/' "$F/openwrt/maintain.sh" > "$D/m.sh"
  stub apk 'case "$*" in
"upgrade --simulate") printf "(1/3) Upgrading libubox20240329 (a -> b)\n(2/3) Upgrading luci-app-foo (1 -> 2)\n(3/3) Upgrading luci-app-bar (1 -> 2)\n" ;;
"upgrade --simulate luci-app-foo") printf "(1/2) Upgrading libubox20240329 (a -> b)\n(2/2) Upgrading luci-app-foo (1 -> 2)\n" ;;
"upgrade --simulate luci-app-bar") printf "(1/1) Upgrading luci-app-bar (1 -> 2)\n" ;;
esac'
  stub opkg 'case "$*" in
list-upgradable) printf "libubox - a - b\nluci-app-foo - 1 - 2\nluci-app-bar - 1 - 2\n" ;;
"upgrade --noaction luci-app-foo") printf "Upgrading libubox on root from a to b...\nUpgrading luci-app-foo on root from 1 to 2...\n" ;;
"upgrade --noaction luci-app-bar") printf "Upgrading luci-app-bar on root from 1 to 2...\n" ;;
esac'
  [ $pm = opkg ] && mv "$D/bin/apk" "$D/bin/apk.off"
  out=$(run "$D/m.sh" 2>&1)
  echo "$out" | grep -q '^  luci-app-foo .*(in UPGRADE, --apply skips it: would also change core: libubox[0-9]*)$' || fail "openwrt maintain ($pm): foo drags in libubox: $out"
  echo "$out" | grep -q '^  luci-app-bar .*(in UPGRADE)$' || fail "openwrt maintain ($pm): bar is fine: $out"
done

# openwrt check: enabled services come from the S links in /etc/rc.d; no init script runs.
fresh; mkdir -p "$D/etc/init.d" "$D/etc/rc.d"; echo "DISTRIB_ID=OpenWrt" > "$D/etc/openwrt_release"
for n in foo bar; do printf '#!/bin/sh\n# procd_open_instance\ntouch "$0.ran"\n' > "$D/etc/init.d/$n"; chmod +x "$D/etc/init.d/$n"; done
touch "$D/etc/rc.d/S50foo" "$D/etc/rc.d/K10bar"
stub ubus 'echo "{ \"running\": false }"'
out=$(run "$F/openwrt/check.sh" 2>/dev/null)
echo "$out" | grep -qx 'WARN enabled but not running: foo' || fail "openwrt check: foo is enabled (S link), bar isn't: $out"
[ -e "$D/etc/init.d/foo.ran" ] || [ -e "$D/etc/init.d/bar.ran" ] && fail "openwrt check ran an init script"

# smart probe: a sleeping disk stays asleep (-n standby) and the probe says why it shows nothing.
fresh; mkdir -p "$D/sys/block/sda"; stub id 'echo 0'
stub smartctl 'echo "$*" >> "$0.log"; case " $* " in *" -n standby "*) echo "Device is in STANDBY mode, exit(2)"; exit 2 ;; esac; echo "SMART overall-health self-assessment test result: PASSED"'
out=$(run "$P/smart.sh")
grep -q -- '-n standby' "$D/bin/smartctl.log" || fail "smart: smartctl without -n standby wakes the disk: $(cat "$D/bin/smartctl.log")"
echo "$out" | grep -q '^asleep, not woken' || fail "smart: a sleeping disk should say so: $out"

# wifi probe: NetworkManager's cached scan, no rescan.
fresh; stub uname 'echo Linux'; stub nmcli 'echo "$*" >> "$0.log"; echo "yes:home:6:270 Mbit/s:80:WPA2"'
run "$P/wifi.sh" | grep -qx 'yes:home:6:270 Mbit/s:80:WPA2' || fail "wifi: nmcli's active line"
grep -q -- '--rescan no' "$D/bin/nmcli.log" || fail "wifi: nmcli dev wifi should not rescan: $(cat "$D/bin/nmcli.log")"

# perf probe: nvidia-smi runs under timeout, where there is one.
fresh; stub uname 'echo Linux'; stub timeout 'echo "$*" >> "$0.log"; shift; exec "$@"'; stub nvidia-smi 'echo "RTX 4090, 3 %"'
run "$P/perf.sh" | grep -qx 'RTX 4090, 3 %' || fail "perf: nvidia-smi line"
grep -q '^15 nvidia-smi ' "$D/bin/timeout.log" 2>/dev/null || fail "perf: nvidia-smi should run under timeout"

# apps probe: dnf reads its cache only (-C), no metadata refresh over the network.
fresh; stub uname 'echo Linux'; stub dnf 'echo "$*" >> "$0.log"; printf "git\nvim\nhtop\n"'
run "$P/apps.sh" | grep -q 'dnf user-installed: *3$' || fail "apps: dnf user-installed count"
grep -q '^-C repoquery' "$D/bin/dnf.log" || fail "apps: dnf repoquery should be -C: $(cat "$D/bin/dnf.log")"

# PowerShell scripts, where pwsh is installed (7, not the 5.1 the targets run: semantics only, syntax is cw.sh's).
if command -v pwsh >/dev/null; then
  ps() { f=$1; shift; PATH=$D/bin:$PATH pwsh -NoProfile -NonInteractive -File "$f" "$@"; }
  # windows check: offline, so no package manager runs (winget and choco would refresh their sources).
  fresh; for c in winget choco scoop; do stub $c "touch \"\$0.ran\""; done
  ps "$F/windows/check.ps1" >/dev/null 2>&1
  for c in winget choco scoop; do [ -e "$D/bin/$c.ran" ] && fail "windows check: ran $c"; done
  # windows maintain --apply, whole, as the sh scripts above: PATH holds only the stubs, TEMP is a temp dir with one
  # old file, and what Windows alone has (COM, the registry, the Recycle Bin) fails quietly under pwsh on Unix.
  PWSH=$(command -v pwsh)
  win() {
    fresh; mkdir "$D/tmp"; touch -t 202601010000 "$D/tmp/old"
    stub winget 'echo "winget $*" >> "${0%/*}/log"; [ "$*" != "upgrade --accept-source-agreements" ] || printf "%s\r\n" "Name Id Version Available Source" "--------------------" "Foo Vendor.Foo 1.0 2.0 winget"'
  }
  wm() { PATH=$D/bin TEMP=$D/tmp "$PWSH" -NoProfile -NonInteractive -File "$F/windows/maintain.ps1" "$@" </dev/null 2>&1; }
  win; out=$(wm --apply usertemp) || fail "windows maintain --apply usertemp: $out"
  [ ! -e "$D/tmp/old" ] && [ ! -e "$D/bin/log" ] || fail "windows maintain --apply usertemp should clean TEMP and run no winget: $out $(cat "$D/bin/log" 2>&1)"
  echo "$out" | grep -q '^updates: not asked for ' && echo "$out" | grep -qx 'mode: applied' || fail "windows maintain --apply usertemp should say the upgrades were not asked for: $out"
  win; out=$(wm --apply update) || fail "windows maintain --apply update: $out"
  grep -q '^winget upgrade --id Vendor.Foo --exact --silent ' "$D/bin/log" && [ -e "$D/tmp/old" ] || fail "windows maintain --apply update should upgrade and clean nothing: $out $(cat "$D/bin/log" 2>&1)"
  win; out=$(wm --apply usertmp); [ $? = 1 ] || fail "windows maintain --apply usertmp should exit 1: $out"
  [ "$(echo "$out" | sed -n 1p)" = "unknown item: usertmp" ] && [ ! -e "$D/bin/log" ] && [ -e "$D/tmp/old" ] || fail "windows maintain --apply usertmp should run nothing: $out"
  win; out=$(wm --apply) || fail "windows maintain --apply: $out"
  grep -q '^winget upgrade --id Vendor.Foo ' "$D/bin/log" && [ ! -e "$D/tmp/old" ] && echo "$out" | grep -qx 'mode: applied' || fail "windows maintain --apply should upgrade and clean: $out"
  # collect: choco counts installed packages, on v1 (whose plain list is the remote feed) and on v2.
  for v in 1.4.0 2.2.2; do
    fresh; stub choco "case \"\$*\" in
--version) echo $v ;;
'list --local-only -r') [ $v = 1.4.0 ] || exit 1; printf 'git|2.47.0\n7zip|24.08\n' ;;
'list -r') [ $v = 1.4.0 ] && seq 1 40 | sed 's/\$/|1.0/' || printf 'git|2.47.0\n7zip|24.08\n' ;;
esac"
    out=$(ps "$S/scripts/collect.ps1" 2>&1)
    echo "$out" | grep -qx 'choco: 2' || fail "collect.ps1: choco $v installed count: $out"
  done
fi

# knowledge/kinds.json, which case items take their kind from: valid JSON, each label in one kind only, and no guess
# or attempt under root cause or resolution (cw search reads any resolution as fixed).
o=$("$PY" - "$S/knowledge/kinds.json" <<'EOF' 2>&1
import collections, json, re, sys
k = json.load(open(sys.argv[1]))["kinds"]
n = collections.Counter(m for x in k for m in x["members"])
print(*sorted(m for m in n if n[m] > 1), sep="\n")
for x in k:
    if x["kind"] in ("root cause", "resolution"):
        print(*(m for m in x["members"] if re.search(r"possible|likely|suspect|guess|unverified|unconfirmed|hypothes|attempt|suggest", m)), sep="\n")
EOF
)
[ -z "$(echo "$o" | tr -d '[:space:]')" ] || fail "kinds.json: labels in two kinds, or guesses under root cause or resolution: $o"

# Temp dirs are left for the OS to clean (under $TMPDIR); a failing run's copy is $D/script.
echo "ok"
