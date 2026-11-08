#!/bin/sh
# Self-check for hooks/approve-gate.sh: once the plugin has started in a session, approvals ask; everything else,
# and every call in a session that never started it, stays silent. In normal mode cw's reads and record edits get allow.
# Usage: sh tests/approve-gate.sh, or SH=dash sh tests/approve-gate.sh to run the hook under dash (Debian's sh).
set -u
R=$(cd "$(dirname "$0")/.." && pwd); G=$R/hooks/approve-gate.sh; CW=$R/skills/cwtfigo/scripts/cw
fail() { echo "FAIL: $*"; exit 1; }
TMPDIR=$(mktemp -d) || exit 1; export TMPDIR; trap 'rm -rf "$TMPDIR"' EXIT
# The hook reads the mode from the record: a temp one, never the real ~/.cwtfigo.
HOME=$TMPDIR/home; REC=$TMPDIR/rec; export HOME CWTFIGO_HOME=$REC; mkdir -p "$HOME" "$REC/hosts/box"
mkdir "$TMPDIR/cwtfigo-visit" && : > "$TMPDIR/cwtfigo-visit/on"
S=on   # session the calls below come from; "on" has a marker
hook() { printf '{"session_id":"%s",%s}' "$S" "$1" | ${SH:-sh} "$G"; }
bash() { hook "$(printf '"tool_name":"Bash","tool_input":{"command":"%s"}' "$1")"; }
ask() { echo "$1" | grep -q '"permissionDecision":"ask"' || fail "should ask: $2"; }

ask "$(bash 'cw approve local x')" "cw approve"
ask "$(bash 'sh scripts/cw approve local check')" "cw approve by path"
ask "$(bash 'sh scripts/cw approve local probes')" "cw approve probes"
ask "$(bash 'sh scripts/cw approve local check maintain')" "cw approve with several scripts"
ask "$(bash "sh $CW approve box check maintain")" "cw approve with several scripts, full path"
ask "$(bash 'ls && sh \"scripts/cw\" approve local x')" "chained, quoted"
ask "$(bash 'true; sh scripts/cw  approve local x')" "after ;, two spaces"
ask "$(bash 'echo abc >> ~/.cwtfigo/hosts/local/approved.sha256')" "append to approved.sha256"
# Names built at run time or matched by a glob: not every way, the common ones.
ask "$(bash 'X=appr; sh scripts/cw ${X}ove local x')" "cw with a variable for its subcommand"
ask "$(bash 'C=scripts/cw; sh $C approve local x')" "cw run from a variable"
ask "$(bash 'C=scripts/cw; sh \"${C}\" yolo')" "cw run from a variable, quoted"
ask "$(bash 'sha256sum f >> ~/.cwtfigo/hosts/box/approved.sha25?')" "approved.sha256 as a glob"
ask "$(bash 'cp f ~/.cwtfigo/hosts/box/approved*')" "approved* glob"
ask "$(bash 'date +%s > ~/.cwtfigo/hosts/box/yolo.o?')" "yolo.on as a glob"
ask "$(bash 'rm -rf $TMPDIR/cwtfigo-v*')" "the marker dir as a glob"
ask "$(bash 'rm -rf /tmp/cwtfigo*')" "the marker dir as a wider glob"
ask "$(hook '"tool_name":"Write","tool_input":{"file_path":"/Users/u/.cwtfigo/hosts/local/approved.sha256","content":"abc  check.sh"}')" "Write"
ask "$(hook '"tool_name":"Edit","tool_input":{"file_path":"/Users/u/.cwtfigo/hosts/local/approved.sha256","old_string":"a","new_string":"b"}')" "Edit"
ask "$(bash 'sh scripts/cw yolo local')" "cw yolo"
ask "$(bash 'sh \"scripts/cw\"  yolo box')" "cw yolo, quoted, two spaces"
ask "$(bash 'date +%s > ~/.cwtfigo/hosts/local/yolo.on')" "write yolo.on"
ask "$(bash 'touch ~/.cwtfigo/hosts/local/yolo.on')" "touch yolo.on"
ask "$(hook '"tool_name":"Write","tool_input":{"file_path":"/Users/u/.cwtfigo/hosts/local/yolo.on","content":"1"}')" "Write yolo.on"
ask "$(hook '"tool_name":"Write","tool_input":{"file_path":"/Users/u/.cwtfigo/hosts/local/APPROVED.SHA256","content":"x"}')" "Write, other case"

[ -z "$(bash 'ls')" ] || fail "ls should pass silently"
[ -z "$(hook '"tool_name":"Edit","tool_input":{"file_path":"/r/tests/cw.sh","old_string":"a","new_string":"sh cw approve local x >> approved.sha256; cw yolo local; yolo.on"}')" ] || fail "Edit mentioning cw approve should pass silently"
[ -z "$(hook '"tool_name":"Write","tool_input":{"file_path":"/r/hooks/approve-gate.sh","content":"cw approve approved.sha256 yolo.on"}')" ] || fail "Write mentioning approved.sha256 should pass silently"
ask "$(bash 'sh scripts/cw yolo office')" "cw yolo on a host whose name starts with off"
ask "$(bash 'sh scripts/cw yolo off; sh scripts/cw yolo')" "yolo off chained with yolo on"
ask "$(bash 'sh scripts/cw yolo off && sh scripts/cw approve local x')" "yolo off chained with approve"
[ -z "$(bash 'sh scripts/cw yolo off')" ] || fail "cw yolo off should pass silently"
ask "$(bash 'sh scripts/cw yolo off/../..')" "yolo off/../.. is YOLO on for the record's root"
ask "$(bash 'sh scripts/cw yolo off\\/..')" "yolo off\/.. is off/.."
ask "$(bash 'sh scripts/cw yolo \"\" off')" "yolo '' off is YOLO on for every machine"
[ -z "$(bash 'sh scripts/cw yolo off; ls')" ] && [ -z "$(bash 'sh scripts/cw yolo off\nls')" ] || fail "cw yolo off, then another command, should pass silently"
[ -z "$(bash 'sh \"scripts/cw\" YOLO OFF')" ] || fail "cw yolo off, quoted, other case, should pass silently"
[ -z "$(bash 'sh scripts/cw run local logs')" ] || fail "cw run should pass silently"
# cw's name hidden from the match (c''w, c\w): approve or yolo as a whole word asks. A search for the word asks too,
# acceptable: the gate only exists once the plugin started in this session.
ask "$(bash "sh scripts/c''w approve local x")" "c''w approve"
ask "$(bash 'sh scripts/c\\w approve local x')" "c\\w approve"
ask "$(bash 'sh scripts/c\"\"w YOLO box')" "c\"\"w yolo"
ask "$(bash 'sh scripts/cw search approve')" "approve as a whole word"
# The subcommand itself quoted or with a backslash: the shell drops those, so do the asks.
ask "$(bash "sh scripts/cw appr''ove local x")" "appr''ove"
ask "$(bash 'sh scripts/cw approv\\e local x')" "approv\\e"
ask "$(bash "sh scripts/cw yo''lo")" "yo''lo"
ask "$(bash "sh scripts/cw mo''de normal")" "mo''de normal"
ask "$(bash 'sh scripts/cw m\\ode normal')" "m\\ode normal"
ask "$(bash "sh scripts/c''w mo\\\"\\\"de strict")" "c''w mo\"\"de strict"
[ -z "$(bash 'sh scripts/c\\w yolo off')" ] || fail "yolo off with cw hidden should pass silently"
[ -z "$(bash 'sh scripts/cw run local approved-list')" ] || fail "approve inside a longer word should pass silently"
[ -z "$(hook '"tool_name":"Bash","tool_input":{"command":"sh scripts/cw yolo off","description":"Switch off YOLO, approve nothing"}')" ] || fail "the description is not the command"
ask "$(bash 'rm -rf ${TMPDIR:-/tmp}/cwtfigo-visit')" "rm the marker dir"
ask "$(hook '"tool_name":"Write","tool_input":{"file_path":"/var/folders/x/T/cwtfigo-visit/on","content":""}')" "Write the marker"
[ -z "$(hook '"transcript_path":"/Users/u/.claude/projects/-Users-u-CWTFIGO-visit-gate/s.jsonl","cwd":"/Users/u/CWTFIGO-visit-gate","tool_name":"Bash","tool_input":{"command":"ls"}')" ] \
  || fail "cwtfigo-visit in cwd/transcript_path should pass silently"
ask "$(printf '{"tool_name":"Bash","tool_input":{"command":"cw approve local x"}}' | ${SH:-sh} "$G")" "no session_id"
ask "$(printf '{"session_id":"../..","tool_name":"Bash","tool_input":{"command":"cw approve local x"}}' | ${SH:-sh} "$G")" "session_id with nothing left"
# cw mode with an argument sets how much Claude Code asks: the human's. Plain cw mode only prints it.
ask "$(bash "sh $CW mode strict")" "cw mode strict"
ask "$(bash "sh \\\"$CW\\\" mode normal")" "cw mode normal, quoted"
ask "$(bash 'sh scripts/cw mode \"x\"')" "cw mode with a quoted argument"
[ -z "$(bash "sh $CW mode")" ] || fail "plain cw mode should pass silently"
# The prompt says, in plain words to the owner, what their yes does.
why() { echo "$1" | grep -q "\"permissionDecisionReason\":\"CWTFIGO: $2" || fail "the prompt for $3 should say: $2 ($1)"; }
why "$(bash "sh $CW approve box check")" "your yes lets this run from now on" "cw approve"
why "$(hook '"tool_name":"Write","tool_input":{"file_path":"/u/.cwtfigo/hosts/box/approved.sha256","content":"x"}')" "your yes lets this run from now on" "Write approved.sha256"
why "$(bash "sh $CW yolo")" "your yes lets me run things you haven't seen" "cw yolo"
why "$(bash "sh $CW mode strict")" "your yes changes how often I ask" "cw mode strict"
why "$(bash 'rm -rf $TMPDIR/cwtfigo-visit')" "this needs your own yes" "the marker"

# Normal mode (no mode file): what can't change a machine without an approval cw checks gets allow.
allow() { echo "$1" | grep -q '"permissionDecision":"allow"' || fail "should allow: $2"; }
nallow() { echo "$1" | grep -q '"allow"' && fail "should not allow: $2"; }
for c in "sh $CW status" "sh \\\"$CW\\\" status" "sh '$CW' status" "sh  $CW  status" "sh $CW run local logs" \
         "sh $CW run box check" "sh $CW run local net eth0" "sh $CW save \\\"fixed wifi, #6\\\"" "sh $CW save \\\"修好了 wifi\\\"" \
         "sh $CW search wifi drops after suspend" "sh $CW miss --host box --upstream a/b wifi" "sh $CW yolo off" \
         "sh $CW save \\\"checkup (brew upgraded 3 packages), freed 2.1 GB!\\\"" "sh $CW save 'check & maintain done; fine?'" \
         "sh $CW search \\\"Failed to start foo.service (code=exited)\\\" \\\"ACPI: [Firmware Bug]: <lid>\\\"" \
         "sh $CW save \\\"it's done | ok\\\"" "sh $CW miss --host box 'a\\\"b {c}'"; do
  allow "$(bash "$c")" "$c"
done
for c in "sh $CW run local maintain --apply" "sh $CW run local maintain --app''ly" "sh $CW run local maintain --app\\\"\\\"ly" \
         "sh $CW run local maintain --APPLY" "sh $CW status; rm x" "sh $CW status && ls" "sh $CW status | cat" "sh $CW status & ls" \
         "sh $CW save \\\"\$(id)\\\"" "sh $CW save \`id\`" "sh $CW status > f" "sh $CW status < f" "sh $CW status\\nrm x" \
         "sh $CW search wifi*" "sh $CW search {a,b}" "sh $CW run local logs \\\\\\\\" "cd /tmp && sh $CW status" "cd /tmp; sh $CW status" \
         "FOO=1 sh $CW status" "bash $CW status" "sh $CW" "sh $CW yolo off box" "sh $CW yolo offx" "sh $CW yolo off; ls" "sh $CW mode" "sh $CW join box:rec" "sh $CW tui" \
         "sh $CW approve local x" "sh scripts/cw status" "sh /tmp/x/skills/cwtfigo/scripts/cw status" "sh /tmp/evil $CW status" "sh $CW.sh status" \
         "sh $CW\\\" status" "sh \\\"$CW status" "sh $CW run local ~/.ssh/id_ed25519" "sh $CW run box /etc/passwd" \
         "sh $CW name box" "sh $CW save \\\"a\\\" ; ls" "sh $CW save 'a' && ls" "sh $CW save \\\"a; ls" \
         "sh $CW save \\\"a\\\\\\\"; ls; echo \\\"" "sh $CW save \\\"a\\\$(id)\\\"" "sh $CW save \\\"a\\\$HOME\\\"" "sh $CW save \\\"a\\nb\\\"" \
         "sh $CW run local net \\\"(x)\\\"" "sh $CW run local net 'a;b'" "sh $CW run local logs \\\"x!\\\"" "sh $CW run local logs '--apply'" \
         "sh $CW run local ~root" "sh $CW run local \\\"x /etc/passwd\\\"" "sh $CW run local 'logs'" "sh $CW run local"; do
  nallow "$(bash "$c")" "$c"
done
# A plugin dir with a space: unquoted, sh would run the part before the space.
B="$TMPDIR/a b"; mkdir -p "$B/hooks" "$B/skills/cwtfigo"; cp "$G" "$B/hooks/"
sp() { printf '{"session_id":"on","tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" | ${SH:-sh} "$B/hooks/approve-gate.sh"; }
allow "$(sp "sh \\\"$B/skills/cwtfigo/scripts/cw\\\" status")" "quoted path with a space"
nallow "$(sp "sh $B/skills/cwtfigo/scripts/cw status")" "unquoted path with a space"
allow "$(sp "cd \\\"$B/skills/cwtfigo\\\" && sh scripts/cw status")" "cd to a quoted dir with a space"
nallow "$(sp "cd $B/skills/cwtfigo && sh scripts/cw status")" "cd to an unquoted dir with a space"
# scripts/cw, as models type it: from this plugin's skills/cwtfigo, by the input's cwd or by exactly one cd ... &&.
D=$R/skills/cwtfigo
bcwd() { hook "$(printf '"cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"}' "$1" "$2")"; }
for c in "sh scripts/cw status" "sh scripts/cw run local logs" "sh \\\"scripts/cw\\\" save \\\"x\\\"" "sh 'scripts/cw' search wifi" "sh $CW status"; do
  allow "$(bcwd "$D" "$c")" "cwd skills/cwtfigo: $c"
done
allow "$(bcwd "$D/" "sh scripts/cw status")" "cwd skills/cwtfigo/"
for c in "cd $D && sh scripts/cw run local logs" "cd \\\"$D\\\" && sh scripts/cw status" "cd '$D' && sh scripts/cw save \\\"x\\\"" \
         "cd $D/scripts/.. && sh scripts/cw status" "cd $D  &&  sh scripts/cw status"; do
  allow "$(bcwd /tmp "$c")" "$c"
done
for c in "sh scripts/cw run local maintain --apply" "sh scripts/cw approve local x" "sh scripts/cw mode" \
         "sh scripts/cw status; ls" "sh scripts/cwx status" "sh ./scripts/cw status"; do
  nallow "$(bcwd "$D" "$c")" "cwd skills/cwtfigo: $c"
done
for w in /tmp "$R" "$R/skills" "$D/scripts" skills/cwtfigo "$D\\\\"; do
  nallow "$(bcwd "$w" "sh scripts/cw status")" "cwd $w"
done
nallow "$(bash "sh scripts/cw status")" "no cwd"
# Git Bash on Windows: Claude Code shows C:\Users\..., the shell has /c/Users/... and cygpath between them. A fake
# cygpath maps C:<posix path> both ways.
Y=$TMPDIR/cyg; mkdir "$Y"; printf '#!/bin/sh\ncase $1 in -m) printf "C:%%s\\n" "$2" ;; -u) printf "%%s\\n" "$2" | sed "s|^C:||; s|\\\\\\\\|/|g" ;; esac\n' > "$Y/cygpath"; chmod +x "$Y/cygpath"
DW=$(printf '%s' "C:$D" | sed 's|/|\\\\|g')   # C:\Users\... as JSON writes it
for c in "sh C:$CW status" "sh \\\"C:$CW\\\" run local logs" "sh 'C:$CW' save x" "cd C:$D && sh scripts/cw status"; do
  allow "$(PATH=$Y:$PATH bcwd /tmp "$c")" "Git Bash: $c"
done
allow "$(PATH=$Y:$PATH bcwd "C:$D" "sh scripts/cw status")" "Git Bash: cwd C:/..."
allow "$(PATH=$Y:$PATH bcwd "$DW" "sh scripts/cw status")" "Git Bash: cwd C:\\..."
for c in "sh D:$CW status" "sh C:$CW.sh status" "sh C:$CW status; ls" "sh C:$CW approve box x"; do nallow "$(PATH=$Y:$PATH bcwd /tmp "$c")" "Git Bash: $c"; done
nallow "$(bcwd /tmp "sh C:$CW status")" "C:/... without cygpath (not Git Bash)"
nallow "$(bcwd "C:$D" "sh scripts/cw status")" "cwd C:/... without cygpath"
for c in "cd /tmp && sh scripts/cw status" "cd $R && sh scripts/cw status" "cd $D/.. && sh scripts/cw status" \
         "cd skills/cwtfigo && sh scripts/cw status" "cd $D ; sh scripts/cw status" "cd $D; sh scripts/cw status" \
         "cd $D && cd $D && sh scripts/cw status" "cd $D && sh scripts/cw status && ls" "cd $D && sh scripts/cw status & ls" \
         "cd $D && sh scripts/cw approve local x" "cd $D && sh scripts/cw yolo" "cd $D && sh scripts/cw run local maintain --apply" \
         "cd $D && sh scripts/cw status | cat" "cd \\\"\$(echo $D)\\\" && sh scripts/cw status" "cd \\\"$D\\\"\\\"/x\\\" && sh scripts/cw status" \
         "cd $D &&& sh scripts/cw status" "cd $D && ls && sh scripts/cw status" "ls && cd $D && sh scripts/cw status" "cd $D && sh scripts/cw"; do
  nallow "$(bcwd /tmp "$c")" "$c"
  nallow "$(bcwd "$D" "$c")" "cwd skills/cwtfigo: $c"
done
w() { hook "$(printf '"tool_name":"%s","tool_input":{"file_path":"%s","content":"x"}' "$1" "$2")"; }
allow "$(w Write "$REC/hosts/box/notes.md")" "Write notes.md"
allow "$(w Edit "$REC/operator.md")" "Edit operator.md"
allow "$(w Write "$REC/hosts/box/check.sh")" "Write a host script: it can't run until approved"
# Under YOLO a written script runs unapproved: no allow for one then, notes still.
for y in "$REC/hosts/box/yolo.on" "$REC/yolo.on"; do
  : > "$y"; nallow "$(w Write "$REC/hosts/box/check.sh")" "Write a host script under YOLO ($y)"
  nallow "$(w Edit "$REC/hosts/other/fix.PS1")" "Edit a .ps1 under YOLO ($y)"
  allow "$(w Write "$REC/hosts/box/notes.md")" "Write notes.md under YOLO ($y)"; rm "$y"
done
for f in "$REC/hosts/box/approved.sha256" "$REC/hosts/box/yolo.on" "$REC/yolo.on" "$REC/mode" "$REC/MODE" "$REC/self" \
         "$REC/.git/config" "$REC/.git/hooks/pre-commit" "$REC/.gitignore" "$REC/.gitattributes" "$REC/hosts/box/../../x" \
         "$REC/hosts/./box/notes.md" "$REC//operator.md" "$REC/../x" "$REC/" "$REC" "${REC}2/x" "$TMPDIR/elsewhere/notes.md" \
         "$REC/hosts/box/a\\\\b"; do
  nallow "$(w Write "$f")" "Write $f"
done
# A Mac folds U+017F (long s) to s: approved.ſha256 and ſelf are approved.sha256 and self there.
for f in "$REC/hosts/box/approved.ſha256" "$REC/ſelf" "$REC/hosts/box/nötes.md"; do nallow "$(w Write "$f")" "Write $f, not ASCII"; done
ln -s "$TMPDIR/home" "$REC/hosts/ln"; nallow "$(w Write "$REC/hosts/ln/.bashrc")" "Write through a symlink out of the record"
nallow "$(hook "$(printf '"tool_name":"NotebookEdit","tool_input":{"file_path":"%s"}' "$REC/hosts/box/notes.md")")" "another tool"
mkdir -p "$HOME/.cwtfigo"; allow "$(CWTFIGO_HOME= hook "$(printf '"tool_name":"Write","tool_input":{"file_path":"%s"}' "$HOME/.cwtfigo/notes.md")")" "the record at ~/.cwtfigo"
# Strict: no allow at all, the asks stay.
echo strict > "$REC/mode"
nallow "$(bash "sh $CW status")" "strict mode, cw status"
nallow "$(w Write "$REC/hosts/box/notes.md")" "strict mode, Write notes.md"
ask "$(bash "sh $CW approve local x")" "strict mode, cw approve"
# A hand-edited mode file: anything but normal (case and spaces aside) is strict. Never fails open.
for m in 'strict\r\n' 'Strict\n' ' strict\n' '' 'x\n'; do printf "$m" > "$REC/mode"; nallow "$(bash "sh $CW status")" "mode file '$m'"; done
for m in 'normal\r\n' ' NORMAL \n'; do printf "$m" > "$REC/mode"; allow "$(bash "sh $CW status")" "mode file '$m'"; done
rm "$REC/mode"

# Not started: silent. Starting one session doesn't start another.
S=a
[ -z "$(bash 'cw approve local x')" ] || fail "cw approve before start should pass silently"
[ -z "$(bash 'rm -rf $TMPDIR/cwtfigo-visit')" ] || fail "rm marker before start should pass silently"
[ -z "$(bash "sh $CW status")" ] && [ -z "$(w Write "$REC/hosts/box/notes.md")" ] || fail "no allow before start either"
[ -z "$(hook '"tool_name":"Skill","tool_input":{"skill":"caveman:caveman"}')" ] || fail "other Skill should pass silently"
[ -z "$(bash 'cw approve local x')" ] || fail "other Skill shouldn't start"
[ -z "$(hook '"tool_name":"Skill","tool_input":{"skill":"cwtfigo:cwtfigo","args":"slow"}')" ] || fail "Skill call should print nothing"
ask "$(bash 'cw approve local x')" "after Skill cwtfigo:cwtfigo"
S=b
[ -z "$(bash 'cw approve local x')" ] || fail "other session should stay silent"
S=c
up() { hook "$(printf '"hook_event_name":"UserPromptSubmit","prompt":"%s"' "$1")"; }
[ -z "$(up 'what is /cwtfigo for')" ] && [ -z "$(up '/cwtfigox')" ] || fail "prompt not starting with /cwtfigo should print nothing"
[ -z "$(bash 'cw approve local x')" ] || fail "prompt not starting with /cwtfigo shouldn't start"
[ -z "$(up '/cwtfigo my mac is hot')" ] || fail "UserPromptSubmit should print nothing"
ask "$(bash 'cw approve local x')" "after /cwtfigo prompt"
S=d; up '/cwtfigo:cwtfigo' >/dev/null
ask "$(bash 'cw yolo local')" "after /cwtfigo:cwtfigo prompt"
echo "ok"
