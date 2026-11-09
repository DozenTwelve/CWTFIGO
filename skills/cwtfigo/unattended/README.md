# Unattended check

`../scripts/unattended.sh` once a day on an always-on operator machine (a home server, a NAS). For each host in the record whose `check` the owner approved at least once, it runs `cw run <host> check` and, if `maintain` was approved, the `maintain` dry run. Hosts that don't answer SSH within 5 s are skipped as offline. WARN/BAD lines, scripts waiting for approval (new or changed since approval) and failures make a report. A clean day ends there: no model call, no message, nothing written to `log.md`.

When there is something, the report is printed (journal), prepended to each affected host's `log.md` as `## <date> unattended` and committed (after a pull, those `log.md` files alone: a visit going on at the same time keeps its own changes) and pushed, summarized by Haiku with no tools (text in, text out; the plain report is sent instead if that fails) and posted to Discord.

It never approves anything, never runs under YOLO (a fresh `yolo.on` anywhere and it refuses, exit 2), never runs `maintain --apply`, and never runs anything `cw run` wouldn't run without a human. No prompt can block it: ssh runs with BatchMode, stdin is `/dev/null`, so sudo can't ask for a password.

## Install on the always-on box

The record must already be on the box (`cw join` done, or its own record, `cw name` done) and its git must be able to commit and push without a prompt.

```sh
mkdir -p ~/.config/cwtfigo ~/.config/systemd/user ~/.local/share/cwtfigo
ln -sfn <plugin root, the dir that holds skills/> ~/.local/share/cwtfigo/plugin   # re-point after a plugin update if the path changes
cp <plugin root>/skills/cwtfigo/unattended/cwtfigo-unattended.* ~/.config/systemd/user/
(umask 077; printf '%s\n' 'https://discord.com/api/webhooks/...' > ~/.config/cwtfigo/discord-webhook
            printf 'ANTHROPIC_API_KEY=%s\n' 'sk-ant-...' > ~/.config/cwtfigo/env)
systemctl --user daemon-reload
loginctl enable-linger "$USER"                           # user timers run without a login session
systemctl --user enable --now cwtfigo-unattended.timer
```

SSH from the box to each host must work without a passphrase prompt (a key without passphrase, or `SSH_AUTH_SOCK=...` in the env file). Sudo in `check.sh` gets no password: give fixed commands NOPASSWD in sudoers, or keep them out.

## Test by hand

```sh
systemctl --user start cwtfigo-unattended.service; journalctl --user -u cwtfigo-unattended -n 50
CWTFIGO_NOTIFY=/nonexistent sh ~/.local/share/cwtfigo/plugin/skills/cwtfigo/scripts/unattended.sh </dev/null   # report to stdout, no model, no post
cat ~/.cwtfigo/unattended.last      # last run: time and outcome; a stale date means the timer is dead
systemctl --user list-timers cwtfigo-unattended.timer
```

Run by hand from a terminal, a local script's sudo can still prompt on that terminal; under systemd there is none.

## Hermes on the always-on box

[Hermes](https://github.com/NousResearch/hermes-agent) on the same box can run the owner's approved menu scripts from chat (Discord), without Claude Code. `cw hermes` writes one Hermes skill per script the TUI would show (check, maintain, `# menu:` scripts) that is approved as it is now, into `~/.local/share/cwtfigo/hermes/cwtfigo/`, and rebuilds that dir whole each time: a script approved in a later visit gets a skill, one removed or changed since loses it.

Record, plugin link and SSH as above (on the box: `sh ~/.local/share/cwtfigo/plugin/skills/cwtfigo/scripts/cw join <ssh-alias>:<path>`, then `cw name <the box's own alias>`), then:

```sh
CW=~/.local/share/cwtfigo/plugin/skills/cwtfigo/scripts/cw
sh $CW hermes                                   # first build, and the hook; says what to add if Hermes doesn't read the dir yet
# ~/.hermes/config.yaml:  skills:  external_dirs: [~/.local/share/cwtfigo/hermes]
hermes gateway restart                          # once: Hermes loads the hook when it starts
```

It also writes a Hermes hook, `~/.hermes/hooks/cwtfigo/`, so nothing needs a timer. The hook follows the dir Hermes reads: `cw hermes <dir>` moves it only to a dir `config.yaml` lists, so a build elsewhere (a preview) leaves it as it was. Before Hermes answers a message, the hook asks the shared record (wherever it lives: GitHub, a NAS, a bare repo on the box) whether a visit saved something new. If so, it rebuilds the skills and Hermes rescans them, so the first message after a visit's approval already sees the new skill. Nothing new costs a moment; a record it can't reach costs a few seconds, then it doesn't try again for 5 minutes.

The `/skill cw-<machine>-<script>` list in Discord is the one thing the hook can't refresh: after a change, `/reload-skills` updates it.

Trust: `cw approve` is gated only by Claude Code's hook, so here the boundary is who may talk to Hermes plus the rules in each generated skill (never approve, never `--apply` without an explicit yes, never run anything else). The hash gate still holds: Hermes can run only scripts the owner approved, as they were approved.
