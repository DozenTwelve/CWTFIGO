#!/bin/sh
# Approval gate. It only applies once the plugin has started in this session: changing the plugin and using it are
# different things. Before that (working on the plugin, running its tests, a contributor's PR) nothing here asks.
# Started = this session called the cwtfigo skill: a Skill call (PreToolUse, tool_input {"skill":"cwtfigo:cwtfigo"})
# or a prompt beginning /cwtfigo or /cwtfigo:cwtfigo (UserPromptSubmit). Either one leaves a marker file
# ${XDG_RUNTIME_DIR:-~/.cache}/cwtfigo-visit/<session_id>, the user's own (not /tmp, which every user on a Linux box
# shares: whoever made it first would own it). No session_id in stdin, or a marker dir this user can't write: treated
# as started (fail closed).
# Residual risk, accepted by the owner: in a session that never started the plugin, the model can write approved.sha256
# directly without being asked.
#
# Once started, PreToolUse (Bash, Write, Edit): approval is the human's. A call that looks like it approves a script
# (`cw approve`, approved.sha256), turns on YOLO (`cw yolo`, yolo.on, which skips approval for a visit) or touches the
# marker (cwtfigo-visit, which switches the gate off) goes to a permission prompt, and so does `cw mode <anything>` (plain
# `cw mode` only prints it). These asks come first and win over the allow below.
# Then the mode, $REC/mode (REC: CWTFIGO_HOME, else ~/.cwtfigo; cw mode writes it). strict (a mode file that doesn't
# say normal, any case and spaces aside): everything else gets no output and takes Claude Code's normal permission
# path. normal (no file, or normal): what can't change a machine without an approval cw itself checks gets "allow",
# so a first visit isn't one prompt per step:
# - Bash whose whole command is `sh <cw> <status|run|save|search|miss> [args]` or `sh <cw> yolo off`. <cw> is this
#   plugin's own, skills/cwtfigo/scripts/cw under the dir this hook sits in (another file of that name could be
#   anything), bare or in "" or ''; in Git Bash on Windows also as C:/... (cygpath), as Claude Code shows the dir there.
#   Or scripts/cw, the same way, when the shell is in this plugin's skills/cwtfigo: the input's cwd is that dir, or the
#   command is exactly `cd <that dir> && sh scripts/cw ...` (the dir absolute, bare or quoted, one && and nothing
#   else). Dirs compared by cd and pwd -P, as the shell's own cd would land. The command holds nothing but letters,
#   digits, spaces, quotes, _ . / , : @ % + = ~ # - and non-ASCII (a save message in the owner's language), the cd
#   prefix's && aside: no ; & | ` $ ( ) < > \ newline, glob or brace, so no variable. Except inside quotes, for save,
#   search and miss: there anything but ` $ \ and the closing quote (an error string, a message with "(...)!"), as the
#   shell reads nothing else inside them. run only without "apply" anywhere in its args, quotes taken out (--app''ly
#   is --apply): --apply changes the machine, and that is the owner's OK moment. SKILL makes every script that changes
#   a machine a dry run without --apply, like maintain, so a rerun of an approved fix only shows what it would do. And
#   only with a script name, unquoted, no / or ~ in it: given a path, cw would show that file.
# - Write/Edit of a file in the record, but not approved.sha256, yolo.on, mode, self or .git* anywhere in it (any case),
#   no . .. or // in the path, nothing but ASCII (a Mac folds U+017F, the long s, to s: approved.sha256 spelled with
#   it is the same file) and no symlink on the way (Write follows one out of the record). A host script written there
#   still can't run until approved: cw checks its hash, on a private copy it then runs, so rewriting the file while it
#   runs changes nothing. Except under YOLO, when cw runs it unapproved: while any yolo.on exists, a .sh or .ps1 there
#   gets no allow.
# The rest gets no output. YOLO (cw yolo) is the third level: cw's, not this hook's.
# What it is: a string match that stops the model approving by habit or by mistake. What it is not: a wall. A model set
# on getting around it can: build the words at run time (eval, base64, printf), write a script with Write and run it
# (Write content isn't read), use a glob or a copy of the host dir it doesn't name, or clear the marker dir as a whole.
# Limits of the allow itself, known: an approved script's args aren't hashed (wifi --test runs as freely as wifi); a
# host script edited between the run that showed it and a cw approve by plain name is approved as edited (cw approve
# <alias> <script>@<hash start>, as run prints it, refuses that); and cw run and cw status pull the shared record
# first, so whoever can push to it is trusted as the owner: a script and its hash pushed there run here unasked.
# Matches the raw stdin JSON, no jq: a false positive costs one extra prompt. Bash: the whole command (cwd and
# transcript_path are dropped first, a checkout path may hold cwtfigo-visit); [^a-z]* lets quotes and extra spaces
# through: cw" approve, cw  approve. Also asked: cw with a variable for its subcommand (cw ${X}ove), a variable just
# before approve or yolo ($C approve), and the file names in a glob (approved.sha25?, yolo.*, cwtfigo-v*).
# Write/Edit: only the file_path, so editing a file that merely mentions them doesn't ask.
# -i: macOS and Windows filesystems ignore case. `cw yolo off` only takes a switch away, so it passes (and in normal
# mode gets allow): the model turns YOLO off when the work is done, with nobody there to answer a prompt. Only as whole
# words: spaces between yolo and off (`cw yolo "" off` is YOLO on), then a space, ; & | ), the end of the command or a
# newline after off.
in=$(cat)
d=${XDG_RUNTIME_DIR:-$HOME/.cache}/cwtfigo-visit
sid=$(printf '%s' "$in" | sed -nE 's/.*"session_id" *: *"([^"]*)".*/\1/p' | head -n 1 | tr -cd 'A-Za-z0-9_-')
# Quiet on failure: a UserPromptSubmit hook's error lands in the owner's prompt. A marker it couldn't write leaves the
# gate on: below, a dir it can't write counts as started. (true, not :, whose failed redirect ends dash.)
mkd() { (umask 077; mkdir -p "$d") 2>/dev/null && [ -w "$d" ]; }
mark() { [ -n "$sid" ] && mkd && { true > "$d/$sid"; } 2>/dev/null; exit 0; }
if printf '%s' "$in" | grep -Eq '"hook_event_name" *: *"UserPromptSubmit"'; then
  printf '%s' "$in" | grep -Eiq '"prompt" *: *"[[:space:]]*/cwtfigo(:cwtfigo)?([" \\]|$)' && mark
  exit 0
fi
if printf '%s' "$in" | grep -Eq '"tool_name" *: *"Skill"'; then
  printf '%s' "$in" | grep -Eq '"skill" *: *"(cwtfigo:)?cwtfigo"' && mark
  exit 0
fi
[ -n "$sid" ] && [ ! -e "$d/$sid" ] && mkd && exit 0
# The command as typed, still JSON-escaped (\" for ", \n for a newline).
cmd=$(printf '%s' "$in" | sed -nE 's/.*"command" *: *"(([^"\\]|\\.)*)".*/\1/p' | head -n 1)
if printf '%s' "$in" | grep -Eq '"tool_name" *: *"Bash"'; then
  printf '%s' "$in" | sed -E 's/"(cwd|transcript_path)" *: *"[^"]*"//g' | tr 'A-Z' 'a-z' \
    | sed -E 's/cw[^a-z]*yolo[[:space:]]+off([[:space:];&|)"]|\\n|$)/\1/g' \
    | grep -Eq 'cw[^a-z]*(approve|yolo|[$`])|\$[{a-z_][a-z0-9_}]*[^a-z]*(approve|yolo)|approved(\.sha|\.?[?*[])|yolo\.|yolo[?*[]|cwtfigo(-v|-?[?*[])' || {
    # cw's name hidden from the match above (c''w, c\w, a copy under another name): approve or yolo as a whole word in
    # the command asks too, a plain yolo off aside. Only the command, not its description ("Switch off YOLO"), else
    # the model turning YOLO off with nobody there would stop at a prompt. JSON's \n and \t are spaces here. Quotes
    # and backslashes go after that, as the shell drops them: appr''ove and approv\e are approve.
    printf '%s' "${cmd:-$in}" | tr 'A-Z' 'a-z' | sed -E 's/\\[nt]/ /g; s/(^|[^a-z0-9_])yolo[[:space:]]+off([[:space:];&|)"]|$)/\1\2/g' \
      | tr -d "'\"\\\\" | grep -Eq '(^|[^a-z0-9_])(approve|yolo)([^a-z0-9_]|$)'
  } || printf '%s' "$cmd" | tr 'A-Z' 'a-z' | tr -d "'\"\\\\" | grep -Eq 'cw[^a-z]*mode[[:space:]]*[^[:space:]]'
else
  printf '%s' "$in" | grep -Eiq '"file_path" *: *"[^"]*((approved\.sha256|yolo\.on)"|cwtfigo-visit)'
fi && {
  # What the yes is for, in the owner's words: the prompt is the question, and a newcomer reads it.
  t=${cmd:-$(printf '%s' "$in" | sed -nE 's/.*"file_path" *: *"([^"]*)".*/\1/p')}
  case $(printf '%s' "$t" | tr 'A-Z' 'a-z' | tr -d "'\"\\\\") in
    *approve*) r="CWTFIGO: your yes lets this run from now on without asking again, until it changes" ;;
    *yolo*) r="CWTFIGO: your yes lets me run things you haven't seen without asking, for 12 hours or until you turn it off" ;;
    *mode*) r="CWTFIGO: your yes changes how often I ask you before doing things on this computer" ;;
    *) r="CWTFIGO: this needs your own yes: it changes what I may do without asking you" ;;
  esac
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$r"
  exit 0; }
REC=${CWTFIGO_HOME:-$HOME/.cwtfigo}
# Strict unless there is no mode file or it says normal: a hand-edited Strict, or strict with a CR, must not fail open.
[ -e "$REC/mode" ] && [ "$(tr -d ' \t\r\n' 2>/dev/null < "$REC/mode" | tr 'A-Z' 'a-z')" != normal ] && exit 0
safe() { printf '%s' "$1" | LC_ALL=C tr -d '\200-\377' | LC_ALL=C grep -Eq "^[A-Za-z0-9 _./,:@%+=~#'\"-]*\$"; }
# safe, with its quoted strings taken out first: inside '' the shell reads nothing but the closing ', inside "" only
# $ ` \ and the closing ", so "fixed wifi (iwlwifi)!" is as plain as fixed wifi. Left to right, as the shell pairs
# them: the leftmost match is where the shell's own quote opens. One it can't pair stays and is checked as by safe.
qsafe() { safe "$(printf '%s' "$1" | sed -E "s/'[^']*'|\"[^\"\$\`\\\\]*\"//g")"; }
# The physical dir an absolute path lands in, by the shell's own (logical) cd. Git Bash on Windows: C:/... or C:\...
# as Claude Code shows it, by cygpath (only Git Bash has it).
phys() (
  p=$1; case $p in [A-Za-z]:[/\\]*) command -v cygpath >/dev/null && p=$(cygpath -u "$p") ;; esac
  case $p in /*) CDPATH= cd "$p" 2>/dev/null && pwd -P ;; esac
)
cwok() {
  c=$(printf '%s' "$cmd" | sed 's/\\"/"/g')
  D=$(phys "$(cd "$(dirname "$0")/.." && pwd)/skills/cwtfigo") && [ -n "$D" ] || return 1
  here=   # the shell runs in this plugin's skills/cwtfigo: scripts/cw is its cw
  case $c in
    "cd "*" && "*)
      d=${c#cd }; d=${d%% && *}; c=${c#*" && "}; c=${c#"${c%%[! ]*}"}
      d=${d#"${d%%[! ]*}"}; d=${d%"${d##*[! ]}"}
      safe "$d" || return 1
      case $d in \"*\") d=${d#\"}; d=${d%\"} ;; \'*\') d=${d#\'}; d=${d%\'} ;; *' '*) return 1 ;; esac
      case $d in *[\"\']*) return 1 ;; esac
      [ "$(phys "$d")" = "$D" ] || return 1; here=1 ;;
    *) w=$(printf '%s' "$in" | sed -nE 's/.*"cwd" *: *"(([^"\\]|\\.)*)".*/\1/p' | head -n 1 | sed 's/\\\\/\\/g')
       [ "$(phys "$w")" = "$D" ] && here=1 ;;
  esac
  qsafe "$c" || return 1
  P=$(cd "$(dirname "$0")/.." && pwd)/skills/cwtfigo/scripts/cw
  case $P in *[\"\'\\]*) return 1 ;; esac
  r=${c#sh }; [ "$r" != "$c" ] || return 1
  r=${r#"${r%%[! ]*}"}
  # Git Bash: cw as C:/Users/..., the way Claude Code shows the skill's dir there, is the same cw. (C:\Users\...
  # isn't: a backslash fails safe above.)
  M=; command -v cygpath >/dev/null && M=$(cygpath -m "$P")
  case $M in ''|*[\"\'\\]*) ;; *)
    case $r in
      "$M "*) r="$P ${r#"$M "}" ;;
      "\"$M\" "*) r="\"$P\" ${r#"\"$M\" "}" ;;
      "'$M' "*) r="'$P' ${r#"'$M' "}" ;;
    esac ;;
  esac
  case $r in
    "\"$P\" "*) a=${r#"\"$P\" "} ;;
    "'$P' "*) a=${r#"'$P' "} ;;
    "$P "*) case $P in *' '*) return 1 ;; esac; a=${r#"$P "} ;;
    "scripts/cw "*|"\"scripts/cw\" "*|"'scripts/cw' "*) [ -n "$here" ] || return 1; a=${r#*cw}; a=${a#[\"\']} ;;
    *) return 1 ;;
  esac
  a=${a#"${a%%[! ]*}"}
  case ${a%% *} in
    # Not name: naming this machine after another host would run that host's approved scripts here.
    status|save|search|miss) ;;
    # Only takes a switch away, and nobody may be there to answer a prompt.
    yolo) [ "$a" = "yolo off" ] ;;
    # The script by name, never a path: cw prints an unapproved file, and ~/.ssh/id_ed25519 is a file too.
    # Its args go to a script, not to cw: safe as before, quoted or not.
    run) safe "$c" && case $(printf '%s' "$a" | awk '{ print $3 }') in ''|*[/~\"\']*) false ;; *) ! printf '%s' "$a" | tr -d "'\"" | grep -iq apply ;; esac ;;
    *) false ;;
  esac
}
pathok() (
  f=$(printf '%s' "$in" | sed -nE 's/.*"file_path" *: *"(([^"\\]|\\.)*)".*/\1/p' | head -n 1)
  case $f in "$REC"/*) ;; *) exit 1 ;; esac
  # ASCII only: a Mac's filesystem folds case beyond ASCII (approved.sha256 with a long s, U+017F, is the same file).
  printf '%s' "$f" | LC_ALL=C grep -q '[^ -~]' && exit 1
  r=${f#"$REC"/}
  case /$r/ in *\\*|*//*|*/./*|*/../*) exit 1 ;; esac
  case $(printf '%s' "/$r" | tr 'A-Z' 'a-z') in */.git*|*/approved.sha256|*/yolo.on|*/mode|*/self) exit 1 ;; esac
  # Under YOLO cw runs a script it has never seen: written then, it takes Claude Code's own prompt.
  case $(printf '%s' "$r" | tr 'A-Z' 'a-z') in *.sh|*.ps1)
    for y in "$REC/yolo.on" "$REC"/hosts/*/yolo.on; do [ -e "$y" ] && exit 1; done ;;
  esac
  set -f; IFS=/; p=$REC
  for c in $r; do p=$p/$c; [ -L "$p" ] && exit 1; done
  exit 0
)
if printf '%s' "$in" | grep -Eq '"tool_name" *: *"Bash"'; then cwok
elif printf '%s' "$in" | grep -Eq '"tool_name" *: *"(Write|Edit)"'; then pathok
else false; fi || exit 0
cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"CWTFIGO normal mode: a read, a dry run or a note; changing a machine takes --apply or a new yes, and those ask"}}
JSON
