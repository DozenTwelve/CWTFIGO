#!/bin/sh
# Probe: load, memory, disks, failed units. Read-only. Run when a request is about slowness, space or "something's off".
exec 2>/dev/null
has() { command -v "$1" >/dev/null 2>&1; }
sec() { [ -n "$open" ] && echo '```'; echo; echo "## $1"; echo '```'; open=1; }

sec uptime
uptime

sec memory
if has free; then free -m; elif has vm_stat; then vm_stat | head -6; fi

sec disks
df -h | grep -v -E '^(tmpfs|devtmpfs|overlay|shm|map |devfs)'

sec failed-units
has systemctl && systemctl --failed --no-legend --plain

echo '```'
exit 0
