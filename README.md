<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/banner-dark.png">
    <img alt="CWTFIGO: an orange robot with a cigar" src="assets/banner-light.png" width="640">
  </picture>
</p>

# CWTFIGO

**Claude, what the fuck is going on?**

Your computer acts up and you don't know why. Call Claude by name: it looks, tells you in plain words what's wrong, fixes it once you say OK, and remembers that machine for next time.

Its scripts run only after your yes, the run that makes changes asks every time, and its notes stay on your computer.

A plugin for [Claude Code](https://claude.com/claude-code) ([website](https://cwtfigo.diamonddoge.org) · [中文](https://cwtfigo.diamonddoge.org/zh/)), independent, not made by Anthropic. Macs, Linux, Windows, Steam Deck, routers, the one in front of you or others on your network over SSH.

![A first checkup: health, what upkeep would do, and a question](assets/report.png)

## Install

In Claude Code, paste one line at a time:

```
/plugin marketplace add DozenTwelve/CWTFIGO
/plugin install cwtfigo@cwtfigo
```

The second line doesn't install by itself: it opens a panel that shows the plugin. Choose **Install for you (user scope)** there, the one that covers every project on this computer. Then type `cwtfigo`. If it offers you a checkup of this computer, it's working; if not, run `/reload-plugins` (or restart Claude Code) and type it again.

It needs `git` (on a Mac: `xcode-select --install`) and `python3` to search past fixes (most Linux has it already; on a minimal install, `sudo apt install python3` or `sudo dnf install python3`; a Mac gets it with `xcode-select --install` too). On Windows it needs Git for Windows: CWTFIGO's own scripts, and the check that asks you before changes, run in its Git Bash. Claude Code works without Git Bash; CWTFIGO doesn't. The first visit goes best on Opus (`/model opus`).

A machine's checkup and upkeep start from a ready-made script on macOS, Windows, Arch, Debian and its relatives (Ubuntu, Mint, Pop!_OS, Raspberry Pi OS and a few more) and OpenWrt routers. Other systems, like Fedora or the Steam Deck, work too: Claude writes their scripts from less.

## How it works

You say the name and what's wrong:

> CWTFIGO, why is my laptop at 90°C every day?
>
> what the fuck is going on with the server
>
> 一体どうなってやがるんだ、Wi-Fiがすぐ切れる

Or just `cwtfigo`, and it offers a checkup: disk, memory, battery, failed services, pending updates, how much space a cleanup would free.

There's no fixed script library. Claude writes each machine's scripts on the spot, for that machine: its OS, what's installed, what you told it not to touch. It starts from a short template per OS and, where open-source projects already keep the data (which files an app leaves behind, where games keep saves, how each package manager upgrades), it reads theirs instead of guessing. It reads them; it never downloads and runs their code.

Before a new script runs, Claude Code asks you. One yes covers the plugin's own read-only checks; the scripts Claude writes for your machine need their own yes. Once approved, a script runs from then on without asking, until it changes. A script that changes your computer (an update, a cleanup, a fix) comes in two steps: a plain run only shows what it would do, and the run that does it asks every time, unless you run Claude Code with its permission prompts switched off. The two steps are a rule Claude follows when it writes a script, not a lock: a script is worth a look before your yes. Other commands Claude runs along the way ask or not as your own Claude Code permission settings say.

What it learns goes into notes on your computer, one folder per machine: what it is, what went wrong, what fixed it, a health check that grows with every fix. The next visit starts from there, so the same question costs less, and a fix that quietly comes undone shows up in the next check.

![Claude Code asking before a script runs](assets/approve.png)

## Why not just ask Claude?

- **It remembers.** Without notes, every chat starts from zero: what this machine is, what you tried last month.
- **It asks first.** A script runs only after your yes (one yes covers the plugin's read-only checks), checked by its fingerprint: if it changes, it asks again.
- **Scripts written for your machine, kept.** Each machine gets its own health check and upkeep script, written by Claude for that machine and approved by you, then rerun every visit and rewritten when something new is learned.
- **Many machines.** Your laptop can look after your server, your NAS and your router over SSH, with the notes for all of them in one place.
- **No AI needed afterwards (Mac and Linux).** A small terminal menu runs your approved checks and upkeep without Claude.

## Without AI: the menu

![The menu: machines, their scripts, a check's output](assets/tui.png)

It shows the scripts Claude has written and you've approved, machine by machine, so on day one it's empty: it fills as you use CWTFIGO. Mac and Linux. In Claude Code, say "CWTFIGO install the TUI", then type `cwtfigo` in a terminal.

Plugin installed but no Claude Code at hand right now? This gets the newest release instead (the menu always needs the plugin installed, which is how it finds CWTFIGO, and the notes your visits made):

```
mkdir -p ~/.local/bin && curl -fsSL https://github.com/DozenTwelve/CWTFIGO/releases/latest/download/cwtfigo-tui-$(uname -s)-$(uname -m).tar.gz | tar -xz -C ~/.local/bin cwtfigo
```

Then type `cwtfigo`. If the terminal says it's not found, `~/.local/bin` isn't on your `PATH` yet (a Mac doesn't have it there by default). Add it and open a new terminal (on Linux with bash, `~/.bashrc` instead of `~/.zshrc`):

```
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
```

When the plugin updates, the menu offers `u` to follow it. More in [`tui/README.md`](tui/README.md).

The same approved scripts can also run from a chat app: on a computer that's always on and runs the Hermes chat bot, `cw hermes` turns each one into a command you can send it from Discord. A yes typed in that chat makes the changes, so whoever may talk to the bot can change that computer. Setup in [`HERMES.md`](HERMES.md).

## Privacy

- The notes live in `~/.cwtfigo`, a git folder on your computer. Delete it and they're gone. Several computers can share them through a private git remote you own; never a public one.
- What Claude reads (names, paths, ports, log lines) passes through Anthropic like anything else you show Claude Code. For a cleanup it measures sizes, never what's in your files.
- It only starts when you call it by name. Describe a problem without the name and you get a normal Claude answer; it never touches a machine you didn't point it at.

## When something goes wrong

Tell it: "CWTFIGO, that didn't work", or "CWTFIGO, open an issue about this". It drafts a bug report with the version and what happened, shows it to you, and posts it under your GitHub account only on your yes. Posting needs GitHub's `gh` tool, installed and logged in (`gh auth login`). Or open one yourself: [new issue](https://github.com/DozenTwelve/CWTFIGO/issues/new/choose). Security problems: see [SECURITY.md](SECURITY.md).

<details>
<summary>Install from a clone, to change it while you use it</summary>

In a terminal:

```
git clone https://github.com/DozenTwelve/CWTFIGO ~/CWTFIGO
```

Then in Claude Code, one line at a time (the path is where you cloned it; a `./` path counts from the folder Claude Code was started in):

```
/plugin marketplace add ~/CWTFIGO
/plugin install cwtfigo@cwtfigo
```

The second line opens the same panel: choose **Install for you (user scope)**. Then `/reload-plugins` if `cwtfigo` isn't known yet.

</details>

## Update

Claude Code doesn't update this plugin by itself: it does that only for Anthropic's own marketplaces. To update now, run `/plugin`, open the **Marketplaces** tab, pick `cwtfigo`, choose **Update marketplace**, then run `/reload-plugins`. Choose **Enable auto-update** in the same place to have it done each time Claude Code starts.

## Uninstall

In Claude Code, `/plugin marketplace remove cwtfigo` uninstalls the plugin with its marketplace. In a terminal, this deletes the menu and the small markers it keeps of past visits:

```
rm -rf ~/.local/bin/cwtfigo "${XDG_RUNTIME_DIR:-$HOME/.cache}/cwtfigo-visit"
```

Then take out the `PATH` line if you added it for the menu, and Hermes as [`HERMES.md`](HERMES.md#taking-it-off) says if you set it up. Your notes stay in `~/.cwtfigo`: delete that folder only if you want them gone for good.

## License

MIT ([LICENSE](LICENSE)). How it behaves, for the curious: [`skills/cwtfigo/SKILL.md`](skills/cwtfigo/SKILL.md).
