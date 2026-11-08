#!/bin/sh
# Manual Windows recheck: run in Git Bash on the Windows machine, from the repo, after git pull.
#   sh tests/windows-manual.sh
# Re-approves the plugin probes, replaces this host's check.ps1 and maintain.ps1 in ~/.cwtfigo with fresh copies of
# the foundations (the CWTFIGO-FOUNDATION line removed, not adapted), runs them, and checks the 2026-11-07 fixes.
# On exit it puts back the host's own check.ps1, maintain.ps1, their .origin files and approved.sha256, so cw save never records the copies.
# Outputs stay in a temp dir for reading; they hold host names and addresses, redact before sharing.
# It approves and runs scripts in the real record: never anywhere else, e.g. from a `for t in tests/*.sh` loop.
case $(uname -s) in MINGW*|MSYS*|CYGWIN*) ;; *) echo "windows-manual.sh: Windows (Git Bash) only, skipped"; exit 0 ;; esac
cd "$(dirname "$0")/.." || exit 1
cw="sh skills/cwtfigo/scripts/cw"
REC=${CWTFIGO_HOME:-$HOME/.cwtfigo}
[ -s "$REC/self" ] || { echo "no $REC/self: run the first visit (cw run local collect) first"; exit 1; }
H=$REC/hosts/$(cat "$REC/self")
T=$(mktemp -d)
bad=0
fail() { echo "FAIL $*"; bad=1; }
run() { s=$(date +%s); $cw run local "$1" >"$T/$1" 2>"$T/$1.err" || fail "$1: exit $?"; echo "$1: $(($(date +%s) - s)) s"; }

$cw approve local probes
run logs
run health
run space
run env
grep -q 'KB2267602\|KB4052623' "$T/logs" && fail "logs: Defender updates still listed as software changes"
grep -q '^Netlogon ' "$T/health" && fail "health: Netlogon still under failed-services"
echo "logs says: $(grep 'rebooted since' "$T/logs" || echo 'no reboot line')"

mkdir "$T/orig"
for f in check.ps1 maintain.ps1 check.ps1.origin maintain.ps1.origin approved.sha256; do [ -f "$H/$f" ] && cp -p "$H/$f" "$T/orig/"; done
restore() { for f in check.ps1 maintain.ps1 check.ps1.origin maintain.ps1.origin approved.sha256; do if [ -f "$T/orig/$f" ]; then cp -p "$T/orig/$f" "$H/"; else rm -f "$H/$f"; fi; done; }
trap restore EXIT
trap 'exit 1' INT TERM HUP
for s in check maintain; do
  rm -f "$H/$s.ps1"
  $cw run local $s >/dev/null 2>&1   # copies the foundation and refuses it, as it should
  [ -f "$H/$s.ps1" ] || { fail "$s: foundation not copied"; continue; }
  sed -i '/^# CWTFIGO-FOUNDATION/d' "$H/$s.ps1"
  $cw approve local $s >/dev/null || fail "$s: approve"
  run $s
done
for s in logs health space env check maintain; do
  [ -s "$T/$s.err" ] && fail "$s wrote to stderr: $(head -c 200 "$T/$s.err")"
done
grep -q 'free on [A-Za-z]::' "$T/maintain" && fail "maintain: double colon in the report"

# cw takes its ssh down when a signal kills it (issue #3 item 7). A caller that dies the Windows way, without a signal
# (a tool timeout, a closed window), leaves cw's sh and its ssh/powershell running until the script ends; seen holding
# Git for Windows files. Listed, not killed: they may be another session's. Kill them by hand if their parent is gone.
powershell.exe -NoProfile -NonInteractive -Command "Get-CimInstance Win32_Process | Where-Object { \$_.ProcessId -ne \$PID -and \$_.CommandLine -match 'scripts/cw run' } | ForEach-Object { 'still running: ' + \$_.ProcessId + ' ' + \$_.Name + ', parent ' + \$_.ParentProcessId + ': ' + \$_.CommandLine }"

echo "outputs: $T"
[ $bad = 0 ] && echo "ALL OK"
exit $bad
