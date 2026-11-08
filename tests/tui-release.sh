#!/bin/sh
# The install line's asset name matches what tui-release.yml uploads. Usage: sh tests/tui-release.sh
set -u
cd "$(dirname "$0")/.."
W=.github/workflows/tui-release.yml
fail() { echo "FAIL: $*"; exit 1; }
for u in Darwin-arm64 Darwin-x86_64 Linux-x86_64 Linux-aarch64; do
  grep -q "uname: $u," "$W" || fail "workflow matrix lacks uname $u"
done
grep -q 'name="cwtfigo-tui-${{ matrix.uname }}"' "$W" || fail "workflow tarball not named cwtfigo-tui-<uname>"
grep -q 'dist/pkg/cwtfigo$' "$W" || fail "workflow binary not packed as cwtfigo"
line='curl -fsSL https://github.com/DozenTwelve/CWTFIGO/releases/latest/download/cwtfigo-tui-$(uname -s)-$(uname -m).tar.gz | tar -xz -C ~/.local/bin cwtfigo'
for f in tui/README.md README.md; do
  grep -qF "$line" "$f" || fail "$f lacks the install line"
  grep -qF 'say "CWTFIGO install the TUI"' "$f" || fail "$f doesn't say Claude Code can install it"
done
# The model installs through cw tui, the plugin's own version, never latest.
grep -qF 'sh <skill>/scripts/cw tui' skills/cwtfigo/SKILL.md || fail "SKILL.md doesn't install the TUI with cw tui"
grep -q 'releases/latest' skills/cwtfigo/SKILL.md && fail "SKILL.md still has the curl line"
# cw tui fetches tui-v<plugin version>: every plugin bump bumps the TUI to the same version and gets that tag.
pv=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' .claude-plugin/plugin.json); tv=$(sed -n 's/^version = "\(.*\)"$/\1/p' tui/Cargo.toml)
[ -n "$pv" ] && [ "$pv" = "$tv" ] || fail "tui/Cargo.toml is $tv, .claude-plugin/plugin.json $pv: keep them equal"
# CI builds with --locked: a lock still on the old version fails the release, and no tui-v<version> appears.
lv=$(awk '/^name = "cwtfigo-tui"$/ { getline; sub(/^version = "/, ""); sub(/"$/, ""); print }' tui/Cargo.lock)
[ "$lv" = "$pv" ] || fail "tui/Cargo.lock has cwtfigo-tui $lv, .claude-plugin/plugin.json $pv: run cargo build in tui/"
# The release refuses a tag that isn't Cargo.toml's version, and a push to main fails while its version has no tag.
grep -qF '"${GITHUB_REF_NAME#tui-v}"' "$W" || fail "workflow doesn't check the tag against Cargo.toml"
grep -qF 'ls-remote --exit-code --tags origin "refs/tags/tui-v$v"' "$W" || fail "workflow doesn't check main's version has its tag"
echo "ok"
