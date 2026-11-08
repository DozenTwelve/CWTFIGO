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
            h.args = m.split('|').map(|a| a.trim().to_string()).filter(|a| !a.is_empty()).collect();
        } else if let Some(m) = c.strip_prefix("menu:") {
            h.menu = Some(m.trim().to_string());
        } else if h.about.is_none() && !c.is_empty() {
            h.about = Some(c.to_string());
        }
    }
    // Takes --apply only if code compares an argument to it; a comment or an echo that mentions it doesn't count.
    h.apply = text.lines().filter(|l| !l.trim_start().starts_with('#')).any(|l| {
        let l = l.replace(['"', '\''], "");
        l.contains("= --apply") || l.contains("--apply)") || l.contains("-contains --apply")
    });
    h
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
    }

    #[test]
    fn bom() {
        assert_eq!(parse("\u{feff}# menu: upkeep\n").menu.as_deref(), Some("upkeep"));
    }
}
