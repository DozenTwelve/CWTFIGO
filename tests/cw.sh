#!/bin/sh
# Self-check for scripts/cw: approval gate, template copy, id mismatch, save. Usage: sh tests/cw.sh
set -u
CW="$(cd "$(dirname "$0")/.." && pwd)/skills/cwtfigo/scripts/cw"
export CWTFIGO_HOME=$(mktemp -d)/rec
H=$CWTFIGO_HOME/hosts/box
fail() { echo "FAIL: $*"; exit 1; }

# A Mac without the Command Line Tools: say so before git or python3 stubs pop a dialog.
M=$(mktemp -d); printf '#!/bin/sh\necho Darwin\n' > "$M/uname"; printf '#!/bin/sh\nexit 2\n' > "$M/xcode-select"; chmod +x "$M/uname" "$M/xcode-select"
out=$(PATH=$M:$PATH CWTFIGO_HOME=$M/rec sh "$CW" status 2>&1); [ $? = 1 ] || fail "a Mac without CLT should stop"
echo "$out" | grep -q 'xcode-select --install' || fail "a Mac without CLT should say how to get it: $out"
[ -e "$M/rec" ] && fail "a Mac without CLT must not reach git init"
# No sha256sum or shasum: approvals are hashes, so cw stops before anything else. A hash tool that prints nothing
# approves nothing.
Z=$(mktemp -d); mkdir "$Z/bin"; for c in dirname uname xcode-select; do p=$(command -v $c) && ln -s "$p" "$Z/bin/$c"; done
out=$(PATH=$Z/bin CWTFIGO_HOME=$Z/rec "$(command -v sh)" "$CW" status 2>&1); [ $? = 1 ] && echo "$out" | grep -q 'neither sha256sum nor shasum' || fail "no hash tool should stop cw: $out"
mkdir "$Z/fake"; printf '#!/bin/sh\n' > "$Z/fake/sha256sum"; chmod +x "$Z/fake/sha256sum"
zw() { PATH=$Z/fake:$PATH CWTFIGO_HOME=$Z/rec sh "$CW" "$@"; }
zw name z >/dev/null; mkdir -p "$Z/rec/hosts/z"; echo 'echo a' > "$Z/rec/hosts/z/a.sh"; printf 'touch "%s/ran"\n' "$Z" > "$Z/rec/hosts/z/b.sh"
zw approve local a >/dev/null; zw run local b >/dev/null 2>&1; [ $? = 3 ] && [ ! -e "$Z/ran" ] || fail "an empty hash must approve nothing"
# No git: say what to install, not "cannot create" the record, and create nothing.
G=$(mktemp -d); for c in dirname uname xcode-select sha256sum shasum; do p=$(command -v $c) && ln -s "$p" "$G/$c"; done
out=$(PATH=$G CWTFIGO_HOME=$G/rec "$(command -v sh)" "$CW" status 2>&1); [ $? = 1 ] || fail "no git should stop cw: $out"
echo "$out" | grep -q 'keeps its notes in git: install it (Debian/Ubuntu/Mint: sudo apt install git;.*Mac: xcode-select --install)' || fail "no git should say how to install it: $out"
echo "$out" | grep -q 'cannot create' && fail "no git is not a permissions problem: $out"
[ -e "$G/rec" ] && fail "no git: nothing should be created"

# cw tui: the TUI of exactly this plugin's version, from its tui-v<version> release, checked by its .sha256. A fake
# uname and curl serve a tarball built here (a fake gh only records whether it was called); HOME is a temp dir. Run by $SH (SH=dash sh tests/cw.sh) if set.
T=$(mktemp -d); mkdir "$T/bin" "$T/pkg" "$T/home"
V=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$(dirname "$CW")/../../../.claude-plugin/plugin.json"); [ -n "$V" ] || fail "no plugin version"
A=cwtfigo-tui-Linux-x86_64.tar.gz
printf '#!/bin/sh\necho new\n' > "$T/pkg/cwtfigo"; echo MIT > "$T/pkg/LICENSE"; tar -czf "$T/srv.tar.gz" -C "$T/pkg" cwtfigo LICENSE
tsum() { { sha256sum "$1" 2>/dev/null || shasum -a 256 "$1"; } | cut -d' ' -f1; }
echo "$(tsum "$T/srv.tar.gz")  $A" > "$T/srv.sha256"
printf '#!/bin/sh\ncase $1 in -m) echo "${FAKE_M:-x86_64}" ;; *) echo "${FAKE_OS:-Linux}" ;; esac\n' > "$T/bin/uname"
printf '#!/bin/sh\necho "$*" >> "$FAKE/curl.args"; [ -e "$FAKE/curl.fail" ] && { cat "$FAKE/curl.fail"; exit 22; }\nwhile [ $# -gt 1 ]; do [ "$1" = -o ] && o=$2; shift; done\ncase $1 in *.sha256) cp "$FAKE/srv.sha256" "$o" ;; *) cp "$FAKE/srv.tar.gz" "$o" ;; esac\n' > "$T/bin/curl"
printf '#!/bin/sh\necho "$*" >> "$FAKE/gh.args"\nwhile [ $# -gt 0 ]; do [ "$1" = -D ] && d=$2; shift; done\ncp "$FAKE/srv.tar.gz" "$d/%s"; cp "$FAKE/srv.sha256" "$d/%s.sha256"\n' "$A" "$A" > "$T/bin/gh"
chmod +x "$T/bin/uname" "$T/bin/curl" "$T/bin/gh"
tw() { PATH=$T/bin:$PATH HOME=$T/home FAKE=$T SHELL=${TSH:-/bin/zsh} "${SH:-sh}" "$CW" tui; }
out=$(tw 2>&1) || fail "cw tui: $out"
grep -qF "https://github.com/DozenTwelve/CWTFIGO/releases/download/tui-v$V/$A" "$T/curl.args" || fail "cw tui should fetch tui-v$V's $A: $(cat "$T/curl.args")"
grep -q latest "$T/curl.args" && fail "cw tui must never fetch latest"
[ -x "$T/home/.local/bin/cwtfigo" ] && [ "$("$T/home/.local/bin/cwtfigo")" = new ] || fail "cw tui should install an executable cwtfigo"
echo "$out" | grep -qx "cwtfigo $V installed in ~/.local/bin" || fail "cw tui should say what it installed: $out"
echo "$out" | grep -q "isn't on PATH.*zshrc" || fail "cw tui should say ~/.local/bin isn't on PATH: $out"
out=$(PATH=$T/home/.local/bin:$PATH tw 2>&1); echo "$out" | grep -q "isn't on PATH" && fail "cw tui on PATH says nothing about it: $out"
# The owner's own shell's rc file, no Mac advice on Linux; another cwtfigo first on PATH is named, not "isn't on PATH".
out=$(TSH=/bin/bash tw 2>&1); echo "$out" | grep -q "isn't on PATH: add export PATH=.* to ~/.bashrc, then" && ! echo "$out" | grep -q Mac || fail "cw tui on Linux bash: $out"
out=$(TSH=/usr/bin/fish tw 2>&1); echo "$out" | grep -q "fish_add_path ~/.local/bin" || fail "cw tui on fish: $out"
mkdir "$T/other"; cp "$T/pkg/cwtfigo" "$T/other/"; chmod +x "$T/other/cwtfigo"
out=$(PATH=$T/other:$T/home/.local/bin:$PATH tw 2>&1); echo "$out" | grep -q "another cwtfigo comes first on PATH, $T/other/cwtfigo" && ! echo "$out" | grep -q "isn't on PATH" || fail "cw tui behind another cwtfigo: $out"
# A link to a clone's own build stays a link: cw tui refuses and says to rebuild.
mkdir "$T/build"; ln -sf "$T/build/cwtfigo-tui" "$T/home/.local/bin/cwtfigo"
out=$(tw 2>&1) && fail "cw tui should refuse to replace a link to an own build"
echo "$out" | grep -q 'link to your own build.*cargo build --release' && [ -L "$T/home/.local/bin/cwtfigo" ] || fail "cw tui over a link: $out"
rm "$T/home/.local/bin/cwtfigo"
# A tarball that doesn't match its .sha256: nothing installed, the old binary left as it was, no temp file left.
echo old > "$T/home/.local/bin/cwtfigo"; echo "$(tsum "$T/pkg/LICENSE")  $A" > "$T/srv.sha256"
out=$(tw 2>&1) && fail "cw tui should refuse a tarball that doesn't match its .sha256"
echo "$out" | grep -q "doesn't match" || fail "a sha mismatch should say so: $out"
[ "$(cat "$T/home/.local/bin/cwtfigo")" = old ] && [ "$(ls -A "$T/home/.local/bin")" = cwtfigo ] || fail "a sha mismatch must leave ~/.local/bin as it was: $(ls -A "$T/home/.local/bin")"
echo "$(tsum "$T/srv.tar.gz")  $A" > "$T/srv.sha256"
grep -q -- '--connect-timeout [0-9]* --max-time [0-9]*' "$T/curl.args" || fail "cw tui's curl needs timeouts, a stalled download would hang the TUI's u: $(cat "$T/curl.args")"
# A 404 (right after a plugin update the release is still building): try again later, the old binary stays, no gh.
echo old > "$T/home/.local/bin/cwtfigo"; printf 404 > "$T/curl.fail"; out=$(tw 2>&1) && fail "cw tui should fail when curl does"
echo "$out" | grep -q "isn't ready to download yet.*Try again in 5 minutes" || fail "a 404 should say to try again later: $out"
[ "$(cat "$T/home/.local/bin/cwtfigo")" = old ] && [ ! -e "$T/gh.args" ] || fail "a failed download must leave the old binary and not try gh"
# No connection (no DNS, a timeout: curl's code 000) is not "not ready yet".
printf 000 > "$T/curl.fail"; out=$(tw 2>&1) && fail "cw tui should fail with no connection"
echo "$out" | grep -q "couldn't reach GitHub" && ! echo "$out" | grep -q "isn't ready" || fail "no connection should say so: $out"
[ "$(ls -A "$T/home/.local/bin")" = cwtfigo ] || fail "a failed download must leave no temp file: $(ls -A "$T/home/.local/bin")"
rm "$T/curl.fail"
# No curl at all: how to get it, before anything is fetched or created.
mkdir "$T/nc"; for c in dirname sed sha256sum shasum; do p=$(command -v $c) && ln -s "$p" "$T/nc/$c"; done; cp "$T/bin/uname" "$T/nc/"
out=$(PATH=$T/nc HOME=$T/home "$(command -v sh)" "$CW" tui 2>&1) && fail "cw tui without curl should fail"
echo "$out" | grep -q "doesn't have: install it (Debian/Ubuntu/Mint: sudo apt install curl;.*Arch: sudo pacman -S curl; a Mac has it)" || fail "cw tui without curl should say how to install it: $out"
touch "$T/curl.fail"
# Windows (Git Bash) has no build: one line, nothing fetched.
rm "$T/curl.args"; out=$(FAKE_OS=MINGW64_NT-10.0 tw 2>&1) && fail "cw tui should refuse Windows"
echo "$out" | grep -q "Mac and Linux only, there's no Windows build" && [ ! -e "$T/curl.args" ] || fail "cw tui on Windows: $out"
# A 32-bit Raspberry Pi: no build for its processor, said before any download.
out=$(FAKE_M=armv7l tw 2>&1) && fail "cw tui should refuse armv7l"
echo "$out" | grep -q 'no TUI build for this processor (armv7l)' && [ ! -e "$T/curl.args" ] || fail "cw tui on armv7l: $out"

# A machine's dir is its SSH alias. "local" means this machine, whose name is in self.
# Shared with other operator machines that know hosts: local asks what this machine is called there, in plain words.
mkdir -p "$CWTFIGO_HOME/hosts/nas"; git init -q "$CWTFIGO_HOME"; git -C "$CWTFIGO_HOME" remote add origin "$CWTFIGO_HOME/none.git"
out=$(sh "$CW" run local collect 2>&1); [ $? = 1 ] || fail "local without a name, shared record with a host, should fail"
echo "$out" | grep -q 'cw name <name>' || fail "local without a name should ask for cw name"
echo "$out" | grep -q 'SSH alias' && fail "the name question in plain words: $out"
[ -f "$CWTFIGO_HOME/self" ] && fail "no automatic name once the record is shared and has a host"
git -C "$CWTFIGO_HOME" remote remove origin; rm -r "$CWTFIGO_HOME/hosts/nas"
# Alone in the record: local takes the hostname, made a valid name: uname -n up to its domain (stock Arch has no
# hostname command), a Mac's LocalHostName first.
N=$(mktemp -d); printf '#!/bin/sh\nexit 127\n' > "$N/hostname"; printf '#!/bin/sh\nexit 1\n' > "$N/scutil"; printf '#!/bin/sh\n' > "$N/xcode-select"
printf '#!/bin/sh\ncase $1 in -n) echo "${FAKE_N:-My_Box-2.lan}" ;; *) echo "${FAKE_OS:-Linux}" ;; esac\n' > "$N/uname"; chmod +x "$N"/*
out=$(PATH=$N:$PATH FAKE_OS=Darwin FAKE_N=MacBook-Air.local CWTFIGO_HOME=$N/rec sh "$CW" run local collect 2>&1); [ $? = 3 ] && grep -qx macbook-air "$N/rec/self" || fail "a Mac with no LocalHostName: $out"
# Not shared, its only host so far a remote one: still one operator, named the same way. Never another host's name.
mkdir -p "$N/r2/hosts/nas"; out=$(PATH=$N:$PATH CWTFIGO_HOME=$N/r2 sh "$CW" run local collect 2>&1); [ $? = 3 ] && grep -qx mybox-2 "$N/r2/self" || fail "a record with only a remote host, not shared, should name this machine: $out"
mkdir -p "$N/r3/hosts/nas"; out=$(PATH=$N:$PATH FAKE_N=nas CWTFIGO_HOME=$N/r3 sh "$CW" run local collect 2>&1); [ $? = 1 ] && [ ! -e "$N/r3/self" ] || fail "this machine must not take another host's name: $out"
echo "$out" | grep -q 'already called nas.*cw name <name>' || fail "a hostname another host has should ask for a name: $out"
out=$(PATH=$N:$PATH sh "$CW" run local collect 2>&1); [ $? = 3 ] || fail "local alone in the record should name itself and go on: $out"
grep -qx mybox-2 "$CWTFIGO_HOME/self" || fail "automatic name: $(cat "$CWTFIGO_HOME/self")"
echo "$out" | grep -q 'called mybox-2 in the record.*cw name' || fail "automatic name should be said: $out"
[ -d "$CWTFIGO_HOME/hosts/local" ] && fail "hosts/local must never be created"
# Stopped at approval (the owner said no, or left): no host dir, so no machine row, and the owner is still new.
[ -e "$CWTFIGO_HOME/hosts/mybox-2" ] && fail "a run that stops before approval must leave no host dir"
sh "$CW" status 2>&1 >/dev/null | grep -q '^hint: this record is new' || fail "a run that stopped before approval: the owner is still new"
mkdir "$CWTFIGO_HOME/hosts/mybox-2"; touch "$CWTFIGO_HOME/hosts/mybox-2/approved.sha256"
for n in '' local a/b 'a b'; do sh "$CW" name "$n" >/dev/null 2>&1 && fail "cw name '$n' should be refused"; done
mkdir "$CWTFIGO_HOME/hosts/nas"; sh "$CW" name nas >/dev/null 2>&1 && fail "cw name onto an existing host dir should be refused"
rm -r "$CWTFIGO_HOME/hosts/nas"
sh "$CW" name box | grep -q box || fail "cw name should say the name"
grep -qx box "$CWTFIGO_HOME/self" || fail "self not written"
[ -f "$H/approved.sha256" ] && [ ! -e "$CWTFIGO_HOME/hosts/mybox-2" ] || fail "cw name should rename this machine's dir"

out=$(sh "$CW" run local collect); [ $? = 3 ] || fail "unapproved collect should exit 3"
echo "$out" | grep -q '^Tell the human in one line what it reads or changes, then run cw approve box collect@[0-9a-f]\{12\} right away: the permission prompt they get is the question' || fail "never-approved script should ask for one line, not a diff, then approve right away: $out"
echo "$out" | grep -q '^# First-visit collector' && echo "$out" | grep -Eq '^full script: .*/collect\.(sh|ps1)$' || fail "plugin script: header and path: $out"
echo "$out" | grep -q 'exec 2>/dev/null' && fail "plugin script: header only, not the whole script"
[ -d "$CWTFIGO_HOME/.git" ] || fail "record not created"
sh "$CW" approve local collect >/dev/null
sh "$CW" run local collect >/dev/null || fail "approved collect should run"
grep -q '^id: ' "$H/facts.md" || fail "facts.md not written"

sed -i.bak 's/^id: .*/id: 0000000000000000/' "$H/facts.md"
sh "$CW" run local collect >/dev/null 2>&1; [ $? = 4 ] || fail "id mismatch should exit 4"
grep -q '^id: 0000' "$H/facts.md" || fail "mismatched facts.md overwritten"
rm "$H/facts.md.bak"

# Windows runs .ps1 through cw's PowerShell loader: args and exit code must survive it.
case $(uname -s) in MINGW*|MSYS*|CYGWIN*)
  grep -q '^id: e3b0c44298fc1c14' "$H/facts.md" && fail "Windows id is the hash of an empty string"
  printf '"[" + ($args -join "|") + "]"; exit 5\n' > "$H/args.ps1"
  sh "$CW" approve local args >/dev/null
  out=$(sh "$CW" run local args a b); [ $? = 5 ] || fail "ps1 exit code lost"
  [ "$out" = "[a|b]" ] || fail "ps1 args: got '$out'"
esac
LC_ALL=C grep -l '[^[:print:][:space:]]' "$(dirname "$CW")"/*.ps1 "$(dirname "$CW")"/probes/*.ps1 "$(dirname "$CW")"/../foundations/*/*.ps1 && fail "PowerShell 5.1 reads stdin in the system code page: keep .ps1 ASCII"
# Syntax only, and pwsh 7 parses some things 5.1 doesn't (??, ternary, && ||): those are kept out by hand.
if command -v pwsh >/dev/null; then
  # Git Bash doesn't convert paths inside environment variables for native programs: cygpath does.
  PS1S=$(ls "$(dirname "$CW")"/*.ps1 "$(dirname "$CW")"/probes/*.ps1 "$(dirname "$CW")"/../foundations/*/*.ps1 | { command -v cygpath >/dev/null && cygpath -w -f - || cat; }) pwsh -NoProfile -NonInteractive -Command '$bad = 0
    foreach ($f in $env:PS1S -split "`n") { $e = $null; $null = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$e); $e | ForEach-Object { "${f}: $_"; $bad = 1 } }
    exit $bad' || fail ".ps1 syntax error"
  # maintain.ps1's dry run against a fake winget (rows as winget prints them): held ids marked, ids found past names
  # with spaces and "< x" versions, a cut-off id not upgraded; choco's python meta packages held.
  W=$(mktemp -d)
  { printf '#!/bin/sh\n'; for l in 'Name                 Id                           Version  Available Source' \
      '------------------------------------------------------------------------' \
      'Epic Online Services EpicGames.EpicOnlineServices 2.0.44.0 4.3.1     winget' \
      'Git                  Git.Git                      2.47.0   2.51.0    winget' \
      'Visual Studio Code   Microsoft.VisualStudioCode   < 1.95   1.105.1   winget' \
      'Some Very Long Name  Vendor.SomeVeryLongPackag… 1.0      2.0       winget'; do printf "printf '%%s\\\\r\\\\n' '%s'\n" "$l"; done; } > "$W/winget"
  printf '#!/bin/sh\necho "python|3.12.0|3.15.0|false"; echo "git|2.47.0|2.51.0|false"\n' > "$W/choco"
  # The copy ends by listing $Error entries about a desktop path: the dry run must not look at the desktops at all.
  chmod +x "$W/winget" "$W/choco"; sed -e '/^# CWTFIGO-FOUNDATION/d' -e 's/^exit 0$/$Error | Where-Object { "$($_.TargetObject)" -like "*Desktop*" } | ForEach-Object { "desktop error: $_" }/' "$(dirname "$CW")/../foundations/windows/maintain.ps1" > "$W/m.ps1"
  out=$(PATH=$W:$PATH pwsh -NoProfile -NonInteractive -File "$W/m.ps1" 2>&1)
  echo "$out" | grep -q 'EpicOnlineServices .*winget$' || fail "maintain.ps1: Epic row should be upgraded: $out"
  echo "$out" | grep -q 'Git.Git .*winget \[held\]$' || fail "maintain.ps1: Git.Git should be held: $out"
  echo "$out" | grep -q 'VisualStudioCode .*winget \[held\]$' || fail "maintain.ps1: id before a '< x' version: $out"
  echo "$out" | grep -q 'Packag… .*\[id cut off' || fail "maintain.ps1: cut-off id should not be upgraded: $out"
  echo "$out" | grep -q '^  python 3.12.0 -> 3.15.0 \[held\]$' || fail "maintain.ps1: choco python should be held: $out"
  echo "$out" | grep -q '^  git 2.47.0 -> 2.51.0$' || fail "maintain.ps1: choco git should be upgraded: $out"
  grep -q 'choco upgrade all -y --except=' "$W/m.ps1" || fail "maintain.ps1: choco upgrade all must leave \$CHOCO_HOLD out"
  echo "$out" | grep -q '^desktop error' && fail "maintain.ps1: dry run lists desktop shortcuts: $out"
  # Removing the shortcuts upgrades add is opt-in: the word is known, the shipped UPDATE leaves it out.
  grep -q 'on \$UPDATE desktop' "$W/m.ps1" && ! grep -q "^\$UPDATE = .*desktop" "$W/m.ps1" || fail "maintain.ps1: desktop shortcuts should be opt-in"
  rm -rf "$W"
  T=$(mktemp -d)
  # space.ps1's walk: a link counts once, where it lives; an unreadable folder says so instead of 0.
  # chmod doesn't deny on NTFS: on Windows only sh tests/windows-manual.sh runs space.ps1.
  case $(uname -s) in MINGW*|MSYS*|CYGWIN*) ;; *)
    mkdir -p "$T/a/locked" "$T/b"; head -c 60000000 /dev/zero > "$T/a/f"; ln -s "$T/a" "$T/b/link"; chmod 000 "$T/a/locked"
    { sed -n '/^\$st = /,/^function file/p' "$(dirname "$CW")/probes/space.ps1"; echo "row a '$T/a'; row b '$T/b'; row locked '$T/a/locked'"; } > "$T/space.ps1"
    out=$(pwsh -NoProfile -NonInteractive -File "$T/space.ps1" 2>&1); chmod 755 "$T/a/locked"
    echo "$out" | grep -Eq '^a +0\.1G partial ' || fail "space.ps1: a folder with an unreadable subfolder should be partial: $out"
    echo "$out" | grep -Eq '^locked +unreadable ' || fail "space.ps1: an unreadable folder should say so: $out"
    echo "$out" | grep -q '^b ' && fail "space.ps1: a link was walked: $out" ;;
  esac
  # env.ps1 never prints a secret: hidden by name or by value, the rest shown.
  { grep -E '^(\$byname|\$byvalue) = |^function (ex|secret)\(' "$(dirname "$CW")/probes/env.ps1"; cat <<'EOF'
$hide = @{ OPENAI_API_KEY = 'x'; DB_PASSWORD = 'x'; GH = 'ghp_abcdefghijklmnopqrstu'; ANTHROPIC = 'sk-ant-abc'
  DATABASE_URL = 'postgres://u:p@db/x'; JWT = 'eyJhbGciOi.x.y'; RANDOM_X = 'AbCdEf0123456789AbCdEf0123' }
$show = @{ JAVA_HOME = 'C:\Program Files\Java\jdk-21'; PYTHONIOENCODING = 'utf-8'; GOPATH = '%USERPROFILE%\go'
  HTTPS_PROXY = 'http://proxy:8080'; ChocolateyLastPathUpdate = '134385134163149238' }
foreach ($k in $hide.Keys) { if (-not (secret $k $hide[$k])) { "leaks $k" } }
foreach ($k in $show.Keys) { if (secret $k $show[$k]) { "hides $k" } }
EOF
  } > "$T/env.ps1"
  out=$(pwsh -NoProfile -NonInteractive -File "$T/env.ps1" 2>&1); [ -z "$out" ] || fail "env.ps1 secrets: $out"
else echo "skipped: .ps1 syntax, maintain.ps1, space.ps1 and env.ps1 checks (no pwsh)"; fi

sh "$CW" run local maintain >/dev/null 2>&1; [ $? = 1 ] || fail "maintain without device.json should fail"
echo '{ "os": "macos" }' > "$H/device.json"
out=$(sh "$CW" run local maintain 2>&1); [ $? = 1 ] || fail "new maintain should be refused until adapted"
grep -q '^# CWTFIGO-FOUNDATION' "$H/maintain.sh" || fail "maintain.sh not copied from foundation"
[ "$(echo "$out" | wc -l)" -eq 1 ] && echo "$out" | grep -q 'adapt it' || fail "unadapted foundation: one line to adapt it, no script: $out"
echo "$out" | grep -q 'cw approve' && fail "unadapted foundation must not offer approval"
sh "$CW" save "unadapted" >/dev/null || fail "save with an unadapted foundation"
git -C "$CWTFIGO_HOME" ls-files | grep -qx 'hosts/box/maintain.sh' && fail "unadapted foundation must not be committed"
git -C "$CWTFIGO_HOME" ls-files | grep -q 'hosts/box/facts.md' || fail "save should still commit the rest"
sh "$CW" approve local maintain >/dev/null 2>&1 && fail "unadapted foundation must not be approved"
sed -i.bak '/^# CWTFIGO-FOUNDATION/d' "$H/maintain.sh"; rm "$H/maintain.sh.bak"
sh "$CW" approve local maintain >/dev/null || fail "adapted maintain should approve"
# Several scripts in one approve (one prompt): all or nothing, each refused as it would be alone.
A2=$(mktemp -d)/rec; aw() { CWTFIGO_HOME=$A2 sh "$CW" "$@"; }; aw name m >/dev/null; mkdir -p "$A2/hosts/m"
echo '{ "os": "arch" }' > "$A2/hosts/m/device.json"; echo 'echo a' > "$A2/hosts/m/a.sh"; echo 'echo b' > "$A2/hosts/m/b.sh"
aw run m check >/dev/null 2>&1   # copies the unadapted foundation
out=$(aw approve m a check 2>&1) && fail "approve with an unadapted check among them should fail"
echo "$out" | grep -q 'check on m is the unadapted foundation' && echo "$out" | grep -q 'approved none: refused check$' || fail "a refused approve should say which: $out"
out=$(aw approve m a nosuch b 2>&1) && fail "approve with a missing script among them should fail"
echo "$out" | grep -q 'approved none: refused nosuch$' || fail "a missing script should be named: $out"
[ -s "$A2/hosts/m/approved.sha256" ] && fail "a refused approve must approve none: $(cat "$A2/hosts/m/approved.sha256")"
aw approve m a probes >/dev/null 2>&1 && fail "probes is its own form, not mixed with names"
aw approve m probes a >/dev/null 2>&1 && fail "probes is its own form, not mixed with names, first either"
[ -s "$A2/hosts/m/approved.sha256" ] && fail "a mixed approve must approve none"
aw approve m a b | grep -qx 'approved: a b on m' || fail "approve a b should say both"
[ "$(cut -d' ' -f3 "$A2/hosts/m/approved.sha256" | tr '\n' ' ')" = 'a b ' ] || fail "approve a b: one line each: $(cat "$A2/hosts/m/approved.sha256")"
aw run m a >/dev/null && aw run m b >/dev/null || fail "both should run once approved together"
# device.json's os decides the script type: windows gets the .ps1 foundation, refused before it ever reaches PowerShell.
for os in arch debian openwrt windows; do
  x=sh; [ $os = windows ] && x=ps1
  A=$CWTFIGO_HOME/hosts/$os; mkdir -p "$A" && touch "$A/approved.sha256"; echo "{ \"os\": \"$os\" }" > "$A/device.json"
  for s in check maintain; do
    sh "$CW" run $os $s >/dev/null 2>&1; [ $? = 1 ] || fail "new $os $s should be refused until adapted"
    cmp -s "$A/$s.$x" "$(dirname "$CW")/../foundations/$os/$s.$x" || fail "$os $s.$x not copied from foundation"
    sh "$CW" approve $os $s >/dev/null 2>&1 && fail "unadapted $os $s must not be approved"
    sed -i.bak '/^# CWTFIGO-FOUNDATION/d' "$A/$s.$x"; rm "$A/$s.$x.bak"
    sh "$CW" approve $os $s >/dev/null || fail "adapted $os $s should approve"
  done
  rm -rf "$A"
done
# A copy records its foundation; once a plugin update changes that foundation, status hints. A temp copy of the
# skill and its own record: the real foundations/ stay as they are.
S=$(mktemp -d); mkdir "$S/s"; cp -R "$(dirname "$CW")" "$(dirname "$CW")/../foundations" "$S/s/"
st() { CWTFIGO_HOME=$S/rec sh "$S/s/scripts/cw" status 2>&1 >/dev/null | grep foundations/; }
A=$S/rec/hosts/arch; mkdir -p "$A" "$S/rec/hosts/old" && touch "$A/approved.sha256"; echo '{ "os": "arch" }' > "$A/device.json"
CWTFIGO_HOME=$S/rec sh "$S/s/scripts/cw" run arch check >/dev/null 2>&1
[ "$(cat "$A/check.sh.origin")" = "$(cd "$S/s" && { sha256sum foundations/arch/check.sh 2>/dev/null || shasum -a 256 foundations/arch/check.sh; })" ] ||
  fail "the copy should record its foundation: $(cat "$A/check.sh.origin")"
echo 'echo old' > "$S/rec/hosts/old/check.sh"   # copied before origins were recorded
out=$(st) && fail "no hint while the foundation is unchanged: $out"
echo '# a fix' >> "$S/s/foundations/arch/check.sh"
out=$(st) && fail "a copy not adapted yet has nothing to carry fixes into: no hint: $out"
sed -i.bak '/^# CWTFIGO-FOUNDATION/d' "$A/check.sh"; rm "$A/check.sh.bak"
out=$(st); [ "$(echo "$out" | wc -l)" -eq 1 ] && echo "$out" | grep -q "^hint: $S/s/foundations/arch/check.sh changed since $A/check.sh .*for arch\. Diff" ||
  fail "a changed foundation should hint once, for this host only: $out"
echo "$out" | sed 's/.*write the line "\(.*\)" to.*/\1/' > "$A/check.sh.origin"
out=$(st) && fail "no hint once the new origin is written: $out"
# device.json and .origin come from the shared record: neither may point cw outside foundations/.
mkdir -p "$S/home/.ssh"; echo secret > "$S/home/.ssh/id_test"; echo 'echo secret' > "$S/home/.ssh/check.sh"
echo x > "$A/a.sh"; echo '0  ../home/.ssh/id_test' > "$A/a.sh.origin"; echo x > "$A/b.sh"; echo '0  foundations/../../home/.ssh/check.sh' > "$A/b.sh.origin"
out=$(CWTFIGO_HOME=$S/rec sh "$S/s/scripts/cw" status 2>&1 >/dev/null); echo "$out" | grep -q '\.ssh' && fail "an .origin outside foundations/ should be ignored: $out"
T=$S/rec/hosts/trav; mkdir -p "$T"; echo '{ "os": "../../home/.ssh" }' > "$T/device.json"
CWTFIGO_HOME=$S/rec sh "$S/s/scripts/cw" run trav check >/dev/null 2>&1; [ $? = 1 ] && [ ! -e "$T/check.sh" ] || fail "an os with a path in it should copy nothing: $(cat "$T/check.sh" 2>&1)"
# A Debian derivative without a foundation of its own gets debian's; an os with neither still says to write one.
U=$(mktemp -d)/rec; A=$U/hosts/ub; mkdir -p "$A" && touch "$A/approved.sha256"; echo '{ "os": "ubuntu" }' > "$A/device.json"
CWTFIGO_HOME=$U sh "$CW" run ub check >/dev/null 2>&1; [ $? = 1 ] || fail "new ubuntu check should be refused until adapted"
cmp -s "$A/check.sh" "$(dirname "$CW")/../foundations/debian/check.sh" || fail "ubuntu should get the debian foundation"
grep -q '  foundations/debian/check.sh$' "$A/check.sh.origin" || fail "ubuntu's origin should name the debian foundation: $(cat "$A/check.sh.origin")"
echo '{ "os": "fedora" }' > "$A/device.json"
out=$(CWTFIGO_HOME=$U sh "$CW" run ub maintain 2>&1); [ $? = 1 ] || fail "an os without a foundation should fail"
echo "$out" | grep -q "no fedora foundation for maintain.sh: write .*/hosts/ub/maintain.sh for this host" || fail "no foundation: $out"
[ -e "$A/maintain.sh" ] && fail "no foundation: nothing should be copied"
# What cw sends a Windows host (local goes the same way): the number of args, one arg per line, the script, then the
# end marker on a line of its own, even when the script's last line has no newline. With pwsh, the loader runs it and
# stops at the marker, not at EOF. An arg with a space arrives whole; one with a newline can't be sent.
A=$CWTFIGO_HOME/hosts/win; mkdir -p "$A" && touch "$A/approved.sha256"; echo '{ "os": "windows" }' > "$A/device.json"
W=$(mktemp -d); printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s/args"; cat > "%s/in"\n' "$W" "$W" > "$W/ssh"; chmod +x "$W/ssh"
eval "$(grep -E '^(PSLOAD|PSRUN)=' "$CW")"
for nl in '\n' ''; do
  printf "\"[\" + (\$args -join \"|\") + \"]\"; exit 5$nl" > "$A/args.ps1"
  sh "$CW" approve win args >/dev/null
  PATH=$W:$PATH sh "$CW" run win args 'a b' "it's" '$(x)' >/dev/null 2>&1
  grep -qx -- -Command "$W/args" && ! grep -q EncodedCommand "$W/args" || fail "cw should start PowerShell with -Command: $(cat "$W/args")"
  [ "$(head -n 4 "$W/in")" = "$(printf '3\na b\nit'"'"'s\n$(x)')" ] && [ "$(tail -n 1 "$W/in")" = '#CWTFIGO-END' ] || fail "cw should send args, script, #CWTFIGO-END: $(cat "$W/in")"
  if command -v pwsh >/dev/null; then
    out=$({ cat "$W/in"; echo '}'; } | pwsh -NoProfile -NonInteractive -Command "$PSRUN"); [ $? = 5 ] || fail "loader: exit code lost or read past the marker"
    [ "$out" = "[a b|it's|\$(x)]" ] || fail "loader args: got '$out'"
  fi
done
# Errors and Write-Host come back as text, not #< CLIXML (what -EncodedCommand makes of them).
if command -v pwsh >/dev/null; then
  err=$(printf '0\nWrite-Error oops\nWrite-Host hi\nexit 2\n#CWTFIGO-END\n' | pwsh -NoProfile -NonInteractive -Command "$PSRUN" 2>&1 >/dev/null); [ $? = 2 ] || fail "loader: exit code lost after an error"
  case $err in *CLIXML*|*'<Objs'*) fail "loader: stderr is CLIXML: $err" ;; *oops*) ;; *) fail "loader: error text lost: $err" ;; esac
  # $script: is the script's own top level, as when a .ps1 file runs; the loader's variables are gone.
  out=$(printf '0\n$n = 0\nfunction f { $script:n++ }\nf; f\n"$n $b"\n#CWTFIGO-END\n' | pwsh -NoProfile -NonInteractive -Command "$PSRUN")
  [ "$out" = "2 " ] || fail "loader: \$script: scope or a leftover loader variable: got '$out'"
  # An exit right after a table: the table still in the formatter must come out, and the exit code with it.
  out=$(printf '0\n[pscustomobject]@{ k = "tbl" } | Select k\n"after"\nexit 6\n#CWTFIGO-END\n' | pwsh -NoProfile -NonInteractive -Command "$PSRUN"); [ $? = 6 ] || fail "loader: exit code lost after a table"
  case $out in *tbl*after*) ;; *) fail "loader: output before exit lost: got '$out'" ;; esac
else echo "skipped: PowerShell loader checks (no pwsh)"; fi
# Before device.json, cw asks the host's shell whether it is Windows: no password prompt, no hang on a dead host.
mkdir "$W/p"; printf '#!/bin/sh\necho "$*" >> "%s/probe"; echo "newbox: Permission denied (publickey)." >&2; exit 255\n' "$W" > "$W/p/ssh"; chmod +x "$W/p/ssh"
out=$(PATH=$W/p:$PATH sh "$CW" run newbox collect </dev/null 2>&1)
echo "$out" | grep -q "can't reach newbox .*ssh said: newbox: Permission denied (publickey)\." || fail "can't reach should keep ssh's own reason (off, no such name or no key login): $out"
[ -e "$CWTFIGO_HOME/hosts/newbox" ] && fail "an unreachable host must leave no host dir (a machine row for good)"
case $out in *"can't reach newbox"*) ;; *) fail "an unreachable host must stop the run, not be taken for sh: $out" ;; esac
grep '%OS%' "$W/probe" | grep -q 'BatchMode=yes.*ConnectTimeout=' || fail "the Windows probe's ssh should use BatchMode and ConnectTimeout: $(cat "$W/probe")"
PATH=$W:$PATH sh "$CW" run win args "$(printf 'a\nb')" >/dev/null 2>&1; [ $? = 1 ] || fail "a ps1 arg with a newline should be refused"
# PowerShell's ReadLine splits at \r too: an arg holding one would end early and its rest run as code.
rm -f "$W/in"; PATH=$W:$PATH sh "$CW" run win args "$(printf 'x\rWrite-Output INJECTED')" >/dev/null 2>&1; [ $? = 1 ] || fail "a ps1 arg with a CR should be refused"
[ -e "$W/in" ] && fail "a refused ps1 arg should send nothing: $(cat "$W/in")"
rm -rf "$A" "$W"
# Over ssh the args are one string the remote shell parses again: each must arrive as it was, nothing in it run.
# The ssh here does what sshd does: joins its args with spaces and hands them to sh -c.
A=$CWTFIGO_HOME/hosts/nas; mkdir -p "$A" && touch "$A/approved.sha256"; echo '{ "os": "arch" }' > "$A/device.json"
W=$(mktemp -d); printf '#!/bin/sh\nwhile :; do case $1 in -o) shift 2 ;; -*) shift ;; *) break ;; esac; done\nshift; echo "$*" >> "%s/cmds"; exec sh -c "$*"\n' "$W" > "$W/ssh"; chmod +x "$W/ssh"
printf 'printf "[%%s]" "$@"\n' > "$A/c.sh"; sh "$CW" approve nas c >/dev/null
out=$(PATH=$W:$PATH sh "$CW" run nas c 'a b' "it's" '$(echo INJECTED)' '' </dev/null 2>&1)
[ "$out" = "[a b][it's][\$(echo INJECTED)][]" ] || fail "ssh args: got '$out'"
# The target's login shell may quote otherwise (fish: \' in '' is an escape): no arg goes into ssh's command at all.
grep -Eq "INJECTED|it's|a b" "$W/cmds" && fail "args must reach the target's sh only, not its login shell: $(cat "$W/cmds")"
PATH=$W:$PATH sh "$CW" run nas c "$(printf 'a\rb')" </dev/null >/dev/null 2>&1; [ $? = 1 ] || fail "an sh arg with a CR should be refused too"
# Off later on (device.json known, so no first-run check): cw says so, not only ssh's own line.
mkdir "$W/off"; printf '#!/bin/sh\necho "ssh: connect to host nas port 22: Operation timed out" >&2; exit 255\n' > "$W/off/ssh"; chmod +x "$W/off/ssh"
out=$(PATH=$W/off:$PATH sh "$CW" run nas c </dev/null 2>&1); [ $? = 255 ] && echo "$out" | grep -q "^cw: can't reach nas over ssh" || fail "an unreachable known host should say so, exit 255: $out"
# With a terminal (sudo may prompt) cw copies the script over and runs it with ssh -t. script(1) gives it one.
printf 'PATH=%s:$PATH sh "%s" run nas c "a b" "it'"'"'s" '"'"'$(echo INJECTED)'"'"' ""\n' "$W" "$CW" > "$W/t.sh"
if [ "$(uname -s)" = Darwin ]; then out=$(script -q /dev/null sh "$W/t.sh" </dev/null 2>&1)
elif command -v script >/dev/null; then out=$(script -qec "sh $W/t.sh" /dev/null </dev/null 2>&1); else out=skip; echo "skipped: ssh -t args (no script)"; fi
# macOS script(1) echoes the ^D it sends at EOF ahead of the output.
case $(printf %s "$out" | tr -d '\r') in skip|*"[a b][it's][\$(echo INJECTED)][]") ;; *) fail "ssh -t args: got '$out'" ;; esac
grep -Eq "INJECTED|it's|a b" "$W/cmds" && fail "ssh -t: args must reach the target's sh only: $(cat "$W/cmds")"
rm -rf "$A" "$W"
# A dying caller (a timed-out tool, a closed terminal) may signal cw alone: its ssh must not live on, orphaned.
W=$(mktemp -d); printf '#!/bin/sh\necho $$ > "%s/pid"; cat >/dev/null; exec sleep 30\n' "$W" > "$W/ssh"; chmod +x "$W/ssh"
for os in arch windows; do
  A=$CWTFIGO_HOME/hosts/$os; mkdir -p "$A" && touch "$A/approved.sha256"; echo "{ \"os\": \"$os\" }" > "$A/device.json"
  x=sh; [ $os = windows ] && x=ps1; echo 'echo hi' > "$A/nap.$x"; sh "$CW" approve $os nap >/dev/null
  PATH=$W:$PATH sh "$CW" run $os nap </dev/null >/dev/null 2>&1 & c=$!
  i=0; until [ -s "$W/pid" ] || [ $i = 50 ]; do sleep 0.1; i=$((i + 1)); done; sleep 0.3
  kill $c; wait $c; sleep 0.3; p=$(cat "$W/pid"); rm -f "$W/pid"
  kill -0 "$p" 2>/dev/null && { kill "$p"; fail "$os: ssh outlived a killed cw run"; }
  rm -rf "$A"
done
rm -rf "$W"
for f in "$(dirname "$CW")"/probes/*.sh "$(dirname "$CW")"/../foundations/*/*.sh; do sh -n "$f" || fail "syntax: $f"; done
# OpenWrt: BusyBox applets only on PATH (no ss, lsof, systemctl, journalctl).
BB=$(mktemp -d); mkdir "$BB/bin"; SH=$(command -v sh)
for c in awk sed grep sort uniq head tail cut ls tr cat; do ln -s "$(command -v $c)" "$BB/bin/$c"; done
cat > "$BB/bin/ip" <<'EOF'
#!/bin/sh
case $1 in -br) echo 'ip: invalid option -- b' >&2; exit 1 ;; esac
printf '1: lo    inet 127.0.0.1/8 scope host lo\\       valid_lft forever\n'
printf '2: eth0: <BROADCAST,UP> mtu 1500 qdisc mq \\    link/ether aa:bb:cc:dd:ee:ff\n'
printf '5: br-lan    inet 192.168.1.1/24 brd 192.168.1.255 scope global br-lan\\       valid_lft forever\n'
EOF
chmod +x "$BB/bin/ip"
bb() { PATH=$BB/bin "$SH" "$(dirname "$CW")/probes/$1.sh"; }
out=$(bb net)
echo "$out" | grep -qx 'br-lan 192.168.1.1/24' || fail "net on BusyBox: addresses from ip -o when ip -br fails: $out"
echo "$out" | grep -q 'link/ether' && fail "net on BusyBox: ip -o link lines are not addresses: $out"
cat > "$BB/bin/netstat" <<'EOF'
#!/bin/sh
case $1 in
--help) echo 'BusyBox v1.36.1 multi-call binary.' >&2 ;;
-tulnp) printf 'Active Internet connections (only servers)\nProto Recv-Q Send-Q Local Address  Foreign Address  State  PID/Program name\n'
  printf 'tcp 0 0 0.0.0.0:22 0.0.0.0:* LISTEN 1200/dropbear\nudp 0 0 0.0.0.0:53 0.0.0.0:* 2345/dnsmasq\n' ;;
*) exit 1 ;;
esac
EOF
chmod +x "$BB/bin/netstat"
out=$(bb net)
echo "$out" | grep -qx 'tcp 0.0.0.0:22 1200/dropbear' && echo "$out" | grep -qx 'udp 0.0.0.0:53 2345/dnsmasq' || fail "net on BusyBox: listening from netstat -tulnp, with programs and UDP: $out"
# procd: enabled means an S link in /etc/rc.d (the probe's /etc pointed at a fake one).
mkdir -p "$BB/etc/rc.d"; touch "$BB/etc/rc.d/S19dnsmasq" "$BB/etc/rc.d/K10dropbear" "$BB/etc/rc.d/S50uhttpd"
sed "s|/etc/|$BB/etc/|g" "$(dirname "$CW")/probes/net.sh" > "$BB/net.sh"
out=$(PATH=$BB/bin "$SH" "$BB/net.sh" | sed -n '/^## services/,$p')
echo "$out" | grep -qx dnsmasq && echo "$out" | grep -qx uhttpd || fail "net on OpenWrt: services enabled in /etc/rc.d: $out"
echo "$out" | grep -q dropbear && fail "net on OpenWrt: a K link alone is not enabled: $out"
# logread: one daemon spamming errors must not hide the others.
printf '#!/bin/sh\necho Linux\n' > "$BB/bin/uname"; printf '#!/bin/sh\ncat %s/log\n' "$BB" > "$BB/bin/logread"; chmod +x "$BB/bin/uname" "$BB/bin/logread"
{ echo 'Sat Nov  7 09:00:00 2026 daemon.err odhcpd[1500]: Failed to send to ff02::1%br-lan'
  i=0; while [ $i -lt 30 ]; do echo "Sat Nov  7 10:00:00 2026 daemon.err noisyd[42]: error $i"; i=$((i + 1)); done
  echo 'Sat Nov  7 10:01:00 2026 kern.err kernel: [  12.3] usb 1-1: device descriptor read error'; } > "$BB/log"
out=$(bb logs)
echo "$out" | grep -Eqx ' *30 noisyd' && echo "$out" | grep -Eqx ' *1 odhcpd' && echo "$out" | grep -Eqx ' *1 kernel' || fail "logs on OpenWrt: logread errors counted per daemon: $out"
echo "$out" | grep -A11 '^## errors, last 10 (logread)' | grep -q 'kernel: \[  12.3\]' || fail "logs on OpenWrt: a short tail after the counts: $out"
printf 'echo host-health\n' > "$H/health.sh"
out=$(sh "$CW" run local health); [ $? = 3 ] || fail "unapproved host health.sh should exit 3"
echo "$out" | grep -qx 'echo host-health' || fail "host script should win over the probe of the same name"
rm "$H/health.sh"
# Every read-only probe at once, each by its own hash: not smart (sudo), not one a host script replaces.
printf 'echo host-perf\n' > "$H/perf.sh"
sh "$CW" approve local probes | grep -q '^approved on box: apps ' || fail "approve probes should list them"
sh "$CW" approve local probes >/dev/null
P=$(ls "$(dirname "$CW")"/probes/*.sh | wc -l)
[ "$(grep -cvE '  (collect|maintain|args)  ' "$H/approved.sha256")" = $(( P - 2 )) ] || fail "probes: one line per probe, once: $(cat "$H/approved.sha256")"
grep -q '  smart  ' "$H/approved.sha256" && fail "approve probes must leave out smart"
grep -q '  perf  ' "$H/approved.sha256" && fail "approve probes must leave out a probe the host script replaces"
sh "$CW" run local smart >/dev/null; [ $? = 3 ] || fail "smart should still ask"
sh "$CW" run local perf | grep -qx 'echo host-perf' || fail "host perf.sh should still ask, in full"
rm "$H/perf.sh"
# A plugin script is one the plugin ships, not any file under its dir: a new file in probes/ or a path through
# scripts/../.. is shown in full, and approve probes leaves it out. The list in cw is the probes dir.
[ "$(sed -n 's/^PROBES=" \(.*\) "$/\1/p' "$CW")" = "$(cd "$(dirname "$CW")/probes" && LC_ALL=C ls | tr '\n' ' ' | sed 's/ $//')" ] || fail "PROBES in cw should list scripts/probes/"
PC=$(mktemp -d); cp -R "$(dirname "$CW")/.." "$PC/cwtfigo"; printf '# Reads uptime.\necho new-probe-body\n' > "$PC/cwtfigo/scripts/probes/zz.sh"
sh "$PC/cwtfigo/scripts/cw" approve local probes | grep -q ' zz' && fail "approve probes must leave out a probe the plugin didn't ship"
out=$(sh "$PC/cwtfigo/scripts/cw" run local zz); [ $? = 3 ] && echo "$out" | grep -qx 'echo new-probe-body' || fail "a probe the plugin didn't ship should be shown in full: $out"
# A name with a space matches two list entries at once ("apps.sh boot.sh"): not a plugin probe either.
printf '# Reads uptime.\ntouch "%s/ran"\n' "$PC" > "$PC/cwtfigo/scripts/probes/apps.sh boot.sh"
sh "$PC/cwtfigo/scripts/cw" approve local probes | grep -q 'apps.sh boot' && fail "approve probes must leave out a probe name with a space"
out=$(sh "$PC/cwtfigo/scripts/cw" run local "apps.sh boot"); [ $? = 3 ] && echo "$out" | grep -q '^touch ' || fail "a probe name with a space should be shown in full: $out"
[ -e "$PC/ran" ] && fail "a probe name with a space ran unapproved"
printf '# Reads uptime.\necho outside-body\n' > "$PC/evil.sh"
sh "$CW" run local "$PC/cwtfigo/scripts/../../evil.sh" >/dev/null 2>&1; [ $? = 1 ] || fail "a path with .. should be refused"
sh "$CW" approve local "$PC/cwtfigo/scripts/../../evil.sh" >/dev/null 2>&1 && fail "approving a path with .. should be refused"
sh "$CW" run local ../box/maintain >/dev/null 2>&1; [ $? = 1 ] || fail "a script name with .. should be refused"
# A path outside the host's dir and the plugin's scripts (a key, a .env) is refused: not printed, never run.
printf 'SECRET-KEY-MATERIAL\n' > "$PC/id_ed25519"
out=$(sh "$CW" run local "$PC/id_ed25519" 2>&1); [ $? = 1 ] || fail "a path outside should be refused: $out"
echo "$out" | grep -q SECRET && fail "a file outside the record and the plugin must not be printed: $out"
echo "$out" | grep -q "isn't one of box's own scripts" || fail "a path outside should say why it's refused: $out"
# A bare name that is no script of the host's or the plugin's, but a file in the shell's current dir: refused, under
# YOLO too, so it is neither run nor approved unseen. Nor approved by name.
printf 'touch "%s/ran"\n' "$PC" > "$PC/cwd"; cp "$H/approved.sha256" "$PC/before"
sh "$CW" yolo >/dev/null; (cd "$PC" && sh "$CW" run local cwd >/dev/null 2>&1); r=$?; sh "$CW" yolo off >/dev/null
[ $r = 1 ] && [ ! -e "$PC/ran" ] && cmp -s "$H/approved.sha256" "$PC/before" || fail "a file in the current dir must not run under YOLO, nor be approved: rc $r"
(cd "$PC" && sh "$CW" approve local cwd >/dev/null 2>&1) && fail "approving a file in the current dir should be refused"
sh "$CW" approve local "$PC/cwd" >/dev/null 2>&1 && fail "approving a path outside should be refused"
cmp -s "$H/approved.sha256" "$PC/before" || fail "a refused approval must write nothing"
rm -rf "$PC"
sh "$CW" save "test" >/dev/null || fail "save"
echo "# don't touch X" >> "$H/maintain.sh"
out=$(sh "$CW" run local maintain); [ $? = 3 ] || fail "edited maintain should exit 3"
echo "$out" | grep -q "changed since it was last approved" || fail "should say the script changed"
echo "$out" | grep -q "^Show the human what changed, then run cw approve box maintain@[0-9a-f]\{12\} right away" || fail "changed script should ask to show the diff, then approve right away: $out"
echo "$out" | grep -q "^+# don't touch X" || fail "edit should be shown as a diff"
# approve with the hash start run printed: refused, approving nothing, when the file changed since run showed it.
a=$(echo "$out" | sed -n 's/.*then run cw approve box \(maintain@[0-9a-f]*\) right away.*/\1/p'); [ -n "$a" ] || fail "no maintain@<sha> in: $out"
cp "$H/maintain.sh" "$H/maintain.shown"; echo "# changed after run showed it" >> "$H/maintain.sh"
out=$(sh "$CW" approve local "$a" 2>&1) && fail "approve of a script changed since run showed it should be refused"
echo "$out" | grep -q 'maintain changed since cw run showed it' || fail "approve should say the script changed since run: $out"
sh "$CW" run local maintain >/dev/null; [ $? = 3 ] || fail "a refused approve must approve nothing"
mv "$H/maintain.shown" "$H/maintain.sh"
sh "$CW" approve local maintain@zzzzzzzzzzzz >/dev/null 2>&1 && fail "approve with a wrong sha256 start should be refused"
sh "$CW" approve local "$(echo "$a" | cut -c1-15)" >/dev/null 2>&1 && fail "approve with a sha256 start under 8 should be refused"
sh "$CW" approve local "$a" >/dev/null || fail "approve with the sha256 start run printed"
sh "$CW" run local maintain >/dev/null || fail "maintain approved by its sha256 start should run"

sh "$CW" status 2>/dev/null | grep -q '^  box (this machine) .*macos.*  0 open$' || fail "status should list and mark this machine"
sh "$CW" status 2>/dev/null | grep -qx '  Another machine? Tell me its SSH alias.' || fail "status should not offer local once this machine is in the record"
# Another operator machine on a newer plugin: status says so, in plain words. Versions compare as numbers. A copy of the
# plugin with a version of its own, and its own record.
PV=$(mktemp -d); mkdir -p "$PV/skills" "$PV/.claude-plugin"; cp -R "$(dirname "$CW")/.." "$PV/skills/cwtfigo"
pv() { echo "{ \"version\": \"$1\" }" > "$PV/.claude-plugin/plugin.json"; }
pc() { git -C "$PV/rec" -c user.name=t -c user.email=t@t commit -q --allow-empty -m x ${1:+-m "cw-version: $1"}; }
ps() { CWTFIGO_HOME=$PV/rec sh "$PV/skills/cwtfigo/scripts/cw" status 2>/dev/null | grep 'Another computer'; }
pv 0.5.9; CWTFIGO_HOME=$PV/rec sh "$PV/skills/cwtfigo/scripts/cw" status >/dev/null 2>&1; pc 0.5.9
out=$(ps) && fail "the same version should say nothing: $out"
pc 0.5.10; out=$(ps)
[ "$out" = "  Another computer uses CWTFIGO 0.5.10, this one 0.5.9. Update this one: claude plugin marketplace update cwtfigo && claude plugin update cwtfigo@cwtfigo, then restart Claude Code." ] || fail "a newer cw-version should show the update line: $out"
pc 0.5.9; pc; out=$(ps) && echo "$out" | grep -q ' 0\.5\.10, this one 0\.5\.9\.' || fail "the highest version of the last commits counts, not the newest commit's: $out"
pv 0.5.10; out=$(ps) && fail "an older cw-version (0.5.9 < 0.5.10) should say nothing: $out"
pv 0.6.0; pc '0.9.0; rm -rf x'; out=$(ps) && fail "a cw-version that isn't a version should be ignored: $out"
# Older than another computer's plugin: its foundations may be the older ones, so no hint to carry them into a copy.
A=$PV/rec/hosts/n; mkdir -p "$A"; echo 'echo x' > "$A/check.sh"; echo '0  foundations/arch/check.sh' > "$A/check.sh.origin"
ph() { CWTFIGO_HOME=$PV/rec sh "$PV/skills/cwtfigo/scripts/cw" status 2>&1 >/dev/null | grep -c 'foundations/arch/check.sh changed'; }
pv 0.5.9; [ "$(ph)" = 0 ] || fail "a plugin older than another computer's should not hint to carry its foundation over"
pv 0.5.10; [ "$(ph)" = 1 ] || fail "the same plugin as the others should still hint a changed foundation"
rm -rf "$PV"
# Columns line up whatever the os/version length: 'last visit' sits at one offset on every row.
mkdir -p "$CWTFIGO_HOME/hosts/pc"; printf '{"os": "windows", "version": "10 22H2 19045.7807 with a long tail"}\n' > "$CWTFIGO_HOME/hosts/pc/device.json"
offs=$(sh "$CW" status 2>/dev/null | awk '/last visit/ {print index($0, "last visit")}' | sort -u)
[ "$(echo "$offs" | wc -l)" -eq 1 ] && [ "$(sh "$CW" status 2>/dev/null | grep -c 'last visit')" -ge 2 ] || fail "status columns should align: offsets $offs"
rm -r "$CWTFIGO_HOME/hosts/pc"
# No git identity anywhere: save falls back to cwtfigo, a configured one wins.
I=$(mktemp -d)/rec; GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 CWTFIGO_HOME=$I sh "$CW" save x >/dev/null
touch "$I/a"; GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 CWTFIGO_HOME=$I sh "$CW" save a >/dev/null || fail "save without a git identity"
[ "$(git -C "$I" log -1 --format='%an <%ae>')" = 'cwtfigo <cwtfigo@localhost>' ] || fail "fallback identity: $(git -C "$I" log -1 --format='%an <%ae>')"
[ "$(git -C "$I" log -1 --format=%B)" = "$(printf 'a\n\ncw-version: %s' "$V")" ] || fail "save should add a cw-version trailer: $(git -C "$I" log -1 --format=%B)"
# Only user.email set: git takes the name from the account's full name. An account without one (GitHub's Ubuntu
# runner) can't commit then, and cw's ident() doesn't fill in the name: a cw bug, reported, not this check's.
if GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$I" -c user.email=me@x var GIT_AUTHOR_IDENT >/dev/null 2>&1; then
git -C "$I" config user.email me@x; touch "$I/b"; GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 CWTFIGO_HOME=$I sh "$CW" save b >/dev/null
[ "$(git -C "$I" log -1 --format=%ae)" = me@x ] || fail "a configured identity must not be overridden"
else echo "skipped: configured identity check (this account has no full name, so git has no name with only user.email set)"; fi
# A remote added by hand has no upstream: the first save sets it. A failed push says git's own error.
git init -q --bare "$I.git"; git -C "$I" remote add origin "$I.git"; touch "$I/c"
CWTFIGO_HOME=$I sh "$CW" save c >/dev/null 2>&1 || fail "first save to a new remote should push"
git -C "$I.git" cat-file -e "$(git -C "$I" rev-parse HEAD)" && [ "$(git -C "$I" rev-parse '@{upstream}' 2>/dev/null)" = "$(git -C "$I" rev-parse HEAD)" ] || fail "first save should push and set the upstream"
git -C "$I" remote set-url origin "$I.missing"; touch "$I/d"
out=$(CWTFIGO_HOME=$I sh "$CW" save d 2>&1) && fail "save to a missing remote should fail"
echo "$out" | grep -q "$I.missing" && echo "$out" | grep -q 'push failed' || fail "failed push should show git's error: $out"
printf '## Open items\n- a\n- b\n  - detail\n## Parked\n- 2026-10-31 c\n  - stone: x\n  - recheck: y\n## Gotchas\n- d\n' > "$H/notes.md"
sh "$CW" status 2>/dev/null | grep -q '^  box .*  2 open, 1 parked$' || fail "status should count open and parked issues"
printf '## Open items\n- (none)\n## Parked\n- 2026-10-31 c\n' > "$H/notes.md"
sh "$CW" status 2>/dev/null | grep -q '^  box .*  0 open, 1 parked$' || fail "a '- (none)' placeholder is not an open issue"
printf '## Open items\n- a\n- b\n  - detail\n## Parked\n- 2026-10-31 c\n  - stone: x\n  - recheck: y\n## Gotchas\n- d\n' > "$H/notes.md"
# Pull before a run must not trip over the visit's own uncommitted edits, even with pull.rebase=true.
P=$(mktemp -d); git init -q --bare "$P/r.git"; git -C "$CWTFIGO_HOME" add -A; git -C "$CWTFIGO_HOME" commit -qm pre
git -C "$CWTFIGO_HOME" remote add origin "$P/r.git"; git -C "$CWTFIGO_HOME" push -q -u origin HEAD 2>/dev/null
git clone -q "$P/r.git" "$P/other"; echo x > "$P/other/topology.md"; git -C "$P/other" add -A; git -C "$P/other" commit -qm other; git -C "$P/other" push -q 2>/dev/null
git -C "$CWTFIGO_HOME" config pull.rebase true; echo "# visit edit" >> "$H/notes.md"
out=$(sh "$CW" status 2>&1); echo "$out" | grep -q 'pull failed' && fail "pull with a dirty record should work: $out"
[ -f "$CWTFIGO_HOME/topology.md" ] || fail "other operator's commit should be pulled"
git -C "$CWTFIGO_HOME" remote remove origin; sed '$d' "$H/notes.md" > "$H/n" && mv "$H/n" "$H/notes.md"
# Two operator machines, one shared record. A stale record pulls before cw run resolves: a foundation copied first
# would sit untracked where the pull brings the other operator's adapted check, and every pull after would fail.
K=$(mktemp -d); kw() { r=$1; shift; HOME=$K PATH=$K/bin:$PATH CWTFIGO_HOME=$K/$r sh "$CW" "$@" </dev/null; }; kg() { r=$1; shift; HOME=$K git -C "$K/$r" "$@"; }
mkdir "$K/bin"; printf '#!/bin/sh\ncat >/dev/null; echo ran-on-nas\n' > "$K/bin/ssh"; chmod +x "$K/bin/ssh"; git init -q --bare "$K/s.git"
kw a name a >/dev/null; mkdir -p "$K/a/hosts/nas"; echo '{ "os": "arch" }' > "$K/a/hosts/nas/device.json"; touch "$K/a/hosts/nas/approved.sha256"
kg a remote add origin "$K/s.git"; kw a save init >/dev/null 2>&1 || fail "two operators: first save"
kw b join "$K/s.git" >/dev/null 2>&1; kw b name b >/dev/null; kw b run nas check >/dev/null 2>&1
sed -i.bak '/^# CWTFIGO-FOUNDATION/d' "$K/b/hosts/nas/check.sh"; rm "$K/b/hosts/nas/check.sh.bak"
kw b approve nas check >/dev/null; kw b save "adapted check" >/dev/null 2>&1 || fail "two operators: save the adapted check"
out=$(kw a run nas check 2>&1) && echo "$out" | grep -q ran-on-nas || fail "a stale record should pull before it resolves the script: $out"
[ "$(kg a rev-parse HEAD)" = "$(git -C "$K/s.git" rev-parse HEAD)" ] && [ -z "$(kg a status --porcelain)" ] || fail "the run should pull, and copy nothing: $(kg a status --porcelain)"
# Both push: the second save merges the other's commit and pushes once more, never rebasing or forcing.
echo '- b note' > "$K/b/topology.md"; kw b save "b note" >/dev/null 2>&1; echo '- a note' > "$K/a/operator.md"
out=$(kw a save "a note" 2>&1) || fail "save after another operator pushed should merge and push: $out"
[ "$(kg a rev-parse HEAD)" = "$(git -C "$K/s.git" rev-parse HEAD)" ] && [ -f "$K/a/topology.md" ] && kg a rev-parse -q --verify HEAD^2 >/dev/null || fail "save should merge the other's commit and push: $(kg a log --oneline -3)"
kg a log -1 --format=%B | grep -qx "cw-version: $V" || fail "the merge after a rejected push should carry the cw-version trailer: $(kg a log -1 --format=%B)"
# Both changed the same lines: stop with what to run, nothing pushed; that done, cw save shares the merge.
kg b pull -q --ff-only; echo '- from b' >> "$K/b/topology.md"; kw b save "from b" >/dev/null 2>&1; echo '- from a' >> "$K/a/topology.md"
out=$(kw a save "from a" 2>&1) && fail "a conflicting save should stop"
echo "$out" | grep -q 'same lines as this one: topology.md' && echo "$out" | grep -qF 'then: cw save "from a"' && echo "$out" | grep -q "git -C $K/a merge --abort" || fail "a conflicting save should say what to run: $out"
[ "$(git -C "$K/s.git" rev-parse HEAD)" = "$(kg b rev-parse HEAD)" ] || fail "a conflicting save must push nothing"
kw a save "from a" >/dev/null 2>&1 && fail "save must not commit a file still holding conflict lines"
printf '%s\n' '- b note' '- from b' '- from a' > "$K/a/topology.md"; kw a save "from a" >/dev/null 2>&1 || fail "save after resolving the conflict"
[ "$(kg a rev-parse HEAD)" = "$(git -C "$K/s.git" rev-parse HEAD)" ] && kg a rev-parse -q --verify HEAD^2 >/dev/null || fail "the resolved merge should be pushed"
# Files every operator appends to merge as a union: two saves that each added lines don't stop on a conflict.
kg b pull -q --ff-only
for r in a b; do echo "{\"query\":\"miss from $r\"}" >> "$K/$r/misses.jsonl"; echo "{\"source\":\"cwtfigo:nas/$r\"}" >> "$K/$r/hosts/nas/cases.jsonl"
  echo "echo $r" > "$K/$r/hosts/nas/$r.sh"; kw $r approve nas $r >/dev/null; done
kw a save "a appends" >/dev/null 2>&1 || fail "a appends: save"
out=$(kw b save "b appends" 2>&1) || fail "lines two operators appended should merge, not conflict: $out"
grep -q 'miss from a' "$K/b/misses.jsonl" && grep -q 'miss from b' "$K/b/misses.jsonl" && grep -q 'nas/a' "$K/b/hosts/nas/cases.jsonl" && grep -q 'nas/b' "$K/b/hosts/nas/cases.jsonl" &&
  grep -q '  a  ' "$K/b/hosts/nas/approved.sha256" && grep -q '  b  ' "$K/b/hosts/nas/approved.sha256" || fail "a union merge keeps both sides' lines"
rm -rf "$K"

# An approved script rewritten while it runs: what runs is what was approved. Past 8 KB, so dash reads the end late too.
{ printf 'echo start\nsleep 1\n'; awk 'BEGIN { for (i = 0; i < 200; i++) print "# padding padding padding padding padding" }'; } > "$H/race.sh"
cp "$H/race.sh" "$H/race.new"; echo 'echo approved-end' >> "$H/race.sh"; echo 'echo UNAPPROVED-RAN' >> "$H/race.new"
sh "$CW" approve local race >/dev/null; RO=$(mktemp)
sh "$CW" run local race > "$RO" 2>&1 & p=$!
sleep 0.5; cat "$H/race.new" > "$H/race.sh"; wait $p
grep -q UNAPPROVED "$RO" && fail "a script rewritten while it runs must not run the new code: $(cat "$RO")"
grep -q approved-end "$RO" || fail "the approved script should run to its end: $(cat "$RO")"
rm -f "$H/race.sh" "$H/race.new" "$RO"

# YOLO: the human's switch, one host or every machine, 12 h or until cw yolo off. Unapproved scripts print, get a yolo approval line, and run.
printf 'echo yolo-ran\n' > "$H/y.sh"
sh "$CW" run local y >/dev/null; [ $? = 3 ] || fail "unapproved script should exit 3 before yolo"
sh "$CW" yolo local | grep -q 'YOLO on for box' || fail "yolo should say it is on"
sh "$CW" status 2>/dev/null | grep -q '^  box .*  2 open, 1 parked  YOLO$' || fail "status should show YOLO"
sh "$CW" status 2>/dev/null | sed -n 9p | grep -qx '  YOLO is on for box, up to 12 h left: new scripts run without your OK\. .*' || fail "status's promise should say YOLO is on, and where"
out=$(sh "$CW" run local y) || fail "unapproved script should run under yolo"
echo "$out" | grep -q '^YOLO: running unapproved y on box' || fail "yolo run should say so"
echo "$out" | grep -q '^echo yolo-ran$' || fail "yolo run should still print the script"
echo "$out" | tail -1 | grep -qx yolo-ran || fail "yolo run should run the script"
grep -q "  y  .*  yolo$" "$H/approved.sha256" || fail "yolo approval line missing"
sh "$CW" run local y >/dev/null || fail "yolo-approved script should run after yolo"
echo '# CWTFIGO-FOUNDATION' > "$H/check.sh"
sh "$CW" run local check >/dev/null 2>&1; [ $? = 1 ] || fail "unadapted foundation must be refused under yolo"
grep -q '  check  ' "$H/approved.sha256" && fail "unadapted foundation approved under yolo"
rm "$H/check.sh"
sh "$CW" save "yolo test" >/dev/null || fail "save under yolo"
[ -f "$H/yolo.on" ] || fail "save should not end yolo: a visit saves many times"
sh "$CW" yolo off | grep -q 'YOLO off' || fail "yolo off should say so"
[ -f "$H/yolo.on" ] && fail "yolo off should end yolo"
printf 'echo all-ran\n' > "$H/a.sh"
sh "$CW" yolo | grep -q 'YOLO on for every machine' || fail "bare yolo should cover every machine"
sh "$CW" run local a | tail -1 | grep -qx all-ran || fail "unapproved script should run under yolo for every machine"
sh "$CW" status 2>/dev/null | grep -q '^  box .*YOLO$' || fail "status should show YOLO for every machine"
sh "$CW" status 2>/dev/null | sed -n 9p | grep -q '^  YOLO is on for every machine, up to 12 h left' || fail "status's promise should say YOLO is on for every machine"
sh "$CW" save "global yolo test" >/dev/null || fail "save under global yolo"
git -C "$CWTFIGO_HOME" log --all --name-only --format= | grep -q yolo.on && fail "yolo.on must never be committed"
sh "$CW" yolo off >/dev/null; [ -f "$CWTFIGO_HOME/yolo.on" ] && fail "yolo off should end yolo for every machine"
echo "$(( $(date +%s) - 13 * 3600 ))" > "$CWTFIGO_HOME/yolo.on"
echo "# edit" >> "$H/a.sh"
sh "$CW" run local a >/dev/null; [ $? = 3 ] || fail "stale global yolo flag should be ignored"
[ -f "$CWTFIGO_HOME/yolo.on" ] && fail "stale global yolo flag should be deleted"
echo "$(( $(date +%s) - 13 * 3600 ))" > "$H/yolo.on"
echo "# edit" >> "$H/y.sh"
sh "$CW" run local y >/dev/null; [ $? = 3 ] || fail "stale yolo flag should be ignored"
[ -f "$H/yolo.on" ] && fail "stale yolo flag should be deleted"
sh "$CW" status 2>/dev/null | grep -q YOLO && fail "status should not show a stale YOLO"
echo "$(( $(date +%s) + 3600 ))" > "$H/yolo.on"; echo "# edit" >> "$H/y.sh"
sh "$CW" run local y >/dev/null; [ $? = 3 ] || fail "a yolo flag from the future should be ignored: it would never expire"
[ -f "$H/yolo.on" ] && fail "a yolo flag from the future should be deleted"
# An alias is a dir name and an ssh argument: off/../.. would be the record itself, so YOLO for every machine.
# collect resolves for any host, so only the alias check can make the run exit 1; and no host dir may appear.
hb=$(ls -a "$CWTFIGO_HOME/hosts")
for a in off/../.. .. . -oProxyCommand=x 'a b' 'a\b' 'b*' 'b?x' 'b[x]'; do
  sh "$CW" yolo "$a" >/dev/null 2>&1 && fail "cw yolo '$a' should be refused"
  sh "$CW" run "$a" collect >/dev/null 2>&1; [ $? = 1 ] || fail "cw run '$a' should be refused"
done
[ "$(ls -a "$CWTFIGO_HOME/hosts")" = "$hb" ] || fail "a bad alias made a host dir: $(ls -a "$CWTFIGO_HOME/hosts")"
[ -e "$CWTFIGO_HOME/yolo.on" ] || [ -e "$CWTFIGO_HOME/approved.sha256" ] && fail "a bad alias reached the record's root"
for n in .. -x 'a\b' 'b*' 'b?x' 'b[x]'; do sh "$CW" name "$n" >/dev/null 2>&1 && fail "cw name '$n' should be refused"; done

git -C "$CWTFIGO_HOME" ls-files | grep -q '^self$' && fail "self must never be committed"
# Here, not over ssh (that ssh fails): the run has to get past approval to show which way it went.
sh "$CW" approve box y >/dev/null; W=$(mktemp -d); printf '#!/bin/sh\nexit 255\n' > "$W/ssh"; chmod +x "$W/ssh"
[ "$(PATH=$W:$PATH sh "$CW" run box y 2>&1)" = yolo-ran ] || fail "this machine's own name should run here like local"
rm -rf "$W"
[ -d "$CWTFIGO_HOME/hosts/local" ] && fail "hosts/local must never be created"

# Same machine under two names: collect refuses to save the second.
rm "$H/facts.md"; sh "$CW" approve local collect >/dev/null; sh "$CW" run local collect >/dev/null || fail "collect after removing facts.md"
T=$CWTFIGO_HOME/hosts/twin; mkdir -p "$T"; grep -m1 '^id: ' "$H/facts.md" > "$T/facts.md"
out=$(sh "$CW" run local collect 2>&1 >/dev/null); [ $? = 4 ] || fail "same id under another name should exit 4"
echo "$out" | grep -q 'already in the record as twin' || fail "should name the other host: $out"
rm -rf "$T"
# No machine-id, platform UUID or NIC: no id line, not the hash of an empty string every such box would share.
# Two of them in one record both collect (the ssh here runs the remote side locally).
Y=$(mktemp -d); mkdir -p "$Y/bin" "$Y/s"; cp -R "$(dirname "$CW")" "$Y/s/"; printf '#!/bin/sh\n' > "$Y/bin/ioreg"
printf '#!/bin/sh\nwhile :; do case $1 in -o) shift 2 ;; -*) shift ;; *) break ;; esac; done\nshift; exec sh -c "$*"\n' > "$Y/bin/ssh"; chmod +x "$Y/bin/ioreg" "$Y/bin/ssh"
sed -i.bak 's|/etc/machine-id|/nonexistent|; s|/sys/class/net|/nonexistent|' "$Y/s/scripts/collect.sh"
yw() { PATH=$Y/bin:$PATH CWTFIGO_HOME=$Y/rec sh "$Y/s/scripts/cw" "$@" </dev/null; }
yw name y1 >/dev/null; yw approve local collect >/dev/null; yw approve y2 collect >/dev/null
yw run local collect >/dev/null && yw run y2 collect >/dev/null || fail "two boxes without an id should both collect"
grep -q '^id:' "$Y/rec/hosts/y1/facts.md" "$Y/rec/hosts/y2/facts.md" && fail "no id source should print no id line: $(grep '^id:' "$Y/rec/hosts/"*/facts.md)"
grep -q '^hostname: ' "$Y/rec/hosts/y2/facts.md" || fail "collect without an id should still write facts"
rm -rf "$Y"

grep -qx 2 "$CWTFIGO_HOME/schema" || fail "schema file not written"
grep -q 'eol=lf' "$CWTFIGO_HOME/.gitattributes" || fail "record should keep LF on Windows operators"
echo 9 > "$CWTFIGO_HOME/schema"
sh "$CW" status >/dev/null 2>&1 && fail "newer record schema must be refused"
echo 2 > "$CWTFIGO_HOME/schema"

# hosts/ but no schema file and no name yet: it just runs, and the schema is written.
O=$(mktemp -d)/old; mkdir -p "$O/hosts/box" && git init -q "$O"
CWTFIGO_HOME=$O sh "$CW" status >/dev/null 2>&1 || fail "a record without a schema file should run"
grep -qx 2 "$O/schema" || fail "a record without a schema file should get schema 2"
echo box > "$O/self"
# cw name moves this machine's tracked dir with git mv; with no own dir yet it only writes self.
echo mine > "$O/hosts/box/facts.md"; git -C "$O" add hosts/box/facts.md && git -C "$O" -c user.name=t -c user.email=t@t commit -qm x
CWTFIGO_HOME=$O sh "$CW" name box2 >/dev/null || fail "cw name with a tracked own dir"
grep -qsx mine "$O/hosts/box2/facts.md" && [ ! -d "$O/hosts/box" ] || fail "cw name should move this machine's own dir"
git -C "$O" ls-files | grep -q '^hosts/box2/facts.md$' || fail "tracked files should be renamed with git mv"
rm -r "$O/hosts/box2"; CWTFIGO_HOME=$O sh "$CW" name box3 >/dev/null
grep -qx box3 "$O/self" && [ ! -d "$O/hosts/box3" ] || fail "cw name without an own dir should only write self"

mkdir -p "$CWTFIGO_HOME/archive"
cat > "$CWTFIGO_HOME/archive/archive.jsonl" <<'EOF'
{"source":"https://x/1","title":"Bar black after Qt 6.12","created":"2026-10-08","closed":"2026-10-08","state":"COMPLETED","items":[{"label":"root cause","kind":"root cause","text":"QQuickColor shadows the shell Color singleton","anchor":"Unable to assign [undefined] to QColor"}]}
{"source":"https://x/2","title":"Wifi drops on resume","created":"2026-09-01","closed":"","state":"OPEN","items":[{"label":"symptom","kind":"symptom","text":"wifi gone after suspend"}]}
{"source":"https://x/3","title":"PPPoE 双栈只拿到 IA_PD","created":"2026-10-01","closed":"2026-10-02","state":"","items":[{"label":"symptom","kind":"symptom","text":"LCP drops after 60s","anchor":"无 IPv6 地址"}]}
EOF
sh "$CW" save "archive" >/dev/null || fail "save with an archive"
git -C "$CWTFIGO_HOME" ls-files | grep -q '^archive/' && fail "archive must never be committed"
printf 'self\n' > "$CWTFIGO_HOME/.gitignore"; sh "$CW" status >/dev/null 2>&1
[ "$(grep -cxF -e self -e mode -e yolo.on -e 'hosts/*/yolo.on' -e archive/ "$CWTFIGO_HOME/.gitignore")" = 5 ] || fail ".gitignore should get each missing line once"
# The usage lists every command, the whole header; an unknown command is named before it.
out=$(sh "$CW" stauts 2>&1); [ $? = 1 ] && echo "$out" | head -1 | grep -qx 'cw: unknown command: stauts' || fail "an unknown command should say so: $out"
out=$(sh "$CW" 2>&1); [ $? = 1 ] && echo "$out" | grep -q '^  cw mode \[strict|normal\]' && echo "$out" | grep -q 'collect writes hosts/' || fail "the usage should list cw mode and end with the header: $out"
echo "$out" | grep -q 'unknown command' && fail "no command is not an unknown one: $out"
# cw mode: how much Claude Code asks on this operator machine. The hook reads $REC/mode; normal when there is none.
[ "$(sh "$CW" mode)" = normal ] || fail "cw mode with no mode file should print normal"
# Every visit opens with the mascot, its last line the one promise; no mode words.
art=$(printf '%s\n' '       *' '       |' "  .----'----." '  |  _   _/ |    CWTFIGO' \
  '  | (-o)(-o)|    Claude, what the fuck is going on?' '  | [#####] |' "  '---------'    Scripts run only after your OK.")
out=$(sh "$CW" status 2>/dev/null); [ "$(echo "$out" | head -7)" = "$art" ] || fail "status should open with the art: $out"
echo "$out" | grep -qx "  CWTFIGO version: $V" || fail "status should say the plugin's version, bug reports ask for it: $out"
echo "$out" | grep -q 'Mode\|C  W  T  F\|Reads nothing' && fail "status should have no mode line: $out"
F=$(mktemp -d); out=$(CWTFIGO_HOME=$F/rec sh "$CW" status 2>/dev/null)
[ "$(echo "$out" | head -7)" = "$art" ] || fail "a brand-new record's status should open with the art: $out"
[ "$(echo "$out" | head -7 | LC_ALL=C grep -c '^[ -~]*[^ ]$')" = 7 ] || fail "art lines: ASCII, no trailing spaces: $out"
mkdir -p "$F/h/hosts/box"; out=$(CWTFIGO_HOME=$F/h sh "$CW" status 2>/dev/null)
[ "$(echo "$out" | head -7)" = "$art" ] || fail "a record with a host should open with the art too: $out"
# Under YOLO the art's promise goes and the YOLO line says it.
CWTFIGO_HOME=$F/rec sh "$CW" yolo >/dev/null; out=$(CWTFIGO_HOME=$F/rec sh "$CW" status 2>/dev/null)
[ "$(echo "$out" | sed -n 7p)" = "  '---------'" ] && [ -z "$(echo "$out" | sed -n 8p)" ] && echo "$out" | sed -n 9p | grep -q '^  YOLO is on for every machine' || fail "under YOLO: art, a blank line, then the YOLO line: $out"
echo "$out" | grep -q 'Scripts run only' && fail "under YOLO status should not promise approval: $out"
sh "$CW" mode strict >/dev/null && [ "$(cat "$CWTFIGO_HOME/mode")" = strict ] && [ "$(sh "$CW" mode)" = strict ] || fail "cw mode strict should set and print it"
[ "$(sh "$CW" status 2>/dev/null | head -7)" = "$art" ] || fail "status should keep its promise in strict mode"
for m in yolo '' STRICT 'strict x'; do sh "$CW" mode $m x >/dev/null 2>&1 && fail "cw mode $m x should be refused"; done
for m in yolo '' STRICT; do sh "$CW" mode "$m" >/dev/null 2>&1 && fail "cw mode '$m' should be refused"; done
[ "$(cat "$CWTFIGO_HOME/mode")" = strict ] || fail "a refused cw mode must leave the mode as it was"
git -C "$CWTFIGO_HOME" check-ignore -q mode || fail "mode is per machine: it must be gitignored"
sh "$CW" mode normal >/dev/null && [ "$(sh "$CW" mode)" = normal ] || fail "cw mode normal should set it back"
# A hand-edited mode file: anything but normal (case and spaces aside) is strict, as in the hook. Never fails open.
for m in 'strict\r\n' 'Strict\n' ' strict\n' '' 'x\n'; do
  printf "$m" > "$CWTFIGO_HOME/mode"; [ "$(sh "$CW" mode)" = strict ] || fail "mode file '$m' should read as strict"
done
for m in 'normal\r\n' ' NORMAL \n'; do
  printf "$m" > "$CWTFIGO_HOME/mode"; [ "$(sh "$CW" mode)" = normal ] || fail "mode file '$m' should read as normal"
done
rm "$CWTFIGO_HOME/mode"
# Changed by hand and never saved: status hints. Not for a new record's own files, nor an unadapted foundation.
V=$(mktemp -d)/rec; vs() { CWTFIGO_HOME=$V sh "$CW" status 2>&1 >/dev/null | grep 'unsaved'; }
out=$(vs) && fail "a new record's own files are not unsaved changes: $out"
mkdir -p "$V/hosts/v"; echo 'echo t' > "$V/hosts/v/t.sh"; CWTFIGO_HOME=$V sh "$CW" save t >/dev/null
out=$(vs) && fail "a saved record has no unsaved changes: $out"
# A record saved by an older cw: this one adds its new lines to .gitignore/.gitattributes itself, which isn't the owner's.
sed -i.b '/^mode$/d' "$V/.gitignore"; sed -i.b '/merge=union/d' "$V/.gitattributes"; rm "$V"/.git*.b
git -C "$V" commit -qam old; out=$(vs) && fail "cw's own .gitignore/.gitattributes lines are not unsaved changes: $out"
printf '# CWTFIGO-FOUNDATION\n' > "$V/hosts/v/check.sh"; out=$(vs) && fail "an unadapted foundation is not an unsaved change: $out"
rm "$V/hosts/v/t.sh"; out=$(vs)
echo "$out" | grep -q "^hint: the record has unsaved changes (files: 1, e.g. a file deleted by hand; git -C $V status shows them): .*cw save" || fail "a file deleted by hand should hint cw save: $out"
CWTFIGO_HOME=$V sh "$CW" status 2>/dev/null | grep -q unsaved && fail "the unsaved hint is the model's: stderr only"
sh "$CW" search 拿不到IPv6地址 | head -1 | grep -q '^1\. PPPoE.*  (stopped, opened 2026-10-01, closed 2026-10-02)$' || fail "search should match Chinese text, and show only the ending for an empty state"
out=$(sh "$CW" search unable to assign QColor) || fail "search failed"
echo "$out" | head -1 | grep -q '^1\. Bar black after Qt 6.12' || fail "search should rank the Qt thread first"
echo "$out" | grep -q 'https://x/2' && fail "search should leave out threads with no shared word"
# Misses: a hit logs nothing, no hit logs itself, cw miss logs hits that didn't fit.
[ -e "$CWTFIGO_HOME/misses.jsonl" ] && fail "a hit must not log a miss"
out=$(sh "$CW" search zzqx nothing matches) || fail "no-hit search failed"
[ "$out" = "no match (logged to misses.jsonl)" ] || fail "no hit should say so in one line: $out"
[ "$(jq -c '[.query, .reason, .upstream, .host]' "$CWTFIGO_HOME/misses.jsonl")" = '["zzqx nothing matches","no hit","",""]' ] || fail "no hit should log one line"
sh "$CW" miss --upstream ValveSoftware/gamescope steam black screen | grep -q 'miss logged' || fail "cw miss failed"
[ "$(tail -1 "$CWTFIGO_HOME/misses.jsonl" | jq -c '[.query, .reason, .upstream, .host, (.date | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))]')" = '["steam black screen","not relevant","ValveSoftware/gamescope","",true]' ] || fail "cw miss line wrong: $(tail -1 "$CWTFIGO_HOME/misses.jsonl")"
sh "$CW" miss --host 2>/dev/null && fail "cw miss --host without a value should fail"
sh "$CW" miss 2>/dev/null && fail "cw miss without words should fail"
[ "$(wc -l < "$CWTFIGO_HOME/misses.jsonl")" -eq 2 ] || fail "refused cw miss must not log"
# Own cases: hosts/*/cases.jsonl ranks with the archive, marked as own; the last line per source wins.
cat > "$H/cases.jsonl" <<'EOF'
{"source":"cwtfigo:box/2026-11-01-lid","title":"Lid wake parked","created":"2026-11-01","closed":"","state":"parked","items":[{"label":"symptom","kind":"symptom","text":"lid open does not wake","anchor":"Unexpected lid state reported by firmware","from":"log.md 2026-11-01"}]}
not json
{"source":"cwtfigo:box/2026-11-01-lid","title":"Lid wake fixed","created":"2026-11-01","closed":"2026-11-03","state":"fixed","items":[{"label":"resolution","kind":"resolution","text":"lid wake works after BIOS update","anchor":"Unexpected lid state reported by firmware","from":"log.md 2026-11-03"}]}
EOF
out=$(sh "$CW" search lid wake firmware 2>/dev/null) || fail "search with cases failed"
echo "$out" | head -2 | tr '\n' ' ' | grep -q '^1\. Lid wake fixed  (fixed, opened 2026-11-01, closed 2026-11-03) *cwtfigo:box/2026-11-01-lid  (your own visit on box)' || fail "own case should be found and marked: $out"
echo "$out" | grep -q 'Lid wake parked' && fail "a later line with the same source should replace the earlier one"
sh "$CW" search lid 2>&1 >/dev/null | grep -q 'skipping bad line' || fail "a bad cases line should be skipped with a warning"
C=$(mktemp -d)/rec; mkdir -p "$C/hosts/box"; cp "$H/cases.jsonl" "$C/hosts/box/"
out=$(CWTFIGO_HOME=$C sh "$CW" search lid 2>&1) || fail "cases without an archive should still be searched"
echo "$out" | grep -q 'your own visit on box' || fail "cases without an archive should be found: $out"
# Own cases are boosted: one scoring a bit below an archive thread comes first, one sharing only a common word doesn't.
# The second sits at about 1/1.7 of the archive thread's score: a boost of 2 would put it first.
O=$(mktemp -d)/rec; mkdir -p "$O/hosts/box"
printf '%s\n' '{"source":"cwtfigo:box/b","title":"Battery drains in sleep","items":[{"kind":"symptom","text":"battery is low after a night asleep"}]}' \
  '{"source":"cwtfigo:box/f","title":"Fan keeps spinning","items":[{"kind":"symptom","text":"it keeps spinning"}]}' > "$O/hosts/box/cases.jsonl"
printf '%s\n' '{"source":"https://x/b","title":"Battery drains in sleep","items":[{"kind":"symptom","text":"battery empty overnight"}]}' \
  '{"source":"https://x/d","title":"Container keeps restarting","items":[{"kind":"symptom","text":"restart loop after the update"}]}' \
  '{"source":"https://x/w","title":"Wifi drops","items":[{"kind":"symptom","text":"wifi gone after resume"}]}' > "$O/archive.jsonl"
out=$(CWTFIGO_HOME=$O CWTFIGO_ARCHIVE=$O/archive.jsonl sh "$CW" search battery sleep 2>&1)
echo "$out" | sed -n 2p | grep -q 'cwtfigo:box/b' || fail "an own case scoring a bit below an archive thread should come first: $out"
out=$(CWTFIGO_HOME=$O CWTFIGO_ARCHIVE=$O/archive.jsonl sh "$CW" search docker keeps restarting 2>&1)
echo "$out" | sed -n 2p | grep -q 'https://x/d' || fail "an own case sharing only a common word should not beat a strong archive match: $out"
# Who said it, the derived ending, stone zones (2026-11-05 corpus analysis). `from` is P<participant> #<post>.
cat >> "$CWTFIGO_HOME/archive/archive.jsonl" <<'EOF'
{"source":"https://github.com/a/b/issues/4","title":"Zebra panel crash","created":"2024-01-01","closed":"","state":"OPEN","items":[{"label":"symptom","kind":"symptom","text":"zebra panel crashes","from":"P0 #0"},{"label":"root cause","kind":"root cause","text":"zebra cache overflow","from":"P0 #0"},{"label":"workaround","kind":"workaround","text":"disabling the cache worked for some users and not for the reporter","from":"P1 #2"},{"label":"observation","kind":"observation","text":"still crashes","from":"P2 #3"}]}
{"source":"https://github.com/a/b/issues/5","title":"Zebra stripes missing","created":"2026-10-01","closed":"2026-10-02","state":"COMPLETED","items":[{"label":"symptom","kind":"symptom","text":"zebra stripes gone","from":"P0 #0"},{"label":"root cause","kind":"root cause","text":"theme cache","from":"P0 #0"},{"label":"root cause","kind":"root cause","text":"maintainer confirms the theme cache","from":"P1 #1"}]}
{"source":"https://github.com/a/b/issues/6","title":"Zebra icons blank","created":"2026-10-03","closed":"2026-10-05","state":"COMPLETED","items":[{"label":"symptom","kind":"symptom","text":"zebra icons blank","from":"P0 #0"},{"label":"resolution","kind":"resolution","text":"fixed by the icon loader change","from":"P1 #4"}]}
{"source":"https://x/7","title":"Zebra zoom stuck","created":"2026-10-03","closed":"","state":"","items":[{"label":"symptom","kind":"symptom","text":"zebra zoom stuck"}]}
EOF
echo '{"source":"cwtfigo:box/2026-11-02-fan","title":"Fan zebra loud","created":"2026-11-02","closed":"","state":"parked","items":[{"label":"symptom","kind":"symptom","text":"fan loud under zebra load","from":"log.md 2026-11-02"}]}' >> "$H/cases.jsonl"
out=$(sh "$CW" search zebra 2>/dev/null) || fail "zebra search failed"
echo "$out" | grep -q '^[0-9]\. Zebra panel crash  (open → worked around, opened 2024-01-01)$' || fail "ending after the state: $out"
echo "$out" | grep -q '^[0-9]\. Zebra stripes missing  (completed → stopped, ' || fail "completed with nothing fixed should end stopped"
echo "$out" | grep -q '^[0-9]\. Zebra icons blank  (completed → fixed, ' || fail "a resolution should end fixed"
echo "$out" | grep -q '^[0-9]\. Zebra zoom stuck  (stopped, ' || fail "no state: the ending alone"
echo "$out" | grep -q '^[0-9]\. Fan zebra loud  (parked → stopped, ' || fail "a parked case should end stopped"
echo "$out" | grep -q 'fan loud under zebra load  (log.md 2026-11-02)$' || fail "a case fact should say where it came from"
echo "$out" | grep -q '\[root cause\] zebra cache overflow  (P0 #0, opening post, unconfirmed)$' || fail "an opening-post root cause nobody confirmed should be marked"
echo "$out" | grep -q '\[root cause\] theme cache  (P0 #0)$' || fail "a root cause confirmed later should not be marked"
echo "$out" | grep -q 'zebra zoom stuck$' || fail "a fact without from should print without a suffix"
echo "$out" | sed -n '/Zebra panel crash/,/^$/p' | grep -qx '   stone zone: a fix/workaround here worked for some and not others' || fail "mixed fix results should be a stone zone"
echo "$out" | sed -n '/Zebra panel crash/,/^$/p' | grep -qx '   stone zone: open/unfixed for over a year with several people' || fail "a year unfixed with 3 people should be a stone zone"
[ "$(echo "$out" | grep -c 'stone zone')" = 2 ] || fail "stone zone lines only on the stone thread"
echo "$out" | tail -1 | grep -qx 'most matches ended stopped/around: expect a workaround or a park, not a fix' || fail "3+ of 5 stopped/around should say so"
sh "$CW" search -n 2 zebra 2>/dev/null | grep -q 'most matches' && fail "fewer than 3 hits can't be most of 5"
sh "$CW" search unable to assign QColor | grep -q 'most matches' && fail "one hit is no footer"
# No archive, no cases: search says so.
N=$(mktemp -d)/rec
out=$(CWTFIGO_HOME=$N sh "$CW" search wifi 2>&1); [ $? = 1 ] || fail "search with nothing to search should fail"
echo "$out" | grep -q 'nothing to search' || fail "search should say there's nothing to search: $out"
# Hand-written lines with missing fields or broken JSON, in cases or the archive: skipped or filled in, never a crash.
M=$(mktemp -d)/rec; mkdir -p "$M/hosts/box"
printf '%s\n' '{"source":"cwtfigo:box/x","state":"parked","items":[{"text":"quokka fan loud"},{"kind":null,"label":"symptom","text":"quokka hot","anchor":null,"from":null},"junk"]}' > "$M/hosts/box/cases.jsonl"
printf '%s\n' 'not json' '{"title":"no source"}' '{"source":"https://x/q","title":"Quokka crash","created":"2026-01-01","items":[{"label":"symptom","kind":"symptom","text":"quokka crashes"}]}' > "$M/archive.jsonl"
out=$(CWTFIGO_HOME=$M CWTFIGO_ARCHIVE=$M/archive.jsonl sh "$CW" search quokka 2>&1) || fail "search should survive lines with missing fields: $out"
[ "$(echo "$out" | grep -c 'skipping bad line .*archive.jsonl:[12]$')" = 2 ] || fail "bad archive lines should be skipped with a warning: $out"
echo "$out" | grep -qx '   - quokka fan loud' && echo "$out" | grep -qx '   - \[symptom\] quokka hot' || fail "a fact without kind should show its label, or nothing: $out"
echo "$out" | grep -q '^[0-9]\.   (parked → stopped)$' || fail "a case without title or created should still print: $out"
echo "$out" | grep -q '^[0-9]\. Quokka crash  (stopped, opened 2026-01-01)$' || fail "the good archive line should be found: $out"
printf '%s\n' '{"source":"cwtfigo:box/y","items":[{"text":"quokka disk","from":3},{"text":"quokka list","kind":["symptom"]},{"text":"quokka anchor","anchor":{}},{"text":"quokka ok"}]}' >> "$M/hosts/box/cases.jsonl"
out=$(CWTFIGO_HOME=$M CWTFIGO_ARCHIVE=$M/archive.jsonl sh "$CW" search quokka 2>&1) || fail "search should survive facts with a non-text from, kind or anchor: $out"
echo "$out" | grep -qx '   - quokka ok' && ! echo "$out" | grep -Eq 'quokka (disk|list|anchor)' || fail "facts with a non-text from, kind or anchor should be skipped: $out"
# Kana, Hangul and full-width letters are words too.
printf '%s\n' '{"source":"https://x/k","title":"スリープから復帰しない","items":[{"label":"symptom","kind":"symptom","text":"와이파이 끊김 after resume"}]}' >> "$M/archive.jsonl"
for q in スリープ 와이파이 ＲＥＳＵＭＥ; do
  CWTFIGO_HOME=$M CWTFIGO_ARCHIVE=$M/archive.jsonl sh "$CW" search "$q" 2>/dev/null | grep -q 'https://x/k' || fail "search should match $q"
done
# The files are UTF-8 whatever the locale (Windows: the system code page). A locale the system lacks tests nothing.
LC_ALL=en_US.ISO8859-1 CWTFIGO_HOME=$M CWTFIGO_ARCHIVE=$M/archive.jsonl sh "$CW" search スリープ 2>/dev/null | grep -q 'https://x/k' || fail "search should read UTF-8 under a non-UTF-8 locale"
for a in "-n" "-n x" "-n 0"; do
  out=$(CWTFIGO_HOME=$M CWTFIGO_ARCHIVE=$M/archive.jsonl sh "$CW" search $a 2>&1); [ $? = 1 ] && echo "$out" | grep -q '^search: -n wants a number' || fail "search $a: $out"
done
# The panel is the human's: what the model should do goes to stderr as hint: lines.
out=$(CWTFIGO_HOME=$N sh "$CW" status 2>/dev/null)
echo "$out" | grep -Eq 'cw |ask the human|operator|hint' && fail "status should hold nothing for the model on a fresh record: $out"
# Unattended: approved scripts only, model and message only when something is found, never under YOLO.
# Git Bash rewrites a <rev>:<path> argument (origin/main:.gitignore becomes origin\main;.gitignore): cw doesn't pass one.
grep -nE 'git(_rec)? [^#]*[A-Za-z0-9_}"]:[A-Za-z0-9_.$"]' "$CW" "$(dirname "$CW")/unattended.sh" && fail "<rev>:<path> to git breaks on Git Bash: read by object id (ls-tree, cat-file) or checkout"
# cw join: a new operator takes the shared record; one with its own record merges into it. Temp HOME: no git identity.
J=$(mktemp -d); jw() { r=$1; shift; HOME=$J CWTFIGO_HOME=$J/$r sh "$CW" "$@"; }
jg() { r=$1; shift; HOME=$J git -C "$J/$r" "$@"; }
git init -q --bare "$J/shared.git"
out=$(jw new status 2>&1 >/dev/null)
echo "$out" | grep -q '^hint: this record is new and not shared: this owner is new to CWTFIGO\. A problem they named comes first\. If they only said the name, offer a checkup .*disk, memory and battery health.*how much space cleaning would free (sizes only' || fail "a brand-new record's status should say the owner is new and offer the whole checkup: $out"
# Other computers only when the owner brings them up: no question every visit, nothing to remember.
[ "$(echo "$out" | grep -c '^hint: ')" = 1 ] && ! echo "$out" | grep -q 'ask once\|before anything else' || fail "a brand-new record's status should not have the model ask about other computers: $out"
# A host already, no commit or remote yet: not a first-ever visit.
mkdir -p "$J/h/hosts/box"; jw h status 2>&1 >/dev/null | grep -q 'owner is new\|another computer' && fail "a record with a host is not a new owner"
out=$(jw a join "$J/shared.git" 2>&1) || fail "join to an empty shared record: $out"
echo "$out" | grep -q 'empty: the next cw save' || fail "an empty shared record should say cw save fills it: $out"
mkdir -p "$J/a/hosts/home" "$J/a/hosts/desk"; echo 'id: home-id' > "$J/a/hosts/home/facts.md"; echo 'id: desk-id' > "$J/a/hosts/desk/facts.md"
printf '%s\n' '- likes it quiet' '- shared bullet' > "$J/a/operator.md"; echo '- home: NAS mounts' > "$J/a/topology.md"
jw a save first >/dev/null 2>&1 || fail "save after joining an empty shared record"
jg a rev-parse -q --verify '@{upstream}' >/dev/null || fail "first save to the shared record should set the upstream"
# No record yet: join clones it, leaves it clean with an upstream, asks for this machine's name.
out=$(jw b join "$J/shared.git" 2>&1) || fail "join with no local record: $out"
jw b status 2>&1 >/dev/null | grep -q 'cw join' && fail "a joined record's status should not point at cw join"
jw c status 2>&1 >/dev/null; mkdir -p "$J/c/hosts"; jw c save x >/dev/null 2>&1; jw c status 2>&1 >/dev/null | grep -q 'cw join' && fail "a saved record's status should not point at cw join"
[ -f "$J/b/hosts/home/facts.md" ] && [ -f "$J/b/operator.md" ] || fail "join should bring the shared record"
[ -z "$(jg b status --porcelain)" ] && jg b rev-parse -q --verify '@{upstream}' >/dev/null || fail "joined record should be clean with an upstream: $(jg b status --porcelain)"
[ "$(jg b rev-parse HEAD)" = "$(jg a rev-parse HEAD)" ] || fail "a new record should be the shared one, no merge commit"
echo "$out" | grep -q '^hint: .*cw name <name>' || fail "join with no name should ask for one: $out"
# Another computer's own record, not a shared copy: git would refuse every push into it. Refused, nothing changed,
# as a path or over ssh (the ssh here runs the command in HOME, as sshd does); a shared copy over ssh joins.
mkdir "$J/bin"; printf '#!/bin/sh\nwhile :; do case $1 in -o) shift 2 ;; -*) shift ;; *) break ;; esac; done\nshift; cd "$HOME" && exec sh -c "$*"\n' > "$J/bin/ssh"; chmod +x "$J/bin/ssh"
for u in "$J/a" fake:a; do
  out=$(PATH=$J/bin:$PATH jw nb join "$u" 2>&1) && fail "join to another computer's own record ($u) should be refused: $out"
  echo "$out" | grep -q "not a shared copy.*git init --bare" || fail "a refused join should say to make a shared copy: $out"
  [ -z "$(jg nb remote)" ] && [ ! -e "$J/nb/hosts" ] || fail "a refused join should change nothing"
done
PATH=$J/bin:$PATH jw sb join fake:shared.git >/dev/null 2>&1 && [ -f "$J/sb/hosts/home/facts.md" ] || fail "join to a shared copy over ssh"
# A record of its own: same collector id under another name keeps the shared host; root notes are unioned.
mkdir -p "$J/c/hosts/server" "$J/c/hosts/pc"; echo 'id: home-id' > "$J/c/hosts/server/facts.md"; echo 'id: desk-id' > "$J/c/hosts/pc/facts.md"
echo pc > "$J/c/self"; echo x > "$J/c/hosts/pc/log.md"
mkdir -p "$J/c/hosts/nas"; echo 'id: nas-id' > "$J/c/hosts/nas/facts.md"; printf '# CWTFIGO-FOUNDATION\n' > "$J/c/hosts/nas/maintain.sh"
printf '%s\n' '- shared bullet' '- uses fish' > "$J/c/operator.md"; echo '- server: off at night' > "$J/c/topology.md"
jw c save own >/dev/null 2>&1; echo 'mine-only' >> "$J/c/.gitignore"; jw c save ign >/dev/null 2>&1
touch "$J/c/dirty"; jw c join "$J/shared.git" >/dev/null 2>&1 && fail "join with unsaved changes should be refused"
rm "$J/c/dirty"; c0=$(jg c rev-parse HEAD)
mkdir "$J/keep"; t=$J/keep jw c join "$J/nowhere.git" >/dev/null 2>&1 && fail "join to a missing record should fail"
[ -d "$J/keep" ] || fail "a failed join must not remove the dir an environment variable t names"
[ -z "$(jg c remote)" ] && [ "$(jg c rev-parse HEAD)" = "$c0" ] || fail "a failed join should leave the record as it was"
out=$(jw c join "$J/shared.git" 2>&1) || fail "join with a record of its own: $out"
[ ! -e "$J/c/hosts/server" ] && [ ! -e "$J/c/hosts/pc/facts.md" ] && [ -f "$J/c/hosts/home/facts.md" ] && [ -f "$J/c/hosts/desk/facts.md" ] || fail "duplicate ids should keep the shared hosts: $(ls "$J/c/hosts")"
echo "$out" | grep -q 'hosts/server is hosts/home in the shared record' || fail "a dropped duplicate should be reported: $out"
grep -qx desk "$J/c/self" || fail "this machine's own dir was a duplicate: self should follow the shared name"
[ "$(grep -c 'shared bullet' "$J/c/operator.md")" = 1 ] && grep -q 'uses fish' "$J/c/operator.md" && grep -q 'likes it quiet' "$J/c/operator.md" || fail "operator.md should be the union: $(cat "$J/c/operator.md")"
grep -q 'off at night' "$J/c/topology.md" && grep -q 'NAS mounts' "$J/c/topology.md" || fail "topology.md should be the union"
grep -q mine-only "$J/c/.gitignore" && fail ".gitignore should be the shared one"
grep -qx self "$J/c/.gitignore" || fail ".gitignore should keep cw's lines"
[ "$(jg c status --porcelain)" = '?? hosts/nas/maintain.sh' ] && jg c rev-parse -q --verify '@{upstream}' >/dev/null || fail "joined record should be clean with an upstream: $(jg c status --porcelain)"
[ -f "$J/c/hosts/nas/facts.md" ] && [ -f "$J/c/hosts/nas/maintain.sh" ] || fail "join should keep a host only this record has, and its unadapted foundation"
jw c save pushed >/dev/null 2>&1 && [ "$(jg c rev-parse HEAD)" = "$(git -C "$J/shared.git" rev-parse "$(jg c rev-parse --abbrev-ref HEAD)")" ] || fail "save after join should push"
out=$(jw c join "$J/shared.git" 2>&1) && echo "$out" | grep -q 'already joined' || fail "joining again should say so: $out"
[ -f "$J/c/hosts/home/facts.md" ] && [ "$(jg c status --porcelain)" = '?? hosts/nas/maintain.sh' ] || fail "joining again must not drop any host"
# Same name, another machine: stop, change nothing.
mkdir -p "$J/d/hosts/home"; echo 'id: other-id' > "$J/d/hosts/home/facts.md"; jw d save own >/dev/null 2>&1; d0=$(jg d rev-parse HEAD)
out=$(jw d join "$J/shared.git" 2>&1) && fail "two different hosts/home should stop join"
echo "$out" | grep -q 'hosts/home/facts.md' || fail "join should name the clashing file: $out"
[ -z "$(jg d remote)" ] && [ "$(jg d rev-parse HEAD)" = "$d0" ] && [ -z "$(jg d status --porcelain)" ] && grep -q other-id "$J/d/hosts/home/facts.md" || fail "a refused join should change nothing"
# git refuses the merge itself (an untracked file in the way): stop, don't claim it joined.
echo 'echo hi' > "$J/c/hosts/home/check.sh"; jw c save check >/dev/null 2>&1 || fail "save check"
mkdir -p "$J/e/hosts/x" "$J/e/hosts/home"; echo 'id: x-id' > "$J/e/hosts/x/facts.md"; jw e save own >/dev/null 2>&1; e0=$(jg e rev-parse HEAD)
printf '# CWTFIGO-FOUNDATION\n' > "$J/e/hosts/home/check.sh"
out=$(jw e join "$J/shared.git" 2>&1) && fail "a merge git refused should stop join: $out"
echo "$out" | grep -q 'Automatic merge' && fail "join should not pass on git's merge chatter: $out"
[ -z "$(jg e remote)" ] && [ "$(jg e rev-parse HEAD)" = "$e0" ] || fail "a refused merge should change nothing"
rm -rf "$J"

UN=$(dirname "$CW")/unattended.sh; sh -n "$UN" || fail "syntax: unattended.sh"
U=$(mktemp -d); R=$U/rec; B=$R/hosts/box; mkdir -p "$U/bin" "$U/noclaude" "$U/nocurl"
printf '#!/bin/sh\necho call >> %s/claude.calls; echo "SUMMARY"; cat\n' "$U" > "$U/bin/claude"
printf '#!/bin/sh\necho "$*" >> %s/curl.args; while [ $# -gt 0 ]; do [ "$1" = -K ] && cat "$2" >> %s/curl.conf; shift; done; cat >> %s/posted\n' "$U" "$U" "$U" > "$U/bin/curl"
printf '#!/bin/sh\necho "$*" >> %s/ssh.args; exit 255\n' "$U" > "$U/bin/ssh"  # every remote host is off
printf '#!/bin/sh\nexit 1\n' > "$U/noclaude/claude"; cp "$U/noclaude/claude" "$U/nocurl/curl"   # FAIL=<these dirs> un
chmod +x "$U/bin/claude" "$U/bin/curl" "$U/bin/ssh" "$U/noclaude/claude" "$U/nocurl/curl"
echo https://discord.test/api/webhooks/1/secret > "$U/hook"; chmod 600 "$U/hook"
un() { PATH=${FAIL:+$FAIL:}$U/bin:$PATH CWTFIGO_HOME=$R CWTFIGO_NOTIFY=$U/hook sh "$UN"; }
CWTFIGO_HOME=$R sh "$CW" name box >/dev/null; mkdir -p "$B" && touch "$B/approved.sha256"
echo '{ "os": "arch" }' > "$B/device.json"   # sh scripts on every operator, Git Bash too
printf '# menu: 每天的检查\necho "OK   load"\necho "WARN disk / 91%%"\n' > "$B/check.sh"; CWTFIGO_HOME=$R sh "$CW" approve local check >/dev/null
mkdir -p "$R/hosts/nas" "$R/hosts/new"; echo "x  check  2026-11-01" > "$R/hosts/nas/approved.sha256"; touch "$R/hosts/new/approved.sha256"
printf '## 用途\n- 家里的 NAS\n' > "$B/notes.md"; CWTFIGO_HOME=$R sh "$CW" save init >/dev/null
# A failed post marks nothing seen: the next run sends the same findings.
(FAIL=$U/noclaude:$U/nocurl un >/dev/null 2>&1) && fail "a failed post should exit non-zero"
[ -e "$R/unattended.seen/box" ] && fail "a failed post must not mark its findings seen"
out=$(un) || fail "unattended with a WARN should exit 0: $out"
[ "$(wc -l < "$U/claude.calls")" -eq 1 ] && [ "$(wc -l < "$U/curl.args")" -eq 1 ] || fail "one WARN: one summary, one post"
jq -r .content "$U/posted" | grep -q 'check: WARN disk / 91%' || fail "post should carry the WARN: $(cat "$U/posted")"
jq -r .content "$U/posted" | grep -q '^# menu: 每天的检查$' || fail "the model should get the menu lines, to write in their language: $(cat "$U/posted")"
jq -r .content "$U/posted" | grep -q '家里的 NAS' && fail "notes.md must not go to the model: $(cat "$U/posted")"
[ "$(jq -c .allowed_mentions "$U/posted")" = '{"parse":[]}' ] || fail "post must not ping anyone: $(cat "$U/posted")"
jq -r .content "$U/posted" | grep -q 'offline (skipped): nas' || fail "offline host should be one line"
jq -r .content "$U/posted" | grep -q 'new' && fail "a host without an approved check is not checked"
grep -q secret "$U/curl.args" && fail "webhook URL must not be on curl's command line"
grep -q 'url = "https://discord.test/api/webhooks/1/secret"' "$U/curl.conf" || fail "curl should get the URL from its config"
echo "$out" | grep -q secret && fail "webhook URL must never be printed"
[ "$(sed -n 1p "$B/log.md")" = "## $(date +%F) unattended" ] && grep -qx -- '- check: WARN disk / 91%' "$B/log.md" || fail "log.md entry: $(cat "$B/log.md")"
git -C "$R" log -1 --format=%s | grep -qx "unattended $(date +%F)" || fail "record should be saved"
git -C "$R" status --porcelain | grep -q . && fail "unattended.last should be ignored, record clean"
grep -q 'reported, posted' "$R/unattended.last" || fail "last-run line"
cp "$B/log.md" "$U/log.before"; un >/dev/null || fail "repeat run"
[ "$(wc -l < "$U/curl.args")" -eq 1 ] && cmp -s "$B/log.md" "$U/log.before" || fail "same WARN as last run: no second post, no second log entry"
CWTFIGO_HOME=$R sh "$CW" status 2>/dev/null | grep ' box ' | grep -q 'last visit never' || fail "unattended entries are not visits: $(CWTFIGO_HOME=$R sh "$CW" status | grep box)"
printf 'echo "OK   load"\n' > "$B/check.sh"; CWTFIGO_HOME=$R sh "$CW" approve local check >/dev/null
CWTFIGO_HOME=$R sh "$CW" save quiet >/dev/null; cp "$B/log.md" "$U/log.before"
out=$(un) || fail "clean run should exit 0"
[ -z "$out" ] || fail "clean run should print nothing: $out"
[ "$(wc -l < "$U/claude.calls")" -eq 1 ] && [ "$(wc -l < "$U/curl.args")" -eq 1 ] || fail "clean run: no model call, no post"
cmp -s "$B/log.md" "$U/log.before" || fail "clean run must not write log.md"
grep -q ' ok, offline: nas' "$R/unattended.last" || fail "clean last-run line: $(cat "$R/unattended.last")"
echo 'echo "WARN changed"' >> "$B/check.sh"
(FAIL=$U/noclaude un >/dev/null) || fail "run with a changed check"
tail -1 "$U/posted" | jq -r .content | grep -q 'check: waiting for approval, changed since' || fail "changed check should wait, plain report when the model fails"
grep -q 'WARN changed' "$U/posted" && fail "a changed check must not run"
CWTFIGO_HOME=$R sh "$CW" yolo local >/dev/null
out=$(un 2>&1); [ $? = 2 ] || fail "unattended under YOLO should refuse"
echo "$out" | grep -q 'YOLO is on' || fail "should say why: $out"
[ "$(wc -l < "$U/curl.args")" -eq 2 ] || fail "refused run must not post"
CWTFIGO_HOME=$R sh "$CW" yolo off >/dev/null
# A run that hangs is cut off after CWTFIGO_TIMEOUT and reported, where there's a timeout command.
if command -v timeout >/dev/null; then
  printf 'sleep 30\n' > "$B/maintain.sh"; CWTFIGO_HOME=$R sh "$CW" approve local maintain >/dev/null
  (CWTFIGO_TIMEOUT=1 un >/dev/null) || fail "run with a hanging maintain"
  tail -1 "$U/posted" | jq -r .content | grep -q 'maintain: timed out after 1s' || fail "hanging maintain should be reported as timed out: $(tail -1 "$U/posted")"
else echo "skipped: unattended timeout (no timeout)"; fi
# Exit codes are cw's only: a script's own exit 1 or 3 is neither a failure nor an approval wait; its lines count.
printf 'echo "WARN own exit"\n[ 1 = 2 ] && echo "WARN never"\n' > "$B/check.sh"; CWTFIGO_HOME=$R sh "$CW" approve local check >/dev/null
printf 'echo "BAD m3"\nexit 3\n' > "$B/maintain.sh"; CWTFIGO_HOME=$R sh "$CW" approve local maintain >/dev/null
un >/dev/null || fail "run with scripts exiting 1 and 3"
m=$(tail -1 "$U/posted" | jq -r .content)
echo "$m" | grep -q 'check: WARN own exit' && echo "$m" | grep -q 'maintain: BAD m3' || fail "a script's own exit should keep its WARN/BAD lines: $m"
echo "$m" | grep -Eq 'failed|waiting' && fail "a script's own exit 1 or 3 is not cw's: $m"
printf '# CWTFIGO-FOUNDATION\n' > "$B/maintain.sh"   # cw refuses to run it: that one is a failure
un >/dev/null || fail "run with an unadapted maintain"
tail -1 "$U/posted" | jq -r .content | grep -q 'maintain: failed (exit 1)' || fail "cw refusing should be reported as failed: $(tail -1 "$U/posted")"
# cw status's pull goes through the BatchMode ssh too (a record with no hosts: no cw run pulls).
N=$(mktemp -d)/rec; git init -q "$N"; git -C "$N" remote add origin nohost:rec.git
PATH=$U/bin:$PATH CWTFIGO_HOME=$N CWTFIGO_NOTIFY=/nonexistent sh "$UN" >/dev/null 2>&1
grep -q 'BatchMode=yes.*git-upload-pack' "$U/ssh.args" || fail "cw status's pull should use the BatchMode ssh: $(cat "$U/ssh.args")"
# Write-back with a remote: pull before the commit, commit only the log.md written, a failed save is in the message.
git init -q --bare "$U/bare.git"; git -C "$R" remote add origin "$U/bare.git"; git -C "$R" push -q -u origin HEAD
git clone -q "$U/bare.git" "$U/other"
grep -v '  maintain  ' "$B/approved.sha256" > "$U/a"; cat "$U/a" > "$B/approved.sha256"   # check runs last
# Another operator pushes while check runs, after cw run's own pull.
printf 'echo "WARN pushed"\ngit -C %s -c user.name=t -c user.email=t@t commit -q --allow-empty -m other && git -C %s push -q\n' "$U/other" "$U/other" > "$B/check.sh"
CWTFIGO_HOME=$R sh "$CW" approve local check >/dev/null; echo draft > "$B/notes.md"   # a visit going on right now
out=$(un 2>&1) || fail "run with a remote: $out"
[ "$(git -C "$U/bare.git" log -2 --format=%s | tr '\n' ' ')" = "unattended $(date +%F) other " ] || fail "the commit should go on top of the other push: $(git -C "$U/bare.git" log -3 --format=%s)"
[ "$(git -C "$R" show --name-only --format= HEAD)" = hosts/box/log.md ] || fail "only log.md should be committed: $(git -C "$R" show --name-only --format= HEAD)"
git -C "$R" status --porcelain | grep -q 'notes.md' || fail "a visit's half-done notes.md must stay uncommitted"
printf '#!/bin/sh\nexit 1\n' > "$U/bare.git/hooks/pre-receive"; chmod +x "$U/bare.git/hooks/pre-receive"
printf 'echo "WARN refused"\n' > "$B/check.sh"; CWTFIGO_HOME=$R sh "$CW" approve local check >/dev/null
(un >/dev/null 2>&1) && fail "a failed push should exit non-zero"
tail -1 "$U/posted" | jq -r .content | grep -q 'record committed here, push failed: ' || fail "a failed push should be in the message: $(tail -1 "$U/posted")"
grep -q 'WARN refused' "$R/unattended.seen/box" && fail "an unsaved run must not mark its findings seen"
git -C "$R" remote remove origin
# Stopped mid-post (systemd stop or timeout sends TERM to the whole unit): the temp dir with the URL goes too.
# bash runs the EXIT trap on a fatal signal anyway; dash (Debian's sh) doesn't, so dash where there is one.
mkdir "$U/slowcurl"; printf '#!/bin/sh\nwhile [ $# -gt 0 ]; do [ "$1" = -K ] && echo "$2" > %s/conf.path; shift; done\necho $$ > %s/curl.pid; exec sleep 30\n' "$U" "$U" > "$U/slowcurl/curl"; chmod +x "$U/slowcurl/curl"
printf 'echo "WARN stopped"\n' > "$B/check.sh"; CWTFIGO_HOME=$R sh "$CW" approve local check >/dev/null
D=sh; command -v dash >/dev/null && D=dash
PATH=$U/slowcurl:$U/bin:$PATH CWTFIGO_HOME=$R CWTFIGO_NOTIFY=$U/hook $D "$UN" >/dev/null 2>&1 & p=$!
i=0; until [ -s "$U/curl.pid" ] || [ $i = 100 ]; do sleep 0.1; i=$((i + 1)); done
kill $p "$(cat "$U/curl.pid")"; wait $p
[ -s "$U/conf.path" ] && [ ! -e "$(cat "$U/conf.path")" ] || fail "a TERM during the post should remove curl.conf: $(cat "$U/conf.path")"
echo "ok"
