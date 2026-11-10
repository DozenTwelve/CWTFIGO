#!/bin/sh
# Self-check for hooks/approve-gate.sh: once the plugin has started in a session, approvals ask; everything else,
# and every call in a session that never started it, stays silent. In normal mode cw's reads and record edits get allow.
# Usage: sh tests/approve-gate.sh, or SH=dash sh tests/approve-gate.sh to run the hook under dash (Debian's sh).
set -u
R=$(cd "$(dirname "$0")/.." && pwd); G=$R/hooks/approve-gate.sh; CW=$R/skills/cwtfigo/scripts/cw
fail() { echo "FAIL: $*"; exit 1; }
TMPDIR=$(mktemp -d) || exit 1; export TMPDIR; trap 'chmod -R u+w "$TMPDIR"; rm -rf "$TMPDIR"' EXIT
# The hook reads the mode from the record: a temp one, never the real ~/.cwtfigo.
HOME=$TMPDIR/home; REC=$TMPDIR/rec; export HOME CWTFIGO_HOME=$REC; mkdir -p "$HOME" "$REC/hosts/box"
# The marker dir: ~/.cache/cwtfigo-visit, also with XDG_RUNTIME_DIR set (Linux), where markers were kept before.
XDG_RUNTIME_DIR=$TMPDIR/run; export XDG_RUNTIME_DIR; V=$HOME/.cache/cwtfigo-visit
mkdir -p "$V" "$XDG_RUNTIME_DIR" && : > "$V/on"
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
# A session that went back to other work: another tool's apply, approve and yolo are not CWTFIGO's to ask about.
for c in 'git stash apply' 'kubectl apply -f k8s/' 'gh pr review 12 --approve' 'npm run test -- --grep yolo' 'terraform apply -auto-approve'; do
  [ -z "$(bash "$c")" ] || fail "$c should pass silently"
done
# With --apply as a flag, or cw as a word, a variable or the plugin's name in the command, they still ask.
for c in 'sh maintain.sh --apply' 'sh maintain.sh -\\-apply' 'A=--apply; sh x \"$A\"' 'A=apply; sh x --$A' 'cd ~/.cwtfigo/hosts/box && sh maintain.sh apply' \
         'sh /tmp/cw apply' 'sh /tmp/x/c\\w approve local y' 'sh $X approve local y' 'sh ~/.cwtfigo/x yolo' 'sh /tmp/CWTFIGO-copy approve local y' \
         'git stash apply; sh scripts/cw status' 'gh pr review $PR --approve'; do
  ask "$(bash "$c")" "$c"
done
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
# cw approve names the scripts and the machine, as the command does; the general line when it doesn't plainly.
why "$(bash "sh $CW approve box check")" "your yes lets check run on box from now on without asking again, until it changes\"" "cw approve"
why "$(bash "sh $CW approve local check maintain@0123456789ab && echo ok")" "your yes lets check, maintain run on this computer from now on without asking again, until one of them changes\"" "cw approve, several"
why "$(bash "sh \\\"$CW\\\" approve box probes")" "your yes lets the plugin's read-only checks run on box from now on" "cw approve probes"
why "$(bash "sh $CW approve box")" "your yes lets this run from now on" "cw approve with no script named"
why "$(hook '"tool_name":"Write","tool_input":{"file_path":"/u/.cwtfigo/hosts/box/approved.sha256","content":"x"}')" "your yes lets this run from now on" "Write approved.sha256"
why "$(bash "sh $CW yolo")" "your yes lets me run things you haven't seen" "cw yolo"
why "$(bash "sh $CW mode strict")" "your yes changes how often I ask" "cw mode strict"
why "$(bash 'rm -rf $TMPDIR/cwtfigo-visit')" "this needs your own yes" "the marker"
# In every mode, what changes a machine or who may change it asks each time: an allow rule, an earlier "don't ask
# again" or auto mode would let it through otherwise. The prompt says what changes.
for c in "sh $CW run local maintain --apply" "sh $CW run box maintain --app''ly trash" "sh scripts/cw run box fix --APPLY" \
         "cd $R/skills/cwtfigo && sh scripts/cw run local maintain --apply" "sh ~/.cwtfigo/hosts/box/maintain.sh --apply" \
         "sh $CW name box" "sh $CW name local2" "C=$CW; sh \$C name box" "sh scripts/c''w name x" "sh $CW join box:rec" "sh \$C join /srv/rec"; do
  ask "$(bash "$c")" "$c"
done
why "$(bash "sh $CW run box maintain --apply trash")" "this changes box (maintain --apply trash), this time only" "--apply"
why "$(bash "sh $CW run local maintain --apply")" "this changes this computer (maintain --apply), this time only" "--apply here"
why "$(bash "sh $CW run box maintain --apply; ls")" "this changes box (maintain --apply), this time only" "--apply, then ;"
why "$(bash "sh x --apply")" "this changes a computer (it runs with --apply), this time only" "--apply, not by cw run"
# Several machines in one command: the prompt must not name just one of them.
for c in "echo == a; sh $CW run a maintain --apply; echo == c; sh $CW run c maintain --apply" "sh $CW run a maintain --apply && sh $CW run c check"; do
  why "$(bash "$c")" "this changes a computer (it runs with --apply), this time only\"" "--apply on more than one machine"
done
why "$(bash "sh $CW name box")" "this calls this computer box in your notes" "cw name"
why "$(bash "sh $CW join nas:cwtfigo.git")" "this shares your notes with nas:cwtfigo.git\." "cw join"
bash "sh $CW run local hostname" | grep -q '"ask"' && fail "name inside a word, in a run without apply, should not ask"
[ -z "$(bash 'git log --format=%an')" ] || fail "name inside a word should pass silently"

# The PowerShell tool (Windows): the same asks as Bash, also with its own escape character, the backtick. Never allow.
grep -q '"matcher": *"[^"]*PowerShell' "$R/hooks/hooks.json" || fail "hooks.json should match the PowerShell tool"
pwsh() { hook "$(printf '"tool_name":"PowerShell","tool_input":{"command":"%s"}' "$1")"; }
for c in "sh $CW approve box check" 'sh scripts/cw yolo' "sh $CW mode strict" "sh $CW run box maintain --apply" "sh $CW name box" \
         "sh $CW join nas:rec" 'sh scripts/cw appr`ove local x' 'sh scripts/cw yo`lo' 'sh scripts/cw run box fix --app`ly' 'sh scripts/cw mo`de strict' \
         'Add-Content $HOME/.cwtfigo/hosts/box/approved.sha256 abc' 'Remove-Item -Recurse $HOME/.cache/cwtfigo-visit'; do
  ask "$(pwsh "$c")" "PowerShell: $c"
done
why "$(pwsh "sh $CW approve box check")" "your yes lets check run on box from now on" "PowerShell, cw approve"
why "$(pwsh "sh $CW run box maintain --apply")" "this changes box (maintain --apply), this time only" "PowerShell, --apply"
for c in 'Get-ChildItem' "sh $CW status" "sh $CW run local logs" "sh $CW save \\\"x\\\"" "sh $CW yolo off"; do
  [ -z "$(pwsh "$c")" ] || fail "PowerShell: $c should pass silently (no ask, and never allow)"
done

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
# Quotes pair as the shell pairs them. An apostrophe inside "" is a letter there, not the start of a '' string: a
# backtick or $( ) between two of them is live, and the shell would run it. In every form that can get allow.
M=$TMPDIR/M
for c in "save \\\"didn't need \`touch $M\`, user's call\\\"" "search \\\"it's \$(touch $M) user's\\\"" "miss \\\"didn't \`touch $M\` user's\\\"" \
         "status \\\"it's\\\" \`touch $M\` \\\"user's\\\"" "save \\\"it's \$HOME, user's\\\"" "save \\\"it's a\\\\\\\\b, user's\\\""; do
  nallow "$(bash "sh $CW $c")" "sh cw $c"
  nallow "$(bash "sh \\\"$CW\\\" $c")" "sh \"cw\" $c"
  nallow "$(bcwd /tmp "cd $D && sh scripts/cw $c")" "cd && sh scripts/cw $c"
  nallow "$(bcwd "$D" "sh scripts/cw $c")" "cwd skills/cwtfigo: sh scripts/cw $c"
done
# A quote with no partner: the shell would read on past the end of the command.
for c in "save didn't" "save \\\"didn't \`touch $M\`\\\"" "save \\\"a" "save 'a" "save \\\"a\\\" 'b" "save 'a' \\\"b" "save \\\"it's\\\" 'a" \
         "save 'it\\\"s' \$(touch $M) 'x\\\"y'" "save 'a\\\"' \\\"\$(touch $M)\\\"" "run local logs \\\"a" "run local logs 'a"; do
  nallow "$(bash "sh $CW $c")" "sh cw $c"
done
# A # that starts a word outside quotes is a comment to the end of the line: the ' after it opens nothing, and the
# line after the newline "inside" it is a command.
for c in "status # 'x\\ntouch $M #'" "save 'a' #'b\\ntouch $M #'" "save a # b" "status #" "run local logs #x"; do
  nallow "$(bash "sh $CW $c")" "sh cw $c"
  nallow "$(bcwd "$D" "sh scripts/cw $c")" "cwd skills/cwtfigo: sh scripts/cw $c"
done
for c in "save a#b" "save '#6 done'" "save \\\"# done\\\"" "save 'two\\nlines'"; do allow "$(bash "sh $CW $c")" "sh cw $c"; done
# Still allowed: an apostrophe inside "" with nothing live, and inside '' anything, as the shell reads nothing there.
for c in "save \\\"didn't need it, user's call\\\"" "save \\\"it's\\\" \\\"user's\\\"" "save 'costs \$5, see \`man x\` and \$(id)'" "save 'a\\\\\\\\b'" \
         "search 'a' \\\"b's\\\" 'c\\\"d' \\\"(e)\\\"" "run local net \\\"eth0\\\" 'x'"; do
  allow "$(bash "sh $CW $c")" "sh cw $c"
done
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
# Other spellings of the same file. approved.sha256/. and yolo.on/ are the file itself to Write; on Windows so are a
# trailing dot or space and ::$DATA. With the name in the path: ask, whatever follows. Other files in the record
# spelled that way (mode. is mode there), or by a short name (APPROV~1.SHA): no allow.
for f in "$REC/hosts/box/approved.sha256/." "$REC/hosts/box/yolo.on/" "$REC/yolo.on/." "$REC/hosts/box/approved.sha256." \
         "$REC/hosts/box/approved.sha256::\$DATA" "$REC/hosts/box/APPROVED.SHA256 " "$REC/hosts/box/yolo.on.bak" \
         "/u/a\\\\\\\"b/.cwtfigo/hosts/box/approved.sha256" "C:\\\\\\\\Users\\\\\\\\u\\\\\\\\.cwtfigo\\\\\\\\yolo.on."; do
  ask "$(w Write "$f")" "Write $f"; ask "$(w Edit "$f")" "Edit $f"
done
for f in "$REC/mode." "$REC/mode " "$REC/self." "$REC/mode::\$DATA" "$REC/hosts/box./notes.md" "$REC/hosts/box /notes.md" \
         "$REC/hosts/box/notes.md." "$REC/hosts/box/notes.md::\$DATA" "$REC/hosts/box/APPROV~1.SHA" "$REC/.gitignore."; do
  nallow "$(w Write "$f")" "Write $f"
done
# The record's mode and self files are what cw mode <level> and cw name write: a Write/Edit of one asks like those,
# and says what the yes is for. In the record only; a mode file somewhere else is somebody else's.
for f in "$REC/mode" "$REC/MODE" "$REC/mode." "$REC/mode/." "$REC/mode::\$DATA" "$REC//mode" "/home/u/.cwtfigo/mode" \
         "C:\\\\Users\\\\u\\\\.CWTFIGO\\\\mode" "C:/Users/u/.cwtfigo/mode "; do
  why "$(w Write "$f")" "your yes changes how often I ask" "Write $f"; why "$(w Edit "$f")" "your yes changes how often I ask" "Edit $f"
done
for f in "$REC/self" "$REC/Self" "$REC/self." "$REC/self/" "$REC/self::\$DATA" "/home/u/.cwtfigo/self" "C:\\\\Users\\\\u\\\\.cwtfigo\\\\self"; do
  why "$(w Write "$f")" "this calls this computer by a new name in your notes" "Write $f"
  why "$(w Edit "$f")" "this calls this computer by a new name in your notes" "Edit $f"
done
for f in "$TMPDIR/elsewhere/mode" "/r/src/self" "/r/.cwtfigo-x/mode" "$REC/hosts/box/mode" "$REC/hosts/box/self"; do
  [ -z "$(w Write "$f")" ] || fail "Write $f should pass silently"
done
allow "$(w Write "$REC/hosts/box/modem.md")" "Write modem.md"; allow "$(w Write "$REC/selfhosted.md")" "Write selfhosted.md"
# A Mac folds U+017F (long s) to s: approved.ſha256 and ſelf are approved.sha256 and self there.
for f in "$REC/hosts/box/approved.ſha256" "$REC/ſelf" "$REC/hosts/box/nötes.md"; do nallow "$(w Write "$f")" "Write $f, not ASCII"; done
ln -s "$TMPDIR/home" "$REC/hosts/ln"; nallow "$(w Write "$REC/hosts/ln/.bashrc")" "Write through a symlink out of the record"
nallow "$(hook "$(printf '"tool_name":"NotebookEdit","tool_input":{"file_path":"%s"}' "$REC/hosts/box/notes.md")")" "another tool"
mkdir -p "$HOME/.cwtfigo"; allow "$(CWTFIGO_HOME= hook "$(printf '"tool_name":"Write","tool_input":{"file_path":"%s"}' "$HOME/.cwtfigo/notes.md")")" "the record at ~/.cwtfigo"
# Strict: no allow at all, the asks stay.
echo strict > "$REC/mode"
nallow "$(bash "sh $CW status")" "strict mode, cw status"
nallow "$(w Write "$REC/hosts/box/notes.md")" "strict mode, Write notes.md"
# Strict promises a prompt for every step: every cw call and every edit of the record asks, not just goes unallowed.
for c in "sh $CW status" "sh $CW yolo off" "sh $CW save \\\"x\\\"" "cd $R/skills/cwtfigo && sh scripts/cw search wifi"; do
  why "$(bash "$c")" "strict mode: you asked me to check with you before every step" "strict mode, $c"
done
why "$(bash "sh $CW run local maintain --apply")" "this changes this computer" "strict mode, --apply"
why "$(pwsh "sh $CW status")" "strict mode: you asked me to check with you before every step" "strict mode, PowerShell"
for f in "$REC/hosts/box/notes.md" "$REC/operator.md" "$(echo "$REC" | tr 'a-z' 'A-Z')/x.md" "/home/u/.cwtfigo/hosts/box/fix.sh" "C:\\\\\\\\Users\\\\\\\\u\\\\\\\\.cwtfigo\\\\\\\\x.md"; do
  why "$(w Write "$f")" "this changes your notes, and in strict mode" "strict mode, Write $f"
  why "$(w Edit "$f")" "this changes your notes, and in strict mode" "strict mode, Edit $f"
done
[ -z "$(bash 'ls')" ] && [ -z "$(w Write "$TMPDIR/elsewhere/notes.md")" ] || fail "strict mode: what isn't cw or the record takes Claude Code's own path"
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
[ -e "$V/a" ] && [ ! -e "$XDG_RUNTIME_DIR/cwtfigo-visit" ] || fail "the marker belongs in ~/.cache/cwtfigo-visit, not under XDG_RUNTIME_DIR (gone at logout)"
S=b
[ -z "$(bash 'cw approve local x')" ] || fail "other session should stay silent"
# The skill's name the way a model may write it: with a slash, with spaces. Another skill's name still doesn't start.
for n in '/cwtfigo:cwtfigo' '/cwtfigo' ' cwtfigo ' ' /cwtfigo:cwtfigo'; do
  S=n$(printf '%s' "$n" | cksum | cut -d' ' -f1); [ -z "$(bash 'cw approve local x')" ] || fail "before Skill '$n' should pass silently"
  hook "$(printf '"tool_name":"Skill","tool_input":{"skill":"%s"}' "$n")" >/dev/null; ask "$(bash 'cw approve local x')" "after Skill '$n'"
done
S=n0; for n in '/cwtfigox' 'x/cwtfigo' 'cwtfigo:other' '//cwtfigo'; do hook "$(printf '"tool_name":"Skill","tool_input":{"skill":"%s"}' "$n")" >/dev/null; done
[ -z "$(bash 'cw approve local x')" ] || fail "another skill's name shouldn't start"
S=c
up() { hook "$(printf '"hook_event_name":"UserPromptSubmit","prompt":"%s"' "$1")"; }
[ -z "$(up 'what is /cwtfigo for')" ] && [ -z "$(up '/cwtfigox')" ] || fail "prompt not starting with /cwtfigo should print nothing"
[ -z "$(bash 'cw approve local x')" ] || fail "prompt not starting with /cwtfigo shouldn't start"
[ -z "$(up '/cwtfigo my mac is hot')" ] || fail "UserPromptSubmit should print nothing"
ask "$(bash 'cw approve local x')" "after /cwtfigo prompt"
S=d; up '/cwtfigo:cwtfigo' >/dev/null
ask "$(bash 'cw yolo local')" "after /cwtfigo:cwtfigo prompt"
# A marker where they were kept before, under XDG_RUNTIME_DIR: a session started before the update stays gated.
S=old; [ -z "$(bash 'cw approve local x')" ] || fail "no marker in either place should pass silently"
mkdir "$XDG_RUNTIME_DIR/cwtfigo-visit" && : > "$XDG_RUNTIME_DIR/cwtfigo-visit/old"
ask "$(bash 'cw approve local x')" "a marker in the old place"
# No marker, but the session's transcript holds a Skill call of cwtfigo or a /cwtfigo prompt, as Claude Code records
# them (a fork carries the old session's history under a new session_id; a marker got deleted): started.
tp() { hook "$(printf '"transcript_path":"%s","tool_name":"Bash","tool_input":{"command":"cw approve local x"}' "$1")"; }
J=$TMPDIR/t; mkdir "$J"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"my mac is hot, CWTFIGO"}}' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_01","name":"Skill","input":{"skill":"cwtfigo:cwtfigo"},"caller":{"type":"direct"}}]}}' > "$J/skill.jsonl"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"<command-message>cwtfigo:cwtfigo</command-message>\n<command-name>/cwtfigo:cwtfigo</command-name>\n<command-args>slow</command-args>"}}' > "$J/prompt.jsonl"
# Only mentions of it: in a tool's output and in a message the quotes are escaped. And another skill's real call.
printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"{\"type\":\"tool_use\",\"name\":\"Skill\",\"input\":{\"skill\":\"cwtfigo:cwtfigo\"}} \"content\":\"<command-message>cwtfigo"}]}}' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_02","name":"Skill","input":{"skill":"caveman:caveman"}}]}}' > "$J/mention.jsonl"
S=t1; ask "$(tp "$J/skill.jsonl")" "transcript with a Skill call of cwtfigo"
[ -e "$V/t1" ] || fail "a session started by its transcript should get its marker"
S=t2; ask "$(tp "$J/prompt.jsonl")" "transcript with a /cwtfigo prompt"
S=t3; [ -z "$(tp "$J/mention.jsonl")" ] || fail "a transcript that only mentions the skill should pass silently"
[ -e "$V/t3.no" ] && [ ! -e "$V/t3" ] || fail "a transcript read and found without the skill should leave t3.no"
# Read once per session: a long transcript is not read again on every call. A Skill call still starts the session.
cat "$J/skill.jsonl" >> "$J/mention.jsonl"; [ -z "$(tp "$J/mention.jsonl")" ] || fail "the transcript should be read once per session"
hook '"tool_name":"Skill","tool_input":{"skill":"cwtfigo:cwtfigo"}' >/dev/null; ask "$(tp "$J/mention.jsonl")" "after Skill, with a .no file"
S=t4; [ -z "$(tp "$J/none.jsonl")" ] && [ -z "$(bash 'cw approve local x')" ] && [ ! -e "$V/t4.no" ] || fail "no transcript to read: silent, and no .no"
cp "$J/skill.jsonl" "$J/none.jsonl"; ask "$(tp "$J/none.jsonl")" "the transcript is there on a later call"
# .no files older than 30 days are cleared when a new one is written; markers stay.
touch -t 202001010000 "$V/t3.no" "$V/t1"; S=t5; tp "$J/mention.jsonl" >/dev/null; S=t6; : > "$J/empty.jsonl"; tp "$J/empty.jsonl" >/dev/null
[ ! -e "$V/t3.no" ] && [ -e "$V/t6.no" ] && [ -e "$V/t1" ] || fail "old .no files should be cleared, markers and new .no files kept"
# A marker dir this user can't write (another user's dir, a read-only disk): fail closed, never off, and quiet.
H=$HOME; mkdir -p "$TMPDIR/ro/.cache/cwtfigo-visit" "$TMPDIR/ro2/.cache"; chmod 555 "$TMPDIR/ro/.cache/cwtfigo-visit" "$TMPDIR/ro2/.cache"
S=e; HOME=$TMPDIR/ro
o=$(up '/cwtfigo my mac is hot' 2>&1) && [ -z "$o" ] || fail "unwritable marker dir: UserPromptSubmit should exit 0 and print nothing: $o"
ask "$(bash 'cw approve local x')" "unwritable marker dir, after /cwtfigo prompt"
S=f; ask "$(bash 'cw approve local x')" "unwritable marker dir, never started"
ask "$(tp "$J/mention.jsonl")" "unwritable marker dir, never started, with a transcript"
HOME=$TMPDIR/ro2; ask "$(bash 'cw approve local x')" "marker dir can't be made"
HOME=; ask "$(bash 'cw approve local x')" "no HOME"
HOME=$H
# No XDG_RUNTIME_DIR (macOS): the same dir, only the user's.
unset XDG_RUNTIME_DIR; S=g; HOME=$TMPDIR/home2; mkdir "$HOME"; V=$HOME/.cache/cwtfigo-visit
[ -z "$(bash 'cw approve local x')" ] || fail "no XDG_RUNTIME_DIR, not started, should pass silently"
up '/cwtfigo' >/dev/null; ask "$(bash 'cw approve local x')" "no XDG_RUNTIME_DIR, after /cwtfigo prompt"
[ -e "$V/g" ] && [ "$(ls -ld "$V" | cut -c1-10)" = drwx------ ] || fail "marker should be in ~/.cache/cwtfigo-visit, mode 700"
echo "ok"
