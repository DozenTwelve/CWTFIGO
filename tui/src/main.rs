//! Offline menu for a CWTFIGO record: machines, their menu scripts, a preview. Every run goes through cw;
//! this program never runs a script or ssh's into a machine itself (only `ssh -G` to read the config).
mod header;

use ratatui::{
    crossterm::event::{self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers},
    layout::{Alignment, Constraint, Layout, Margin, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{
        Block, BorderType, Clear, Padding, List, ListItem, ListState, Paragraph, Scrollbar, ScrollbarOrientation, ScrollbarState,
        Wrap,
    },
    DefaultTerminal, Frame,
};
use std::collections::HashSet;
use std::io::IsTerminal;
use std::net::{TcpStream, ToSocketAddrs};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitStatus, Stdio};
use std::sync::mpsc::{self, Sender};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use std::{env, fs};

struct Item {
    stem: String,
    file: String,
    label: String,
    args: Vec<String>,
    apply: bool,
    text: String,
}

struct Host {
    name: String,
    here: bool,
    os: Option<String>,
    online: Option<bool>,
    /// cw's YOLO is on for it: an unapproved script runs and gets approved without asking.
    yolo: bool,
    items: Vec<Item>,
}

enum Mode {
    Normal,
    PickArg(usize),
    Confirm(String, Then),
}

/// What a confirm runs: fixed when it's asked, so a pull that adds or drops machines or scripts can't redirect it.
#[derive(Clone, Debug, PartialEq)]
struct Target {
    name: String,
    stem: String,
    file: String,
    arg: Option<String>,
    can_apply: bool,
}

enum Then {
    /// Then a dry run, whatever was asked when cw stopped: --apply never runs on content that hasn't had one.
    Approve(Target),
    Apply(Target),
}

struct App {
    cw: PathBuf,
    rec: PathBuf,
    hosts: Vec<Host>,
    host: usize,
    item: usize,
    pane: usize,
    scroll: u16,
    mode: Mode,
    message: String,
    probing: HashSet<String>,
    pulling: bool,
    /// What `u` does, for the key bar, when the plugin's version isn't this build's: `u` installs the plugin's.
    update: Option<String>,
}

/// What a background thread reports: a probe's answer, or how `cw status` (the pull) ended.
enum Msg {
    Online(String, Option<bool>),
    Pulled(String),
}

fn main() {
    let args: Vec<String> = env::args_os().skip(1).map(|a| a.to_string_lossy().into_owned()).collect();
    match cli(&args) {
        Ok(None) => {}
        Ok(Some(out)) => {
            println!("{out}");
            return;
        }
        Err(e) => {
            eprintln!("{e}");
            std::process::exit(2);
        }
    }
    // ratatui::init panics without one.
    if !std::io::stdout().is_terminal() || !std::io::stdin().is_terminal() {
        eprintln!("cwtfigo: needs a terminal");
        std::process::exit(1);
    }
    let cw = find_cw().unwrap_or_else(|e| {
        eprintln!("{e}");
        std::process::exit(1);
    });
    let rec = env::var_os("CWTFIGO_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env::var_os("HOME").unwrap_or_default()).join(".cwtfigo"));
    let hosts = hosts(&rec);
    // A debug build is a checkout's, newer or older than any plugin: no nagging. Nor for a link to one's own build,
    // which cw tui won't replace.
    let home = PathBuf::from(env::var_os("HOME").unwrap_or_default());
    let update = if cfg!(debug_assertions) || own_build(&home) {
        None
    } else {
        update_to(plugin_version(&cw).as_deref(), env!("CARGO_PKG_VERSION"))
    };
    let mut app = App {
        cw,
        rec,
        hosts,
        host: 0,
        item: 0,
        pane: 0,
        scroll: 0,
        mode: Mode::Normal,
        message: env::var("CWTFIGO_UPDATED_FROM")
            .map(|from| format!("updated from {from} to {}", env!("CARGO_PKG_VERSION")))
            .unwrap_or_default(),
        probing: HashSet::new(),
        pulling: false,
        update,
    };
    #[cfg(unix)]
    survive_ctrl_c();
    let mut terminal = ratatui::init();
    let res = run(&mut terminal, &mut app);
    ratatui::restore();
    if let Err(e) = res {
        eprintln!("error: {e}");
    }
}

const USAGE: &str = "usage: cwtfigo [--help | --version]";

/// The arguments: Ok(None) runs the TUI, Ok(Some) is what to print instead, Err the error and usage (exit 2).
fn cli(args: &[String]) -> Result<Option<String>, String> {
    match args {
        [] => Ok(None),
        [a] if a == "--version" => Ok(Some(format!("cwtfigo {}", env!("CARGO_PKG_VERSION")))),
        [a] if a == "--help" => Ok(Some(format!(
            "{USAGE}\nKeys: on the bottom row; more in https://github.com/DozenTwelve/CWTFIGO/blob/main/tui/README.md"
        ))),
        [a] => Err(format!("cwtfigo: unknown argument {a}\n{USAGE}")),
        _ => Err(format!("cwtfigo: too many arguments\n{USAGE}")),
    }
}

/// The checkout a debug build was built from, for running it from a clone. Not compiled into a release: there it would
/// be the build machine's path (a CI runner's), mean nothing on this one, and leak into the binary.
#[cfg(debug_assertions)]
const DEV_CW: Option<&str> = Some(concat!(env!("CARGO_MANIFEST_DIR"), "/../skills/cwtfigo/scripts/cw"));
#[cfg(not(debug_assertions))]
const DEV_CW: Option<&str> = None;

/// CWTFIGO_CW, else the plugin Claude Code installed, else (debug builds) this checkout, if it exists.
fn find_cw() -> Result<PathBuf, String> {
    if let Some(p) = env::var_os("CWTFIGO_CW").map(PathBuf::from) {
        // Set but wrong is a mistake to show, not a reason to quietly run some other cw.
        return if p.is_file() { Ok(p) } else { Err(format!("CWTFIGO_CW={} is not a file.", p.display())) };
    }
    let home = PathBuf::from(env::var_os("HOME").unwrap_or_default());
    let claude = env::var_os("CLAUDE_CONFIG_DIR").map(PathBuf::from).unwrap_or_else(|| home.join(".claude"));
    let list = claude.join("plugins/installed_plugins.json");
    let dev = DEV_CW.map(PathBuf::from);
    installed_cw(&fs::read_to_string(&list).unwrap_or_default())
        .into_iter()
        .chain(dev.clone())
        .find(|p| p.is_file())
        .ok_or_else(|| {
            let mut e = format!(
                "cw not found. Looked at:\n  CWTFIGO_CW (not set)\n  the cwtfigo@cwtfigo plugin in {}",
                list.display()
            );
            if let Some(d) = dev {
                e += &format!("\n  {} (the clone this debug build came from)", d.display());
            }
            e + "\nTo fix, install the plugin in Claude Code:\n  /plugin marketplace add DozenTwelve/CWTFIGO\n  \
                 /plugin install cwtfigo@cwtfigo\nor set CWTFIGO_CW to the path of a scripts/cw."
        })
}

/// scripts/cw in every cwtfigo@cwtfigo install Claude Code lists, scope user first. Old versions stay in the cache,
/// so the list (not the newest directory there) says which one is live.
fn installed_cw(json: &str) -> Vec<PathBuf> {
    // ponytail: string split, not a JSON parser: entries are flat objects and the paths sit under $HOME, so no `]`, `}`
    // or `"` in them. A path with one of those breaks it; serde_json if that ever happens.
    let Some(list) = json.split("\"cwtfigo@cwtfigo\"").nth(1).and_then(|s| s.split(']').next()) else { return vec![] };
    let mut found: Vec<(bool, PathBuf)> = list
        .split('}')
        .filter_map(|e| {
            let path = PathBuf::from(field(e, "installPath")?).join("skills/cwtfigo/scripts/cw");
            Some((field(e, "scope").as_deref() != Some("user"), path))
        })
        .collect();
    found.sort_by_key(|f| f.0); // stable: same scope keeps the file's order
    found.into_iter().map(|f| f.1).collect()
}

/// The string value of "key" in a flat JSON object, as written by tools (any spacing around the colon).
fn field(json: &str, key: &str) -> Option<String> {
    let v = json.split(&format!("\"{key}\"")).nth(1)?.trim_start().strip_prefix(':')?.trim_start().strip_prefix('"')?;
    Some(v[..v.find('"')?].to_string())
}

/// The version of the plugin cw belongs to: cw is <root>/skills/cwtfigo/scripts/cw, the version in
/// <root>/.claude-plugin/plugin.json.
fn plugin_version(cw: &Path) -> Option<String> {
    let root = cw.ancestors().nth(4)?;
    field(&fs::read_to_string(root.join(".claude-plugin/plugin.json")).ok()?, "version")
}

/// What `u` offers when this build isn't the plugin's version: `cw tui` installs exactly the plugin's, older or newer.
/// An older one is a switch, never called an update.
fn update_to(plugin: Option<&str>, mine: &str) -> Option<String> {
    let num = |v: &str| v.split('.').map(|x| x.parse::<u64>().unwrap_or(0)).collect::<Vec<_>>();
    let p = plugin.filter(|p| *p != mine)?;
    Some(format!("{} TUI to {p}", if num(p) > num(mine) { "update" } else { "switch" }))
}

/// ~/.local/bin/cwtfigo links to a build from a clone (tui/README's setup): rebuilt there, not by `cw tui`.
fn own_build(home: &Path) -> bool {
    home.join(".local/bin/cwtfigo").is_symlink()
}

/// `cw tui` installs the plugin's version into ~/.local/bin; then this process becomes it, same args. On failure the
/// TUI stays as it was.
fn update(terminal: &mut DefaultTerminal, app: &mut App) {
    let mut cmd = cw(app);
    cmd.arg("tui");
    // No pause on success: the new TUI says it was updated. A failure still stops to show why.
    match run_external(terminal, &mut cmd, false) {
        Ok(s) if s.success() => {
            let bin = PathBuf::from(env::var_os("HOME").unwrap_or_default()).join(".local/bin/cwtfigo");
            ratatui::restore();
            let e = reexec(&bin);
            *terminal = ratatui::init();
            let _ = terminal.clear();
            app.message = format!("updated, but cannot start {}: {e}", bin.display());
        }
        Ok(s) => app.message = format!("TUI update failed: cw tui {s}"),
        Err(e) => app.message = format!("cannot start sh: {e}"),
    }
}

/// Only returns on failure.
#[cfg(unix)]
fn reexec(bin: &Path) -> std::io::Error {
    let mut cmd = Command::new(bin);
    cmd.args(env::args_os().skip(1)).env("CWTFIGO_UPDATED_FROM", env!("CARGO_PKG_VERSION"));
    std::os::unix::process::CommandExt::exec(&mut cmd)
}
#[cfg(not(unix))]
fn reexec(_: &Path) -> std::io::Error {
    std::io::ErrorKind::Unsupported.into()
}

fn run(terminal: &mut DefaultTerminal, app: &mut App) -> std::io::Result<()> {
    let (tx, rx) = mpsc::channel();
    refresh(app, &tx);
    pull(app, &tx);
    let mut last = Instant::now();
    loop {
        while let Ok(m) = rx.try_recv() {
            got(app, m);
        }
        terminal.draw(|f| draw(f, app))?;
        if event::poll(Duration::from_millis(250))? {
            if let Event::Key(k) = event::read()? {
                if k.kind == KeyEventKind::Press && !key(terminal, app, k, &tx) {
                    return Ok(());
                }
            }
        }
        if last.elapsed() > Duration::from_secs(10) {
            refresh(app, &tx);
            last = Instant::now();
        }
    }
}

/// The keys that leave from the main screen: q, Esc, and Ctrl-C or Ctrl-D, which raw mode delivers as plain keys.
fn quits(k: KeyEvent) -> bool {
    matches!(k.code, KeyCode::Char('q') | KeyCode::Esc)
        || k.modifiers.contains(KeyModifiers::CONTROL) && matches!(k.code, KeyCode::Char('c' | 'd'))
}

/// One key press. false = quit.
fn key(terminal: &mut DefaultTerminal, app: &mut App, k: KeyEvent, tx: &Sender<Msg>) -> bool {
    let code = k.code;
    let up = matches!(code, KeyCode::Up | KeyCode::Char('k'));
    let down = matches!(code, KeyCode::Down | KeyCode::Char('j'));
    app.message.clear(); // a message stays until the next key, then the key bar is back
    match std::mem::replace(&mut app.mode, Mode::Normal) {
        Mode::Confirm(_, then) => {
            if !matches!(code, KeyCode::Char('y' | 'Y')) {
                app.message = "cancelled".into();
            } else {
                match then {
                    Then::Apply(t) => go(terminal, app, t, true),
                    Then::Approve(t) => {
                        let mut cmd = cw(app);
                        cmd.args(["approve", &t.name, &t.stem]);
                        match run_external(terminal, &mut cmd, false) {
                            Ok(s) if s.success() => {
                                save(terminal, app, &t.name, &format!("approved {}", t.stem));
                                go(terminal, app, t, false)
                            }
                            _ => app.message = format!("approve {} on {} failed", t.stem, t.name),
                        }
                    }
                }
            }
        }
        Mode::PickArg(i) => {
            let n = app.hosts[app.host].items[app.item].args.len();
            match code {
                KeyCode::Enter => {
                    let arg = app.hosts[app.host].items[app.item].args[i].clone();
                    go(terminal, app, target(app, Some(arg)), false);
                }
                KeyCode::Esc | KeyCode::Char('q') => {}
                _ if up => app.mode = Mode::PickArg(i.saturating_sub(1)),
                _ if down => app.mode = Mode::PickArg((i + 1).min(n - 1)),
                _ => app.mode = Mode::PickArg(i),
            }
        }
        Mode::Normal => match code {
            _ if quits(k) => return false,
            KeyCode::Tab => app.pane = (app.pane + 1) % 3,
            KeyCode::BackTab => app.pane = (app.pane + 2) % 3,
            KeyCode::Right | KeyCode::Char('l') => app.pane = (app.pane + 1).min(2),
            KeyCode::Left | KeyCode::Char('h') => app.pane = app.pane.saturating_sub(1),
            KeyCode::Char('r') => {
                rescan(app);
                refresh(app, tx);
                pull(app, tx);
                app.message = if app.pulling { "refreshed, getting the latest notes" } else { "refreshed" }.into();
            }
            KeyCode::Char('u') if app.update.is_some() => update(terminal, app),
            KeyCode::PageDown => app.scroll = app.scroll.saturating_add(20),
            KeyCode::PageUp => app.scroll = app.scroll.saturating_sub(20),
            KeyCode::Enter => match app.hosts[app.host].items.get(app.item) {
                Some(it) if !it.args.is_empty() => app.mode = Mode::PickArg(0),
                Some(_) => go(terminal, app, target(app, None), false),
                None => {}
            },
            _ if up || down => match app.pane {
                0 => {
                    app.host = if up { app.host.saturating_sub(1) } else { (app.host + 1).min(app.hosts.len() - 1) };
                    app.item = 0;
                    app.scroll = 0;
                }
                1 => {
                    let n = app.hosts[app.host].items.len().max(1);
                    app.item = if up { app.item.saturating_sub(1) } else { (app.item + 1).min(n - 1) };
                    app.scroll = 0;
                }
                _ => app.scroll = if up { app.scroll.saturating_sub(1) } else { app.scroll.saturating_add(1) },
            },
            _ => {}
        },
    }
    true
}

/// The selected script; only called while it exists (Enter on it).
fn target(app: &App, arg: Option<String>) -> Target {
    let h = &app.hosts[app.host];
    let it = &h.items[app.item];
    Target { name: h.name.clone(), stem: it.stem.clone(), file: it.file.clone(), arg, can_apply: it.apply }
}

fn cw(app: &App) -> Command {
    let mut c = Command::new("sh");
    c.arg(&app.cw);
    c
}

/// `cw run`, then whatever its exit code asks for: 3 approve, 0 on a script that takes --apply: offer it.
fn go(terminal: &mut DefaultTerminal, app: &mut App, t: Target, apply: bool) {
    let mut cmd = cw(app);
    cmd.args(run_args(&t, apply));
    let res = run_external(terminal, &mut cmd, true);
    if apply {
        let how = match &res {
            Ok(s) => s.code().map_or("killed".into(), |c| format!("exit {c}")),
            Err(e) => format!("didn't start: {e}"),
        };
        save(terminal, app, &t.name, &format!("ran {}: {how}", run_args(&t, true)[2..].join(" ")));
    }
    rescan(app); // cw run pulls the record: scripts may have changed
    let unapproved = !approved(&app.rec, &t);
    after(app, t, apply, unapproved, res.map(|s| s.code()));
}

/// What the owner did here goes where a visit's actions go: an entry on top of the machine's log.md, then `cw save`, so
/// other computers sharing the record get the approval and the next visit sees the run. Only fails out loud.
fn save(terminal: &mut DefaultTerminal, app: &mut App, name: &str, what: &str) {
    let mut cmd = note(app, name, what);
    if !matches!(run_external(terminal, &mut cmd, false), Ok(s) if s.success()) {
        app.message = format!("{what} on {name}, but saving it to the notes failed");
    }
}

/// Writes the log.md entry; the `cw save` to run after it.
fn note(app: &App, name: &str, what: &str) -> Command {
    let date = Command::new("date").arg("+%F").output().map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string());
    let entry = format!("## {} tui\n- {what} (in the TUI)\n\n", date.unwrap_or_default());
    let f = app.rec.join("hosts").join(name).join("log.md");
    let old = fs::read_to_string(&f).unwrap_or_default();
    // Newest first, under anything above the first entry.
    let at = if old.starts_with("## ") { 0 } else { old.find("\n## ").map_or(old.len(), |i| i + 1) };
    let _ = fs::write(&f, format!("{}{entry}{}", &old[..at], &old[at..]));
    let mut cmd = cw(app);
    cmd.args(["save", &format!("tui: {what} on {name}")]);
    cmd
}

/// Whether cw counts the script approved: its sha256 in the host's approved.sha256, the check cw makes. Exit 3 from
/// an approved script is the script's own, not cw asking. Reading cw's output instead would take the tty from scripts.
fn approved(rec: &Path, t: &Target) -> bool {
    let h = rec.join("hosts").join(&t.name);
    let f = h.join(&t.file);
    let out = Command::new("sha256sum")
        .arg(&f)
        .output()
        .or_else(|_| Command::new("shasum").args(["-a", "256"]).arg(&f).output());
    let out = match out {
        Ok(o) if o.status.success() => String::from_utf8_lossy(&o.stdout).into_owned(),
        _ => return false,
    };
    let sum = out.split_whitespace().next().unwrap_or("");
    let list = fs::read_to_string(h.join("approved.sha256")).unwrap_or_default();
    !sum.is_empty() && list.lines().any(|l| l.split(' ').next() == Some(sum))
}

/// What the owner can do about a failure cw explains only to the model, or ssh only by its exit code.
fn hint(code: i32, here: bool, unadapted: bool) -> &'static str {
    match code {
        1 if unadapted => ". Not adapted to this machine yet: have the AI adapt and approve it first.",
        255 if !here => ". ssh could not reach it: is it on and on the network?",
        _ => "",
    }
}

/// --apply goes first: sh scripts look for it in $1 only.
fn run_args(t: &Target, apply: bool) -> Vec<&str> {
    let mut v = vec!["run", &t.name, &t.stem];
    v.extend(apply.then_some("--apply"));
    v.extend(t.arg.as_deref());
    v
}

/// What the run's exit asks for next. Works on t alone: the lists may have changed under it.
fn after(app: &mut App, t: Target, apply: bool, unapproved: bool, res: std::io::Result<Option<i32>>) {
    let (name, stem) = (t.name.clone(), t.stem.clone());
    match res {
        Ok(Some(3)) if unapproved => {
            app.mode = Mode::Confirm(format!("Approve {stem} on {name}? y/N"), Then::Approve(t))
        }
        Ok(Some(0)) if t.can_apply && !apply => {
            app.mode = Mode::Confirm(format!("Run {stem} with --apply? y/N"), Then::Apply(t))
        }
        Ok(Some(c)) => {
            let here = app.hosts.iter().any(|h| h.name == name && h.here);
            let text = fs::read_to_string(app.rec.join("hosts").join(&name).join(&t.file)).unwrap_or_default();
            let unadapted = text.lines().any(|l| l.starts_with("# CWTFIGO-FOUNDATION"));
            app.message = format!("{stem} on {name}: exit {c}{}", hint(c, here, unadapted));
        }
        Ok(None) => app.message = format!("{stem} on {name}: killed"),
        Err(e) => app.message = format!("cannot start sh: {e}"),
    }
}

/// Out of raw mode, Ctrl-C signals the whole foreground group: the script and this TUI. A handler that does nothing,
/// not SIG_IGN: exec resets handlers to the default, so the script still stops on Ctrl-C.
// ponytail: unix only; Windows Ctrl-C needs SetConsoleCtrlHandler if the TUI ever runs natively there.
#[cfg(unix)]
fn survive_ctrl_c() {
    extern "C" fn ignore(_: libc::c_int) {}
    unsafe { libc::signal(libc::SIGINT, ignore as extern "C" fn(libc::c_int) as libc::sighandler_t) };
}

/// Leave the TUI, run cmd in the real terminal, wait for Enter (always on failure), come back.
fn run_external(terminal: &mut DefaultTerminal, cmd: &mut Command, pause: bool) -> std::io::Result<ExitStatus> {
    ratatui::restore();
    let res = cmd.status();
    if pause || !matches!(&res, Ok(s) if s.success()) {
        match &res {
            Ok(s) => println!("\n[{s}] Press Enter to return."),
            Err(e) => println!("\ncannot start: {e}. Press Enter to return."),
        }
        let _ = std::io::stdin().read_line(&mut String::new());
    }
    *terminal = ratatui::init();
    let _ = terminal.clear();
    res
}

fn scan(rec: &Path) -> Vec<Host> {
    let me = fs::read_to_string(rec.join("self")).unwrap_or_default().trim().to_string();
    let mut hosts: Vec<Host> = fs::read_dir(rec.join("hosts"))
        .into_iter()
        .flatten()
        .flatten()
        .filter(|e| e.path().is_dir())
        .map(|e| {
            let name = e.file_name().to_string_lossy().into_owned();
            let here = name == me;
            let os = os(&e.path());
            let yolo = fresh(&rec.join("yolo.on")) || fresh(&e.path().join("yolo.on"));
            Host { here, online: None, yolo, items: items(&e.path(), ext(os.as_deref(), here)), os, name }
        })
        .collect();
    hosts.sort_by(|a, b| a.name.cmp(&b.name));
    hosts
}

/// The record's machines; an empty record (a first run) shows this one, named by self, else the name cw's autoname
/// will give it. A rescan that finds the real ones replaces it.
fn hosts(rec: &Path) -> Vec<Host> {
    let hosts = scan(rec);
    if !hosts.is_empty() {
        return hosts;
    }
    let mut name = fs::read_to_string(rec.join("self")).unwrap_or_default().trim().to_string();
    if name.is_empty() {
        name = autoname();
    }
    if name.is_empty() || name == "local" {
        name = "this computer".into();
    }
    vec![Host { name, here: true, os: None, online: None, yolo: false, items: vec![] }]
}

/// As cw's autoname: a Mac's LocalHostName, else `hostname -s`, else `hostname`; lowercased, only a-z 0-9 -.
fn autoname() -> String {
    let out = |cmd: &str, args: &[&str]| {
        let o = Command::new(cmd).args(args).output().map(|o| o.stdout).unwrap_or_default();
        String::from_utf8_lossy(&o).trim().to_string()
    };
    let mut n = if cfg!(target_os = "macos") { out("scutil", &["--get", "LocalHostName"]) } else { out("hostname", &["-s"]) };
    if n.is_empty() {
        n = out("hostname", &[]);
    }
    n.to_lowercase().chars().filter(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || *c == '-').collect()
}

/// What the right pane says when the machine has no menu. Only the stand-in for an empty record has no dir.
fn start_hint(rec: &Path, h: &Host) -> String {
    // Plain words: a newcomer may open this before their first visit (SKILL.md's rule for a new owner).
    if !rec.join("hosts").join(&h.name).is_dir() {
        return "No notes for this computer yet.\n\nIn Claude Code, say \"CWTFIGO\" to start. It looks at this \
                computer and writes scripts to check it and keep it up to date, which you can then run here without AI.\n\n\
                Used CWTFIGO on another computer before? Tell Claude."
            .into();
    }
    // Collected only: cw copies check and maintain from the foundations on their first run, in a visit.
    let who = if h.here { "this computer" } else { &h.name };
    format!("Nothing to run on {who} yet.\n\nIn Claude Code, say \"CWTFIGO\": it writes scripts to check {who} and keep it up to date, which you can then run here.")
}

/// Rescan, keeping the selection on the same machine and script: a pull can end while the owner is looking at one.
fn rescan(app: &mut App) {
    let h = &app.hosts[app.host];
    let (name, stem) = (h.name.clone(), h.items.get(app.item).map(|i| i.stem.clone()));
    let mut hosts = scan(&app.rec);
    for h in &mut hosts {
        h.online = app.hosts.iter().find(|o| o.name == h.name).and_then(|o| o.online);
    }
    if !hosts.is_empty() {
        app.hosts = hosts;
    }
    if let Some(i) = app.hosts.iter().position(|h| h.name == name) {
        app.host = i;
        app.item = stem.and_then(|s| app.hosts[i].items.iter().position(|it| it.stem == s)).unwrap_or(app.item);
    }
    app.host = app.host.min(app.hosts.len() - 1);
    app.item = app.item.min(app.hosts[app.host].items.len().saturating_sub(1));
}

/// As cw's fresh: the file holds an epoch less than 12 h old (cw deletes a stale one on its next run).
fn fresh(f: &Path) -> bool {
    let Some(t) = fs::read_to_string(f).ok().and_then(|t| t.trim().parse::<u64>().ok()) else { return false };
    let now = SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_secs());
    now >= t && now - t < 43200
}

/// The "os" in the machine's device.json; None before its first collect.
fn os(dir: &Path) -> Option<String> {
    field(&fs::read_to_string(dir.join("device.json")).ok()?, "os")
}

/// The extension cw will run on this machine, as cw decides it: device.json, else this machine's own OS.
/// None: a machine not collected yet, cw asks its shell; show both.
fn ext(os: Option<&str>, here: bool) -> Option<&'static str> {
    let windows = match os {
        Some(os) => os == "windows",
        None if here => cfg!(windows),
        None => return None,
    };
    Some(if windows { "ps1" } else { "sh" })
}

/// Scripts with a `# menu:` line, plus check and maintain, which always belong on the menu.
fn items(dir: &Path, ext: Option<&str>) -> Vec<Item> {
    let mut v: Vec<Item> = fs::read_dir(dir)
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|e| {
            let p = e.path();
            let x = p.extension()?.to_str()?;
            if ext.map_or(!matches!(x, "sh" | "ps1"), |e| x != e) {
                return None;
            }
            let stem = p.file_stem()?.to_str()?.to_string();
            // Lossy: a script with a Latin-1 comment still shows up.
            let text = String::from_utf8_lossy(&fs::read(&p).ok()?).replace('\t', "    ");
            let h = header::parse(&text);
            if h.menu.is_none() && stem != "check" && stem != "maintain" {
                return None;
            }
            Some(Item {
                label: h.menu.or(h.about).unwrap_or_else(|| stem.clone()),
                file: e.file_name().to_string_lossy().into_owned(),
                stem,
                args: h.args,
                apply: h.apply,
                text,
            })
        })
        .collect();
    v.sort_by_key(|i| (i.stem != "check", i.stem != "maintain", i.stem.clone()));
    v
}

fn got(app: &mut App, m: Msg) {
    match m {
        Msg::Online(name, online) => {
            app.probing.remove(&name);
            if let Some(h) = app.hosts.iter_mut().find(|h| h.name == name) {
                h.online = online;
            }
        }
        Msg::Pulled(message) => {
            app.pulling = false;
            rescan(app);
            // The picker indexes the script's args, which the pull may have changed or dropped.
            if matches!(app.mode, Mode::PickArg(_)) {
                app.mode = Mode::Normal;
            }
            // The pull's word comes a second after start: it mustn't wipe out "updated from".
            app.message =
                if app.message.starts_with("updated from") { format!("{}, {message}", app.message) } else { message };
        }
    }
}

/// Background `cw status`, which pulls a shared record: the copy here may be from the last pull, long ago. cw does the
/// git and ssh; it never gets the terminal, so it can't prompt over the TUI, and a hung Home only leaves it running.
/// No .git, no status: it would git-init the record, and the TUI creates nothing. No remote (one computer alone, the
/// usual case): nothing to pull, nothing to say.
fn pull(app: &mut App, tx: &Sender<Msg>) {
    if app.pulling || !app.rec.join(".git").exists() {
        return;
    }
    let remote = Command::new("git").arg("-C").arg(&app.rec).arg("remote").stdin(Stdio::null()).output();
    if !remote.is_ok_and(|o| o.status.success() && !o.stdout.is_empty()) {
        return;
    }
    app.pulling = true;
    let mut cmd = cw(app);
    cmd.arg("status").stdin(Stdio::null()).env("GIT_TERMINAL_PROMPT", "0");
    if env::var_os("GIT_SSH_COMMAND").is_none() {
        cmd.env("GIT_SSH_COMMAND", "ssh -o BatchMode=yes -o ConnectTimeout=10");
    }
    // ssh asks for a passphrase or a host key on /dev/tty, not stdin: no controlling terminal, nothing to ask on.
    #[cfg(unix)]
    unsafe {
        std::os::unix::process::CommandExt::pre_exec(&mut cmd, || {
            libc::setsid();
            Ok(())
        });
    }
    let tx = tx.clone();
    std::thread::spawn(move || {
        let m = match cmd.output() {
            Ok(o) => pulled(o.status.success(), &String::from_utf8_lossy(&o.stderr)),
            Err(e) => format!("couldn't get the latest notes: cannot start sh: {e}"),
        };
        let _ = tx.send(Msg::Pulled(m));
    });
}

/// The bar's word on `cw status`. On failure, git's or ssh's first line says why ("ssh: connect to host ..."); cw's
/// own "pull failed" line and the hint: lines (cw's for the model, git's advice) after it don't.
fn pulled(ok: bool, stderr: &str) -> String {
    let failed = stderr.lines().any(|l| l.starts_with("cw: pull failed"));
    if ok && !failed {
        return "notes up to date".into();
    }
    let lines = || stderr.lines().map(str::trim).filter(|l| !l.is_empty() && !l.starts_with("hint:"));
    let why = lines().find(|l| !l.starts_with("cw: pull failed")).or_else(|| lines().next()).unwrap_or("cw status failed");
    format!("couldn't get the latest notes: {why}")
}

fn refresh(app: &mut App, tx: &Sender<Msg>) {
    for name in due(app) {
        probe(name, tx.clone());
    }
}

/// Machines to probe now: not this one, and not one whose last probe hasn't answered (a hung DNS lookup has no
/// timeout; without this every refresh would stack another thread on it).
fn due(app: &mut App) -> Vec<String> {
    let names: Vec<String> =
        app.hosts.iter().filter(|h| !h.here && !app.probing.contains(&h.name)).map(|h| h.name.clone()).collect();
    app.probing.extend(names.iter().cloned());
    names
}

/// Background: resolve the alias with `ssh -G`, then TCP-connect to its SSH port (no root, unlike ICMP).
fn probe(name: String, tx: Sender<Msg>) {
    std::thread::spawn(move || {
        let cfg = Command::new("ssh")
            .arg("-G")
            .arg(&name)
            .output()
            .map(|o| String::from_utf8_lossy(&o.stdout).into_owned())
            .unwrap_or_default();
        let get = |k: &str| cfg.lines().find_map(|l| l.strip_prefix(k)).map(|v| v.trim().to_string());
        let online = match (get("hostname "), get("port ").and_then(|p| p.parse::<u16>().ok())) {
            (Some(h), Some(p)) => reach(&h, p),
            _ => None,
        };
        let _ = tx.send(Msg::Online(name, online));
    });
}

/// Some(true) if the port answers, Some(false) if it doesn't, None (unknown) if the name doesn't resolve here: ssh may
/// still find it. The Linux build is static musl, whose resolver skips NSS (no mDNS, so no `.local`); getent asks the
/// system's.
fn reach(host: &str, port: u16) -> Option<bool> {
    let addr = (host, port).to_socket_addrs().ok().and_then(|mut a| a.next()).or_else(|| {
        if !cfg!(target_os = "linux") {
            return None;
        }
        let out = Command::new("getent").args(["hosts", host]).output().ok()?;
        let ip = String::from_utf8_lossy(&out.stdout).split_whitespace().next()?.parse::<std::net::IpAddr>().ok()?;
        Some((ip, port).into())
    })?;
    Some(TcpStream::connect_timeout(&addr, Duration::from_millis(800)).is_ok())
}

const ACCENT: Color = Color::Cyan;
const MUTED: Style = Style::new().fg(Color::DarkGray);

/// The keys that work right now, for the bar at the bottom.
fn keys(mode: &Mode) -> &'static [(&'static str, &'static str)] {
    match mode {
        Mode::Normal => {
            &[("j/k", "move"), ("tab/h/l", "pane"), ("enter", "run"), ("PgUp/PgDn", "scroll"), ("r", "refresh"), ("q", "quit")]
        }
        Mode::PickArg(_) => &[("j/k", "choose"), ("enter", "run"), ("esc", "back")],
        Mode::Confirm(..) => &[("y", "yes"), ("any other key", "no")],
    }
}

fn draw(f: &mut Frame, app: &mut App) {
    let [top, main, foot] =
        Layout::vertical([Constraint::Length(1), Constraint::Min(3), Constraint::Length(1)]).areas(f.area());
    // The machines pane is as wide as its widest row (marker, dot, name, OS), so the other two get the rest.
    let name_w = app.hosts.iter().map(|h| Span::raw(&h.name).width()).max().unwrap_or(0).min(16);
    let os_w = app.hosts.iter().map(|h| h.os.as_deref().map_or(0, |o| Span::raw(o).width())).max().unwrap_or(0).min(10);
    let yolo_w = if app.hosts.iter().any(|h| h.yolo) { 5 } else { 0 };
    let left_w = (2 + 2 + name_w + 1 + os_w + yolo_w + 3).max(" Machines ".len() + 2) as u16;
    let [left, mid, right] =
        Layout::horizontal([Constraint::Length(left_w), Constraint::Percentage(35), Constraint::Fill(1)]).areas(main);

    // Title bar, as in lanman: name, the record, how many machines answer.
    let up = app.hosts.iter().filter(|h| h.here || h.online == Some(true)).count();
    let count = format!(" {up}/{} online ", app.hosts.len());
    let [name, status] = Layout::horizontal([Constraint::Fill(1), Constraint::Length(count.len() as u16)]).areas(top);
    let home = env::var_os("HOME").map(PathBuf::from).unwrap_or_default();
    let rec = match app.rec.strip_prefix(&home) {
        Ok(r) if !home.as_os_str().is_empty() => Path::new("~").join(r),
        _ => app.rec.clone(),
    };
    let mut title = Line::from(vec![
        Span::styled(" CWTFIGO ", Style::new().fg(ACCENT).add_modifier(Modifier::REVERSED | Modifier::BOLD)),
        Span::styled(format!(" {}", rec.display()), MUTED),
    ]);
    // Under YOLO cw runs an unapproved script with no question, so the TUI's approve step never comes.
    if app.hosts.iter().any(|h| h.yolo) {
        title.push_span(Span::styled("  YOLO: unapproved scripts run without asking", Style::new().fg(Color::Red).add_modifier(Modifier::BOLD)));
    }
    f.render_widget(title, name);
    f.render_widget(Span::styled(count, MUTED), status);

    // Shape and colour both say the state, so it reads without colour too.
    let machines = app.hosts.iter().map(|h| {
        let (icon, color) = match (h.here, h.online) {
            (true, _) => ("◆", ACCENT),
            (_, Some(true)) => ("●", Color::Green),
            (_, Some(false)) => ("○", Color::Red),
            (_, None) => ("◌", Color::Yellow),
        };
        let pad = name_w.saturating_sub(Span::raw(&h.name).width());
        let name = Style::new().add_modifier(if h.online == Some(false) { Modifier::DIM } else { Modifier::BOLD });
        ListItem::new(Line::from(vec![
            Span::styled(format!("{icon} "), Style::new().fg(color)),
            Span::styled(format!("{}{} ", h.name, " ".repeat(pad)), name),
            Span::styled(h.os.clone().unwrap_or_default(), MUTED),
            Span::styled(if h.yolo { " YOLO" } else { "" }, Style::new().fg(Color::Red).add_modifier(Modifier::BOLD)),
        ]))
    });
    list(f, left, " Machines ", machines.collect(), app.host, app.pane == 0);

    // Two lines a script: its menu label, then the file and what Enter will ask.
    let host = &app.hosts[app.host];
    let w = mid.width.saturating_sub(4) as usize;
    let menu: Vec<ListItem> = host
        .items
        .iter()
        .map(|i| {
            let mut sub = i.file.clone();
            if i.apply {
                sub += " · --apply";
            }
            if !i.args.is_empty() {
                sub += &format!(" · {}", i.args.join("|"));
            }
            ListItem::new(vec![Line::from(fit(&i.label, w)), Line::styled(fit(&sub, w), MUTED)])
        })
        .collect();
    let title = format!(" Menu · {} ", host.name);
    if menu.is_empty() {
        // How to get some is in the right pane, the same advice for a first run and a machine not set up yet.
        let empty = "Nothing to run here yet.";
        let p = Paragraph::new(empty).style(MUTED).alignment(Alignment::Center).wrap(Wrap { trim: true });
        f.render_widget(p.block(block(title, app.pane == 1)), mid);
    } else {
        list(f, mid, &title, menu, app.item, app.pane == 1);
    }

    let inner = right.inner(Margin::new(1, 1));
    let (title, text) = match host.items.get(app.item) {
        Some(i) => (format!(" {} ", i.file), preview(i, inner.width)),
        None => (" Start ".into(), Paragraph::new(start_hint(&app.rec, host))),
    };
    let text = text.wrap(Wrap { trim: false });
    // Scrolling stops at the last page, so PgUp after many PgDn moves at once.
    let total = text.line_count(inner.width);
    let max = total.saturating_sub(inner.height as usize) as u16;
    let focused = app.pane == 2;
    app.scroll = app.scroll.min(max);
    f.render_widget(text.scroll((app.scroll, 0)).block(block(title, focused)), right);
    if max > 0 {
        let mut state = ScrollbarState::new(max as usize).position(app.scroll as usize);
        let bar = Scrollbar::new(ScrollbarOrientation::VerticalRight)
            .begin_symbol(None)
            .end_symbol(None)
            .track_symbol(Some("│"))
            .track_style(MUTED)
            .thumb_style(if focused { Style::new().fg(ACCENT) } else { MUTED });
        f.render_stateful_widget(bar, right.inner(Margin::new(0, 1)), &mut state);
    }

    let bar = if app.message.is_empty() {
        let mut v = vec![];
        for (k, what) in keys(&app.mode) {
            let (k, what) = match &app.update {
                // In scroll's place, so the bar still fits 80 columns.
                Some(to) if *k == "PgUp/PgDn" => ("u", to.clone()),
                _ => (*k, what.to_string()),
            };
            v.push(Span::styled(format!(" {k}"), Style::new().fg(ACCENT).add_modifier(Modifier::BOLD)));
            v.push(Span::styled(format!(" {what} "), MUTED));
        }
        Line::from(v)
    } else {
        let mut v = vec![Span::styled(format!(" {} ", app.message), Style::new().add_modifier(Modifier::BOLD))];
        // The offer outlasts a message: a pull's word at start would otherwise hide it a second after it appears.
        if let (Some(to), Mode::Normal) = (&app.update, &app.mode) {
            v.push(Span::styled(" u", Style::new().fg(ACCENT).add_modifier(Modifier::BOLD)));
            v.push(Span::styled(format!(" {to} "), MUTED));
        }
        Line::from(v)
    };
    f.render_widget(bar, foot);

    match &app.mode {
        Mode::Normal => {}
        Mode::Confirm(prompt, _) => popup(f, " Confirm ", prompt, Color::Red),
        Mode::PickArg(i) => {
            let args = &host.items[app.item].args;
            let w = args.iter().map(|a| a.chars().count()).max().unwrap_or(0) as u16 + 8;
            let area = centered(f.area(), w.max(20), args.len() as u16 + 2);
            f.render_widget(Clear, area);
            let items = args.iter().map(|a| ListItem::new(a.as_str())).collect();
            list(f, area, " Run with ", items, *i, true);
        }
    }
}

/// The menu label and what Enter does with it, a rule, then the script with its comments muted.
fn preview(it: &Item, width: u16) -> Paragraph<'static> {
    let mut v = vec![Line::styled(it.label.clone(), Style::new().add_modifier(Modifier::BOLD))];
    let mut does = String::from("enter: ");
    if !it.args.is_empty() {
        does += &format!("choose {}, then ", it.args.join(" | "));
    }
    does += if it.apply { "dry run, asks before --apply" } else { "runs it, no --apply step" };
    v.push(Line::styled(does, Style::new().fg(ACCENT)));
    v.push(Line::styled("─".repeat(width as usize), MUTED));
    for l in it.text.lines() {
        let style = if l.trim_start().starts_with('#') { MUTED } else { Style::new() };
        v.push(Line::styled(l.to_string(), style));
    }
    Paragraph::new(v)
}

/// s cut to w columns, with … when it didn't fit.
fn fit(s: &str, w: usize) -> String {
    if Span::raw(s).width() <= w {
        return s.into();
    }
    let (mut out, mut n) = (String::new(), 0);
    for c in s.chars() {
        let cw = Span::raw(c.to_string()).width();
        if n + cw + 1 > w {
            break;
        }
        n += cw;
        out.push(c);
    }
    out + "…"
}

/// Rounded borders; the focused pane's in the accent colour, the others muted.
fn block(title: String, focused: bool) -> Block<'static> {
    let (border, title_style) = if focused {
        (Style::new().fg(ACCENT), Style::new().fg(ACCENT).add_modifier(Modifier::BOLD))
    } else {
        (MUTED, Style::new())
    };
    Block::bordered().border_type(BorderType::Rounded).border_style(border).title(Span::styled(title, title_style))
}

/// The selection is reversed only in the focused pane (palette colours, readable on light and dark terminals);
/// elsewhere it keeps the marker and turns bold.
fn list(f: &mut Frame, area: Rect, title: &str, items: Vec<ListItem>, sel: usize, focused: bool) {
    let mut state = ListState::default();
    state.select((!items.is_empty()).then_some(sel));
    let mark = if focused { Modifier::REVERSED | Modifier::BOLD } else { Modifier::BOLD };
    let list = List::new(items)
        .block(block(title.into(), focused))
        .highlight_style(Style::new().add_modifier(mark))
        .highlight_symbol("▶ ");
    f.render_stateful_widget(list, area, &mut state);
}

/// A centred box at most 60 columns wide; longer text wraps instead of being cut at the screen edge.
fn popup(f: &mut Frame, title: &str, text: &str, color: Color) {
    let w = (Span::raw(text).width() as u16 + 6).min(60).min(f.area().width.saturating_sub(4));
    let p = Paragraph::new(text).alignment(Alignment::Center).wrap(Wrap { trim: true });
    let area = centered(f.area(), w, p.line_count(w.saturating_sub(4)) as u16 + 2);
    f.render_widget(Clear, area);
    let block = Block::bordered().border_type(BorderType::Rounded).title(title).border_style(Style::new().fg(color));
    f.render_widget(p.block(block.padding(Padding::horizontal(1))), area);
}

fn centered(area: Rect, width: u16, height: u16) -> Rect {
    let x = area.x + area.width.saturating_sub(width) / 2;
    let y = area.y + area.height.saturating_sub(height) / 2;
    Rect { x, y, width: width.min(area.width), height: height.min(area.height) }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn item(stem: &str, apply: bool) -> Item {
        let (file, text) = (format!("{stem}.sh"), String::new());
        Item { stem: stem.into(), file, label: stem.into(), args: vec![], apply, text }
    }

    fn app(hosts: Vec<Host>) -> App {
        App {
            cw: "cw".into(),
            rec: "/nonexistent".into(),
            hosts,
            host: 0,
            item: 0,
            pane: 0,
            scroll: 0,
            mode: Mode::Normal,
            message: String::new(),
            probing: HashSet::new(),
            pulling: false,
            update: None,
        }
    }

    #[test]
    fn offers_the_plugins_version_only_when_it_differs() {
        let root = env::temp_dir().join(format!("cwtfigo-tui-version-{}", std::process::id()));
        let cw = root.join("skills/cwtfigo/scripts/cw");
        assert_eq!(plugin_version(&cw), None);
        fs::create_dir_all(root.join(".claude-plugin")).unwrap();
        fs::write(root.join(".claude-plugin/plugin.json"), "{\n  \"name\": \"cwtfigo\",\n  \"version\": \"0.5.3\",\n}").unwrap();
        assert_eq!(plugin_version(&cw).as_deref(), Some("0.5.3"));
        assert_eq!(update_to(Some("0.5.3"), "0.5.2").as_deref(), Some("update TUI to 0.5.3"));
        assert_eq!(update_to(Some("0.5.10"), "0.5.9").as_deref(), Some("update TUI to 0.5.10"));
        // A curl of the latest release is often newer than a plugin from a lagging marketplace: not an update.
        assert_eq!(update_to(Some("0.5.1"), "0.5.2").as_deref(), Some("switch TUI to 0.5.1"), "cw tui installs the plugin's, older too");
        assert_eq!(update_to(Some("0.5.2"), "0.5.2"), None);
        assert_eq!(update_to(None, "0.5.2"), None);
        let mut a = sample();
        assert!(!screen(&mut a, 80, 24).contains("update TUI"));
        a.update = update_to(plugin_version(&cw).as_deref(), "0.5.2");
        let s = screen(&mut a, 80, 24);
        let bar = s.lines().last().unwrap();
        assert!(bar.contains("u update TUI to 0.5.3") && bar.contains("q quit"), "{bar}");
        a.message = "notes up to date".into();
        let s = screen(&mut a, 80, 24);
        let bar = s.lines().last().unwrap();
        assert!(bar.contains("notes up to date") && bar.contains("u update TUI to 0.5.3"), "a message keeps the offer: {bar}");
        fs::remove_dir_all(&root).unwrap();
    }

    #[test]
    fn yolo_shows() {
        let rec = env::temp_dir().join(format!("cwtfigo-tui-yolo-{}", std::process::id()));
        for h in ["a", "b"] {
            fs::create_dir_all(rec.join("hosts").join(h)).unwrap();
        }
        let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs();
        let yolo = || scan(&rec).iter().map(|h| h.yolo).collect::<Vec<_>>();
        assert_eq!(yolo(), [false, false]);
        fs::write(rec.join("hosts/b/yolo.on"), format!("{now}\n")).unwrap();
        assert_eq!(yolo(), [false, true]);
        let mut a = app(scan(&rec));
        let s = screen(&mut a, 80, 24);
        assert!(s.lines().next().unwrap().contains("YOLO: unapproved scripts run without asking"), "{s}");
        assert!(s.lines().any(|l| l.contains("◌ b  YOLO")) && !s.lines().any(|l| l.contains("◌ a ") && l.contains("YOLO")), "{s}");
        fs::write(rec.join("hosts/b/yolo.on"), format!("{}\n", now - 43200)).unwrap();
        fs::write(rec.join("yolo.on"), "garbled").unwrap();
        assert_eq!(yolo(), [false, false], "12 h old or garbled: off, as in cw");
        fs::write(rec.join("yolo.on"), format!("{now}")).unwrap();
        assert_eq!(yolo(), [true, true], "the record's yolo.on is every machine's");
        fs::remove_dir_all(&rec).unwrap();
    }

    #[test]
    fn what_the_tui_does_is_saved() {
        let d = env::temp_dir().join(format!("cwtfigo-tui-save-{}", std::process::id()));
        fs::create_dir_all(d.join("rec/hosts/b")).unwrap();
        fs::write(d.join("cw"), "printf '%s|' \"$@\" > \"$0.args\"\n").unwrap();
        let mut a = app(vec![host("b", vec![])]);
        (a.cw, a.rec) = (d.join("cw"), d.join("rec"));
        let log = d.join("rec/hosts/b/log.md");
        let entries = || fs::read_to_string(&log).unwrap().lines().filter(|l| l.starts_with("## ")).map(|l| l.ends_with(" tui")).collect::<Vec<_>>();
        assert!(note(&a, "b", "approved fix").status().unwrap().success());
        assert_eq!(fs::read_to_string(d.join("cw.args")).unwrap(), "save|tui: approved fix on b|");
        assert!(fs::read_to_string(&log).unwrap().contains("- approved fix (in the TUI)\n"));
        fs::write(&log, "# log\n\n## 2026-11-01 visit\n- x\n").unwrap();
        note(&a, "b", "ran maintain --apply: exit 0");
        let text = fs::read_to_string(&log).unwrap();
        assert!(text.starts_with("# log\n\n## ") && text.contains("- ran maintain --apply: exit 0"), "{text}");
        assert_eq!(entries(), [true, false], "newest first");
        fs::write(&log, "## 2026-11-01 visit\n").unwrap();
        note(&a, "b", "approved fix");
        assert_eq!(entries(), [true, false]);
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn ctrl_c_quits() {
        let k = |c, m| KeyEvent::new(KeyCode::Char(c), m);
        assert!(quits(k('c', KeyModifiers::CONTROL)) && quits(k('d', KeyModifiers::CONTROL)) && quits(k('q', KeyModifiers::NONE)));
        assert!(quits(KeyEvent::new(KeyCode::Esc, KeyModifiers::NONE)));
        assert!(!quits(k('c', KeyModifiers::NONE)) && !quits(k('r', KeyModifiers::CONTROL)));
    }

    #[cfg(unix)]
    #[test]
    fn no_update_offer_for_a_linked_build() {
        let home = env::temp_dir().join(format!("cwtfigo-tui-link-{}", std::process::id()));
        fs::create_dir_all(home.join(".local/bin")).unwrap();
        assert!(!own_build(&home));
        fs::write(home.join(".local/bin/cwtfigo"), "").unwrap();
        assert!(!own_build(&home), "a downloaded binary gets the offer");
        fs::remove_file(home.join(".local/bin/cwtfigo")).unwrap();
        std::os::unix::fs::symlink(home.join("target/release/cwtfigo-tui"), home.join(".local/bin/cwtfigo")).unwrap();
        assert!(own_build(&home));
        fs::remove_dir_all(&home).unwrap();
    }

    fn host(name: &str, items: Vec<Item>) -> Host {
        Host { name: name.into(), here: false, os: None, online: None, yolo: false, items }
    }

    #[test]
    fn confirm_keeps_its_target_when_the_lists_change() {
        let mut a = app(vec![host("b", vec![item("check", false), item("maintain", true)])]);
        a.item = 1;
        let t = target(&a, Some("guard".into()));
        // A pull adds a machine in front and the script list goes empty: index-based lookup would hit "a" or panic.
        a.hosts = vec![host("a", vec![item("x", true)]), host("b", vec![])];
        after(&mut a, t.clone(), false, false, Ok(Some(0)));
        assert!(matches!(&a.mode, Mode::Confirm(_, Then::Apply(u)) if *u == t));
        after(&mut a, t.clone(), true, true, Ok(Some(3)));
        // cw stopped an --apply run on a changed script: the approve doesn't carry --apply over.
        assert!(matches!(&a.mode, Mode::Confirm(_, Then::Approve(u)) if *u == t));
        assert_eq!(t.name, "b");
        assert_eq!(t.stem, "maintain");
    }

    #[test]
    fn cw_comes_from_the_live_plugin_install() {
        // Shape Claude Code writes: other plugins around it, a project install listed before the user one.
        let json = r#"{
  "version": 2,
  "plugins": {
    "caveman@caveman": [
      { "scope": "user", "installPath": "/h/.claude/plugins/cache/caveman/caveman/0d95", "version": "0d95" }
    ],
    "cwtfigo@cwtfigo": [
      {
        "scope": "project",
        "projectPath": "/h/p",
        "installPath": "/h/.claude/plugins/cache/cwtfigo/cwtfigo/0.4.8",
        "version": "0.4.8"
      },
      {
        "scope": "user",
        "installPath": "/h/.claude/plugins/cache/cwtfigo/cwtfigo/0.4.9",
        "version": "0.4.9",
        "installedAt": "2026-11-01T00:00:00.000Z"
      }
    ],
    "zz@zz": [{"scope":"user","installPath":"/h/zz"}]
  }
}"#;
        let cw = |v: &str| PathBuf::from(format!("/h/.claude/plugins/cache/cwtfigo/cwtfigo/{v}/skills/cwtfigo/scripts/cw"));
        assert_eq!(installed_cw(json), [cw("0.4.9"), cw("0.4.8")]);
        assert_eq!(installed_cw(r#"{"plugins":{"cwtfigo@cwtfigo":[{"installPath":"/a"},{"installPath":"/b"}]}}"#).len(), 2);
        assert!(installed_cw(r#"{"plugins":{"caveman@caveman":[]}}"#).is_empty());
        assert!(installed_cw("").is_empty());
    }

    #[test]
    fn a_name_that_does_not_resolve_is_unknown_not_offline() {
        let l = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let port = l.local_addr().unwrap().port();
        assert_eq!(reach("127.0.0.1", port), Some(true));
        drop(l);
        assert_eq!(reach("127.0.0.1", port), Some(false), "resolves, nothing listens: offline");
        // .invalid never resolves (RFC 6761), as a .local name doesn't through musl's resolver.
        assert_eq!(reach("cwtfigo-test.invalid", 22), None);
    }

    #[test]
    fn build_path_only_in_debug_builds() {
        // cargo test --release checks the release side: no CI runner path to fall back on or print.
        assert_eq!(DEV_CW.is_some(), cfg!(debug_assertions));
    }

    #[test]
    fn menu_shows_the_file_cw_runs() {
        let d = env::temp_dir().join(format!("cwtfigo-tui-ext-{}", std::process::id()));
        fs::create_dir_all(&d).unwrap();
        fs::write(d.join("check.sh"), "# check\n").unwrap();
        fs::write(d.join("check.ps1"), "# check\n").unwrap();
        let files = |x| items(&d, x).into_iter().map(|i| i.file).collect::<Vec<_>>();
        assert_eq!(os(&d), None);
        assert_eq!(ext(os(&d).as_deref(), false), None);
        assert_eq!(files(None).len(), 2);
        fs::write(d.join("device.json"), "{\n  \"os\":  \"windows\",\n}").unwrap();
        assert_eq!(os(&d).as_deref(), Some("windows"));
        assert_eq!(ext(os(&d).as_deref(), false), Some("ps1"));
        assert_eq!(files(Some("ps1")), ["check.ps1"]);
        fs::write(d.join("device.json"), "{\"os\": \"arch\"}").unwrap();
        assert_eq!(os(&d).as_deref(), Some("arch"));
        assert_eq!(ext(os(&d).as_deref(), true), Some("sh"));
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn only_cw_asks_for_approval() {
        let rec = env::temp_dir().join(format!("cwtfigo-tui-approve-{}", std::process::id()));
        let h = rec.join("hosts/b");
        fs::create_dir_all(&h).unwrap();
        fs::write(h.join("fix.sh"), "#!/bin/sh\nexit 3\n").unwrap();
        fs::write(h.join("approved.sha256"), "").unwrap();
        let t = Target { name: "b".into(), stem: "fix".into(), file: "fix.sh".into(), arg: None, can_apply: false };
        assert!(!approved(&rec, &t));
        let sum = "bb6220bfa599c6294ebc0954c2781c5513b565eb55f01aba387bfd0dc90176b1"; // of fix.sh above
        fs::write(h.join("approved.sha256"), format!("{sum}  fix  2026-11-07\n")).unwrap();
        assert!(approved(&rec, &t));
        let mut a = app(vec![host("b", vec![item("fix", false)])]);
        after(&mut a, t.clone(), false, false, Ok(Some(3)));
        assert!(matches!(a.mode, Mode::Normal));
        assert_eq!(a.message, "fix on b: exit 3");
        after(&mut a, t, false, false, Ok(Some(4)));
        assert!(matches!(a.mode, Mode::Normal));
        assert_eq!(a.message, "fix on b: exit 4");
        fs::remove_dir_all(&rec).unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn ctrl_c_stops_the_script_not_the_tui() {
        survive_ctrl_c();
        unsafe { libc::raise(libc::SIGINT) };
        let s = Command::new("sh").args(["-c", "kill -INT $$; exit 0"]).status().unwrap();
        assert_eq!(s.code(), None, "the child must still die of SIGINT");
    }

    /// The screen as text, one line per row: wide characters take one char, not their cells.
    fn screen(a: &mut App, w: u16, h: u16) -> String {
        let mut t = ratatui::Terminal::new(ratatui::backend::TestBackend::new(w, h)).unwrap();
        t.draw(|f| draw(f, a)).unwrap();
        let view = t.backend().to_string();
        let rows = view.lines().map(|l| {
            let l = &l[1..];
            l.split_once("\" Hidden by").map_or(&l[..l.len() - 1], |p| p.0).trim_end().to_string()
        });
        rows.collect::<Vec<_>>().join("\n")
    }

    fn sample() -> App {
        let mut check = item("check", false);
        check.text = "#!/bin/sh\n# check.sh (debian): READ-ONLY.\necho hi\n".into();
        let mut up = item("upkeep", true);
        up.label = "更新和清理".into();
        up.args = vec!["guard".into(), "restore".into()];
        let mut me = host("kettle", vec![item("check", false)]);
        me.here = true;
        let mut attic = host("attic", vec![check, up]);
        attic.online = Some(true);
        attic.os = Some("debian".into());
        let mut den = host("den", vec![]);
        den.online = Some(false);
        app(vec![attic, me, den])
    }

    #[test]
    fn layout_at_80x24() {
        let s = screen(&mut sample(), 80, 24);
        for want in ["Machines", "attic", "debian", "kettle", "den", "Menu", "更新和清理", "check.sh", "READ-ONLY", "upkeep.sh · --apply", "q quit", "2/3 online"] {
            assert!(s.contains(want), "{want:?} missing from\n{s}");
        }
        let mut a = sample();
        a.message = "check on attic: exit 2".into();
        assert!(screen(&mut a, 80, 24).lines().last().unwrap().contains("exit 2"), "a message takes the key bar's place");
        a.scroll = 1000;
        let s = screen(&mut a, 80, 24);
        assert_eq!(a.scroll, 0, "a short script doesn't scroll");
        assert!(s.contains("enter: runs it") && s.contains("echo hi"));
        a.item = 1;
        let s = screen(&mut a, 80, 24);
        assert!(s.contains("enter: choose guard |") && s.contains("--apply"), "{s}");
        a.item = 0;
        a.hosts[0].items[0].text = (0..100).map(|i| format!("echo {i}\n")).collect();
        a.scroll = 1000;
        let s = screen(&mut a, 80, 24);
        assert!(s.contains("echo 99") && !s.contains("echo 70"), "PgDn stops at the last page\n{s}");
        a.message.clear();
        let long = "Approve a script with a name long enough that its confirm runs past sixty columns? y/N";
        a.mode = Mode::Confirm(long.into(), Then::Apply(target(&a, None)));
        let s = screen(&mut a, 80, 24);
        assert!(s.contains("Confirm") && s.contains("Approve a") && s.contains("y/N"), "a long popup wraps\n{s}");
        assert!(s.lines().last().unwrap().contains("any other key"), "the key bar follows the mode");
        a.mode = Mode::Normal;
        a.host = 2;
        assert!(screen(&mut a, 80, 24).contains("Nothing to run here yet."));
        screen(&mut sample(), 30, 8); // tiny terminals must not panic
    }

    /// Prints the screen for a real record: CWTFIGO_HOME=<copy> SNAP_HOST=den cargo test dump -- --ignored --nocapture
    #[test]
    #[ignore]
    fn dump() {
        let rec = PathBuf::from(env::var("CWTFIGO_HOME").unwrap());
        let mut a = app(hosts(&rec));
        a.rec = rec;
        let (tx, rx) = mpsc::channel();
        refresh(&mut a, &tx);
        while let Ok(m) = rx.recv_timeout(Duration::from_secs(2)) {
            got(&mut a, m);
        }
        let want = env::var("SNAP_HOST").unwrap_or_default();
        a.host = a.hosts.iter().position(|h| h.name == want).unwrap_or(0);
        a.item = env::var("SNAP_ITEM").ok().and_then(|i| i.parse().ok()).unwrap_or(0);
        a.pane = env::var("SNAP_PANE").ok().and_then(|i| i.parse().ok()).unwrap_or(0);
        let (w, h) = (env::var("SNAP_W").map_or(80, |v| v.parse().unwrap()), env::var("SNAP_H").map_or(24, |v| v.parse().unwrap()));
        println!("{}", screen(&mut a, w, h));
    }

    #[test]
    fn fit_counts_columns() {
        assert_eq!(fit("check", 5), "check");
        assert_eq!(fit("checks", 5), "chec…");
        assert_eq!(fit("更新和清理", 6), "更新…"); // 2 columns each
        assert_eq!(fit("abc", 0), "…");
    }

    #[test]
    fn hints() {
        assert!(hint(255, false, false).contains("ssh"));
        assert_eq!(hint(255, true, false), "");
        assert!(hint(1, false, true).contains("adapt"));
        assert_eq!(hint(1, false, false), "");
        assert_eq!(hint(2, false, true), "");
    }

    #[test]
    fn one_probe_per_machine_at_a_time() {
        let mut me = host("me", vec![]);
        me.here = true;
        let mut a = app(vec![host("a", vec![]), me]);
        assert_eq!(due(&mut a), ["a"]);
        assert!(due(&mut a).is_empty());
        a.probing.remove("a");
        assert_eq!(due(&mut a), ["a"]);
    }

    #[test]
    fn a_pull_keeps_the_selection() {
        let rec = env::temp_dir().join(format!("cwtfigo-tui-keep-{}", std::process::id()));
        fs::create_dir_all(rec.join("hosts/b")).unwrap();
        for f in ["check.sh", "fix.sh"] {
            fs::write(rec.join("hosts/b").join(f), "# menu: x\n").unwrap();
        }
        let mut a = app(scan(&rec));
        a.rec = rec.clone();
        a.item = 1; // fix
        // The pull brings a machine in front and a script before fix.
        fs::create_dir_all(rec.join("hosts/a")).unwrap();
        fs::write(rec.join("hosts/b/deploy.sh"), "# menu: x\n").unwrap();
        rescan(&mut a);
        assert_eq!((a.hosts[a.host].name.as_str(), a.hosts[a.host].items[a.item].stem.as_str()), ("b", "fix"));
        fs::remove_dir_all(&rec).unwrap();
    }

    #[test]
    fn pull_message() {
        assert_eq!(pulled(true, ""), "notes up to date");
        assert_eq!(pulled(true, "hint: some other hint\n"), "notes up to date");
        let ssh = "ssh: connect to host home port 22: Operation timed out\nfatal: Could not read from remote repository.\n\n\
                   Please make sure you have the correct access rights\nand the repository exists.\n\
                   cw: pull failed, using local record\nhint: ...\n";
        assert_eq!(pulled(true, ssh), "couldn't get the latest notes: ssh: connect to host home port 22: Operation timed out");
        assert_eq!(pulled(true, "cw: pull failed, using local record\n"), "couldn't get the latest notes: cw: pull failed, using local record");
        assert_eq!(pulled(false, "cw: no record at /x\n"), "couldn't get the latest notes: cw: no record at /x");
        assert_eq!(pulled(false, ""), "couldn't get the latest notes: cw status failed");
    }

    #[test]
    fn no_record_no_pull() {
        let d = env::temp_dir().join(format!("cwtfigo-tui-nogit-{}", std::process::id()));
        fs::create_dir_all(&d).unwrap();
        fs::write(d.join("cw"), "touch \"$0.ran\"\n").unwrap();
        let mut a = app(vec![host("b", vec![])]);
        (a.cw, a.rec) = (d.join("cw"), d.join("none"));
        let (tx, rx) = mpsc::channel();
        pull(&mut a, &tx);
        assert!(!a.pulling && rx.recv_timeout(Duration::from_millis(300)).is_err());
        assert_eq!(a.message, "");
        assert!(!d.join("cw.ran").exists() && !d.join("none").exists(), "cw status ran: it would git-init the record");
        // A record on one computer alone, no remote: nothing to pull, and no "record pulled" at every start.
        a.rec = d.join("rec");
        assert!(Command::new("git").args(["init", "-q"]).arg(&a.rec).status().unwrap().success());
        pull(&mut a, &tx);
        assert!(!a.pulling && rx.recv_timeout(Duration::from_millis(300)).is_err() && a.message.is_empty());
        assert!(!d.join("cw.ran").exists(), "cw status ran with no remote");
        fs::remove_dir_all(&d).unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn pull_runs_behind_the_ui() {
        let d = env::temp_dir().join(format!("cwtfigo-tui-pull-{}", std::process::id()));
        fs::create_dir_all(d.join("hosts/b")).unwrap();
        assert!(Command::new("git").args(["init", "-q"]).arg(&d).status().unwrap().success());
        assert!(Command::new("git").arg("-C").arg(&d).args(["remote", "add", "origin", "/nonexistent"]).status().unwrap().success());
        // A slow Home. No terminal: stdin is closed, no /dev/tty (checked only when the test runs in one), git may not prompt.
        let cw = "sleep 1; : 2>/dev/null </dev/tty && echo got-tty >&2; read x && echo got-stdin >&2\n\
                  echo \"prompt=$GIT_TERMINAL_PROMPT\" >&2\n\
                  echo 'cw: pull failed, using local record' >&2\n";
        fs::write(d.join("cw"), cw).unwrap();
        let mut a = app(vec![host("b", vec![])]);
        (a.cw, a.rec) = (d.join("cw"), d.clone());
        let (tx, rx) = mpsc::channel();
        let t = Instant::now();
        pull(&mut a, &tx);
        pull(&mut a, &tx); // one at a time
        assert!(t.elapsed() < Duration::from_millis(500), "pull blocked the UI");
        assert!(rx.try_recv().is_err());
        got(&mut a, rx.recv_timeout(Duration::from_secs(10)).unwrap());
        assert_eq!(a.message, "couldn't get the latest notes: prompt=0");
        assert!(!a.pulling);
        assert!(rx.recv_timeout(Duration::from_millis(1500)).is_err(), "a second status ran");
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn empty_record_shows_this_machine() {
        let rec = env::temp_dir().join(format!("cwtfigo-tui-empty-{}", std::process::id()));
        let one = |rec: &Path| {
            let h = hosts(rec);
            assert_eq!(h.len(), 1);
            assert!(h[0].here && h[0].items.is_empty() && !h[0].name.is_empty());
            h.into_iter().next().unwrap()
        };
        // No record at all: the name cw will give it on the first visit, worked out as cw does.
        let cw = "if [ \"$(uname -s)\" = Darwin ]; then n=$(scutil --get LocalHostName 2>/dev/null); else n=$(hostname -s 2>/dev/null); fi; \
                  [ -n \"$n\" ] || n=$(hostname); printf %s \"$n\" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-'";
        let want = String::from_utf8(Command::new("sh").args(["-c", cw]).output().unwrap().stdout).unwrap();
        assert_eq!(one(&rec).name, if want.is_empty() || want == "local" { "this computer" } else { &want });
        fs::create_dir_all(rec.join("hosts")).unwrap();
        fs::write(rec.join("self"), "kettle\n").unwrap();
        let mut a = app(vec![one(&rec)]);
        a.rec = rec.clone();
        assert_eq!(a.hosts[0].name, "kettle");
        let s = screen(&mut a, 80, 24);
        for want in ["kettle", "Start", "\"CWTFIGO\"", "Nothing to run here yet.", "Tell Claude."] {
            assert!(s.contains(want), "{want:?} missing from\n{s}");
        }
        // SKILL.md's words not to use with a new owner, and the menu-line advice a first-timer can't act on.
        for jargon in ["record", "join", "ssh-alias", "menu:", "`"] {
            assert!(!s.contains(jargon), "{jargon:?} on the first-run screen\n{s}");
        }
        rescan(&mut a); // still empty: the stand-in stays
        assert_eq!(a.hosts[0].name, "kettle");
        fs::create_dir_all(rec.join("hosts/kettle")).unwrap();
        fs::write(rec.join("hosts/kettle/check.sh"), "# check\n").unwrap();
        rescan(&mut a); // after the first visit: the real one
        assert_eq!(a.hosts[0].items.len(), 1);
        fs::remove_dir_all(&rec).unwrap();
    }

    #[test]
    fn a_machine_with_no_menu_says_how_it_gets_one() {
        let rec = env::temp_dir().join(format!("cwtfigo-tui-nomenu-{}", std::process::id()));
        fs::create_dir_all(rec.join("hosts/den")).unwrap();
        fs::write(rec.join("hosts/den/device.json"), "{\"os\": \"arch\"}").unwrap(); // collected, nothing else
        let mut a = app(scan(&rec));
        a.rec = rec.clone();
        let s = screen(&mut a, 80, 24);
        assert!(s.contains("Nothing to run here yet.") && s.contains("Start"), "{s}");
        assert!(start_hint(&rec, &a.hosts[0]).starts_with("Nothing to run on den yet.\n\nIn Claude Code, say \"CWTFIGO\": it writes scripts to check den "));
        a.hosts[0].here = true;
        assert!(start_hint(&rec, &a.hosts[0]).starts_with("Nothing to run on this computer yet."));
        fs::remove_dir_all(&rec).unwrap();
    }

    #[test]
    fn arguments() {
        let a = |v: &[&str]| cli(&v.iter().map(|s| s.to_string()).collect::<Vec<_>>());
        assert_eq!(a(&[]), Ok(None));
        assert_eq!(a(&["--version"]), Ok(Some(format!("cwtfigo {}", env!("CARGO_PKG_VERSION")))));
        let help = a(&["--help"]).unwrap().unwrap();
        assert!(help.starts_with(USAGE) && help.contains("tui/README.md"), "{help}");
        let e = a(&["-x"]).unwrap_err();
        assert_eq!(e.lines().collect::<Vec<_>>(), ["cwtfigo: unknown argument -x", USAGE]);
        assert!(a(&["--version", "x"]).unwrap_err().ends_with(USAGE));
    }

    #[test]
    fn apply_before_menu_arg() {
        let t = Target {
            name: "b".into(),
            stem: "maintain".into(),
            file: "maintain.sh".into(),
            arg: Some("guard".into()),
            can_apply: true,
        };
        assert_eq!(run_args(&t, true), ["run", "b", "maintain", "--apply", "guard"]);
        assert_eq!(run_args(&t, false), ["run", "b", "maintain", "guard"]);
    }
}
