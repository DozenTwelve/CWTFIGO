# macOS

- Security updates: https://support.apple.com/en-us/100100 (Apple security releases).
- Logs survive a forced restart: `/usr/bin/log show --start "<time>" --style compact`. A gap in the log marks a hang.
- `/Library/Logs/DiagnosticReports/`: `shutdown_stall`, `ResetCounter-*.diag` (field `Boot faults` says whether the power button was held), disk-write reports. Decode with `spindump -i <report> -o out.txt`.
- High load for ~15 minutes after a restart is normal (iCloud keychain sync, Spotlight). Don't call it a fault.
- Software installed by `.pkg` installers is outside Homebrew; `pkgutil --pkgs` and `pkgutil --files <id>` say who owns a file.
- `tmutil localsnapshot` pins every byte freed after it: a cleanup behind a local snapshot shows no gain until `tmutil deletelocalsnapshots <date>`. List them with `tmutil listlocalsnapshots /`.
- `networkQuality -s` vs `networkQuality -s -I en0`: same numbers means traffic is not going through a proxy/VPN/TUN. Apple's built-in speed test, no install.
- `mise doctor` inside a `uv run` environment: the temporary venv sits first in PATH, so it warns about a PATH order the user doesn't have. Check with the user's own PATH, not the one `uv run` built.
