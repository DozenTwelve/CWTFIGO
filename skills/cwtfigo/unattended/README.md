# Unattended check

**Frozen: this mode is kept but not supported for now.** For running approved scripts from a chat app, see [`HERMES.md`](../../../HERMES.md).

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
