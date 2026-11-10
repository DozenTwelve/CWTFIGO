# Run your approved scripts from a chat app (Hermes)

[Hermes](https://github.com/NousResearch/hermes-agent) is a chat bot you run yourself, on a computer that's always on (a home server, a NAS). With CWTFIGO's help it can run the checks and upkeep you approved in Claude Code, from Discord, without Claude Code on that computer: `cw hermes` turns each approved script the menu would show (check, maintain, and scripts with a `# menu:` line) into a Hermes skill, a command you can send it.

**Anyone who may talk to the Hermes bot can change that computer and the machines it reaches.** Upkeep runs a dry run first, then asks in the chat whether to make the changes; a yes typed there runs it for real (`--apply`). The skills tell Hermes never to approve a script, and cw runs only scripts you approved, as you approved them. Past that, nothing checks who is asking, and Hermes can't tell who typed the yes: keep the bot to yourself.

## What the always-on computer needs

- Linux or a Mac, with `git` and `python3`, and Hermes already set up and answering you in Discord.
- Your notes shared through a private git copy that both computers can reach: a private GitHub repo, or a shared copy on the always-on computer itself (below). Never a public one. The always-on computer must be able to fetch it without a password prompt.
- An SSH key login (no password, no passphrase prompt) from it to every other machine you want it to run scripts on. Nobody can type a password there, so a step that needs `sudo` with a password fails and says so.

## Set it up

1. **Share your notes**, if they aren't shared yet. On the always-on computer, make an empty shared copy:

   ```sh
   git init --bare ~/cwtfigo.git
   ```

   Then in Claude Code on your own computer, say "CWTFIGO, share my notes through `<box>:cwtfigo.git`" (`<box>` being how your computer reaches the always-on one over SSH). It runs `cw join` and `cw save`, and Claude Code asks you first.

2. **Get the plugin's files** onto the always-on computer. A clone keeps them at a fixed place, which the Hermes hook below depends on:

   ```sh
   git clone https://github.com/DozenTwelve/CWTFIGO ~/CWTFIGO
   CW=~/CWTFIGO/skills/cwtfigo/scripts/cw
   ```

3. **Join the notes and name this computer** (the name your other computer uses for it over SSH, so its own scripts run here and not over SSH to itself). Use `~/cwtfigo.git` if the shared copy is on this computer, otherwise the private repo's address:

   ```sh
   sh $CW join ~/cwtfigo.git
   sh $CW name <box>
   ```

4. **Make the skills**, and tell Hermes where they are:

   ```sh
   sh $CW hermes
   ```

   If it says Hermes doesn't read them yet, add the folder to `~/.hermes/config.yaml`:

   ```yaml
   skills:
     external_dirs: [~/.local/share/cwtfigo/hermes]
   ```

   Then restart Hermes once, so it loads the hook `cw hermes` just wrote:

   ```sh
   hermes gateway restart
   ```

In Discord, `/reload-skills` refreshes the `/skill` list; each script shows up as `/skill cw-<machine>-<script>`. Or just ask the bot in plain words ("run the check on the NAS").

## Staying up to date

The hook (in `~/.hermes/hooks/cwtfigo/`) means nothing needs a timer: before Hermes answers a message, it asks the shared notes whether a Claude Code visit saved something new, and if so rebuilds the skills. A script you approve today has its skill at your next message; one that changed since you approved it loses its skill until you approve it again. Only the `/skill` list in Discord needs `/reload-skills` after a change.

To update the plugin's files: `git -C ~/CWTFIGO pull`. The skills rebuild at the next message. Then run `sh $CW hermes` once more and `hermes gateway restart`, so Hermes loads the hook as the new version writes it.

## Taking it off

Delete `~/.local/share/cwtfigo/hermes` and `~/.hermes/hooks/cwtfigo`, take the folder out of `~/.hermes/config.yaml`, then `hermes gateway restart`. The clone (`~/CWTFIGO`) and this computer's copy of the notes (`~/.cwtfigo`) can go too: your own computer keeps its notes.
