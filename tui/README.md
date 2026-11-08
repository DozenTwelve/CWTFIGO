# cwtfigo-tui

Run the scripts in your CWTFIGO record without AI. Left: the machines in `~/.cwtfigo/hosts/` (or `$CWTFIGO_HOME`), online by a TCP probe of their SSH port; with none yet (a first run), this machine. A machine with no scripts yet gets a hint on how to start in the right pane. Middle: each machine's scripts with a `# menu:` line, plus `check` and `maintain`. Right: the script. Enter runs it through `cw run` (asks to approve when cw stops on an unapproved script, offers `--apply` after a dry run); the TUI itself never runs a script or SSHes anywhere.

It only runs what cw runs: scripts you approved, through cw's own approval check. An unapproved or changed script stops in cw; the TUI asks you (the script is in the right pane) and only then calls `cw approve`. Except under YOLO: while it's on (`cw yolo`, asked for in a Claude Code visit, lasts 12 h or until `cw yolo off`), cw runs an unapproved script without asking and approves it. The TUI says so at the top and marks those machines YOLO. An approval or an `--apply` run made here goes on top of that machine's `log.md` as a `## <date> tui` entry and is saved with `cw save`, so other computers sharing the record get it.

## Install a prebuilt binary

In Claude Code, say "CWTFIGO install the TUI": it runs `cw tui`, which installs the TUI of your plugin's version. That is the rule: the TUI runs the same version as the plugin, the one that fits its cw.

Without Claude Code at hand, this gets the newest release; if the plugin is a different version, the TUI then offers `u` to switch to the plugin's:

```sh
mkdir -p ~/.local/bin && curl -fsSL https://github.com/DozenTwelve/CWTFIGO/releases/latest/download/cwtfigo-tui-$(uname -s)-$(uname -m).tar.gz | tar -xz -C ~/.local/bin cwtfigo
```

Then type `cwtfigo` in a terminal (`cwtfigo --version` says which build it is). Needs `~/.local/bin` on your `PATH`; Mac and Linux only (no Windows build); `curl` sets no quarantine flag on a Mac, so the unsigned binary opens.

To check the download first:

```sh
cd "$(mktemp -d)" && f=cwtfigo-tui-$(uname -s)-$(uname -m).tar.gz
curl -fsSLO https://github.com/DozenTwelve/CWTFIGO/releases/latest/download/$f
curl -fsSLO https://github.com/DozenTwelve/CWTFIGO/releases/latest/download/$f.sha256
{ sha256sum -c $f.sha256 2>/dev/null || shasum -a 256 -c $f.sha256; } && mkdir -p ~/.local/bin && tar -xzf $f -C ~/.local/bin cwtfigo
```

## Build from a clone

```sh
cd tui && cargo build --release
ln -s "$PWD/target/release/cwtfigo-tui" ~/.local/bin/cwtfigo
```

The link follows rebuilds: after a `git pull`, `cargo build --release` again.

## Where it finds cw

1. `CWTFIGO_CW`, if set (the path to a `scripts/cw`; it errors if that file isn't there).
2. The plugin Claude Code installed: the `cwtfigo@cwtfigo` entry in `~/.claude/plugins/installed_plugins.json` (or under `$CLAUDE_CONFIG_DIR`): the one installed for every project first, else the one for the folder you start the TUI in, else the newest; plus `skills/cwtfigo/scripts/cw`.
3. A debug build only: the checkout it was built from (`../skills/cwtfigo/scripts/cw`), if it exists. A release build has no such fallback.

So install the plugin in Claude Code (`/plugin install cwtfigo@cwtfigo`) and the binary finds it, and keeps up when the plugin updates. When the plugin is a different version than the TUI, the bottom row offers `u`: "update TUI to <version>" when the plugin's is newer, "switch TUI to <version>" when it's older. Either way it runs `cw tui`, which installs the plugin's version, and restarts into it. If cw warns about your `PATH` (`~/.local/bin` missing from it, or another `cwtfigo` before it), or this TUI wasn't started from `~/.local/bin/cwtfigo`, it stops to show that first: otherwise the next `cwtfigo` you type starts the old one again.

Keys: j/k or up/down, tab (or h/l, left/right) between panes, PgUp/PgDn scroll the preview, r refresh (probes again and, when the record has a remote, pulls it through `cw status`, as it does at start: the TUI creates nothing; the bar says if the pull failed), q, Esc or Ctrl-C quit. The bottom row shows the keys that work right now.
