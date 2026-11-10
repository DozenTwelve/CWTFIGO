# Security

CWTFIGO runs scripts on your machines and keeps a record of them. A hole in it is a hole in every machine it manages.

## What counts

- Anything that runs or approves a script without the owner's yes: a run that skips `cw`'s hash check, an approval
  written without the owner being asked, YOLO switched on behind their back.
- Anything that gets around the approval hook (`hooks/approve-gate.sh`), including getting a call that changes a
  machine let through without a prompt in normal mode.
- Command injection over SSH: an argument, a host name or a record file that makes the target (or the operator
  machine) run something other than the approved script.
- Anything that leaks the record (`~/.cwtfigo`: host facts, notes, the network's layout) off the operator machine
  without the owner reading and approving it.
- Anything that reads a file outside the record into the conversation (a key, a `.env`, a browser export) without the
  owner's yes, for example through a `cw` call the hook lets through in normal mode.
- The Hermes skills `cw hermes` writes, and its Hermes hook: a skill that runs something other than the owner's
  approved script as approved, or `--apply` without a yes in the chat, or a record or script field that gets
  instructions or commands into a skill. Not a hole: whoever may talk to the Hermes bot is trusted like the owner, since
  a yes in the chat runs `--apply` ([HERMES.md](HERMES.md)).

Not a hole: the shared record. `cw run` and `cw status` pull it first, so whoever can push to it is trusted like the
owner: a script and its approval pushed there run on the next `cw run`. Keep it private, on a machine you control.

The hook is a guard against mistakes, not a sandbox: a string match that stops the model approving by habit or by
accident. What it does and doesn't stop, and the known limits of what it lets through without a prompt, are written in
[its header](hooks/approve-gate.sh). A way around it that the header already lists is known; one it doesn't list is
worth a report.

## How to report

Privately, through GitHub's private vulnerability reporting on
[DozenTwelve/CWTFIGO](https://github.com/DozenTwelve/CWTFIGO): the **Security** tab, **Report a vulnerability**.
Please don't open a public issue for it.

Include:

- the CWTFIGO version (`version` in `.claude-plugin/plugin.json`)
- the steps to reproduce it, as small as you can make them
- what it lets someone do: which machine, what runs or leaks, with or without the owner's yes
