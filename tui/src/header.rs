//! What a host script's header says: `# menu:`, `# menu-args: a | b`, its first comment line, and whether it takes --apply.

#[derive(Debug, Default, PartialEq)]
pub struct Header {
    pub menu: Option<String>,
    pub args: Vec<String>,
    pub about: Option<String>,
    pub apply: bool,
}

pub fn parse(text: &str) -> Header {
    let mut h = Header::default();
    let text = text.strip_prefix('\u{feff}').unwrap_or(text); // Windows editors save .ps1 with a BOM
    // The header is the leading comment block (shebang included); menu lines sit right under the first comment line.
    for line in text.lines().map(str::trim).take_while(|l| l.starts_with('#')) {
        if line.starts_with("#!") {
            continue;
        }
        let c = line.trim_start_matches('#').trim();
        if let Some(m) = c.strip_prefix("menu-args:") {
            // A word starting with - would be an option (--apply on the dry run, no y/N), one with = zsh expands: dropped,
            // as cw hermes does.
            h.args = m.split('|').map(|a| a.trim().to_string()).filter(|a| !a.is_empty() && !a.starts_with(['-', '='])).collect();
        } else if let Some(m) = c.strip_prefix("menu:") {
            h.menu = Some(m.trim().to_string());
        } else if h.about.is_none() && !c.is_empty() {
            h.about = Some(c.to_string());
        }
    }
    // Takes --apply only if code compares an argument to it; a comment or an echo that mentions it doesn't count.
    // Quotes out: [ $1 = --apply ], [ --apply = $1 ], a case pattern, PowerShell's -contains and -eq. As cw hermes
    // reads it (cw's awk): tests/menu-headers.txt holds a case per shape for both.
    h.apply = text.lines().filter(|l| !l.trim_start().starts_with('#')).any(|l| {
        let l = l.replace(['"', '\''], "");
        ["= --apply", "[ --apply =", "-contains --apply", "-eq --apply"].iter().any(|p| l.contains(p)) || case_pattern(&l)
    });
    h
}

/// --apply in a case pattern: right before the ), or with other words up to it, as in -y|--apply) and --apply|-y).
fn case_pattern(l: &str) -> bool {
    l.match_indices("--apply").any(|(i, m)| {
        let rest = &l[i + m.len()..];
        rest.find([' ', '\t', ')']).is_some_and(|end| rest[end..].starts_with(')') && (end == 0 || rest.starts_with('|')))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn menu_args_apply() {
        let h = parse("#!/bin/sh\n# attic: routine upkeep.\n# menu: 更新和清理\n# menu-args: guard | restore\n# more\nAPPLY=; [ \"$1\" = --apply ] && APPLY=1\n# menu: not header\n");
        assert_eq!(h.menu.as_deref(), Some("更新和清理"));
        assert_eq!(h.args, ["guard", "restore"]);
        assert_eq!(h.about.as_deref(), Some("attic: routine upkeep."));
        assert!(h.apply);
    }

    #[test]
    fn first_comment_skips_empty_and_plain_mentions_dont_apply() {
        let h = parse("#!/bin/sh\n#\n# check.sh (macOS): READ-ONLY.\nexec 2>/dev/null\necho \"re-run x.sh --apply\"\n");
        assert_eq!(h.menu, None);
        assert!(h.args.is_empty());
        assert_eq!(h.about.as_deref(), Some("check.sh (macOS): READ-ONLY."));
        assert!(!h.apply);
    }

    #[test]
    fn apply_forms() {
        assert!(parse("[ \"$2\" = \"--apply\" ] || exit 0").apply);
        assert!(parse("case $1 in --apply) a=1 ;; esac").apply);
        assert!(parse("$APPLY = $args -contains '--apply'").apply);
        assert!(!parse("# --apply = do it").apply);
        assert!(parse("case $1 in\n  --apply|-y|--yes) a=1 ;;\nesac").apply);
        assert!(parse("case $1 in -y|--apply) a=1 ;; esac").apply);
        assert!(parse("[ \"--apply\" = \"$1\" ] && a=1").apply);
        assert!(parse("if ($args[0] -eq '--apply') { $a = $true }").apply);
        assert!(!parse("echo \"usage: x [--apply|-n]\"").apply);
        assert!(!parse("echo \"--apply | tee log (see the notes)\"").apply);
    }

    #[test]
    fn menu_args_no_options() {
        assert_eq!(parse("# x\n# menu-args: 照片 | --apply | 两 个 | -n | =x | a=b\n").args, ["照片", "两 个", "a=b"]);
    }

    #[test]
    fn shared_fixture() {
        // The headers tests/cw.sh gives cw hermes: the TUI and Hermes must offer the same menu. As items() reads a check.sh.
        for case in include_str!("../../tests/menu-headers.txt").split("\n@@ ").skip(1) {
            let (want, text) = case.split_once('\n').unwrap_or((case, ""));
            let h = parse(&text.replace('\t', "    "));
            let label = h.menu.or(h.about).unwrap_or_else(|| "check".into());
            let got = format!("{label} @@ {} @@ {}", h.args.join(" | "), if h.apply { "yes" } else { "no" });
            assert_eq!(got, want);
        }
    }

    #[test]
    fn bom() {
        assert_eq!(parse("\u{feff}# menu: upkeep\n").menu.as_deref(), Some("upkeep"));
    }
}
