# CWTFIGO-FOUNDATION: adapt to this host from its record, then delete this line. cw won't approve it before.
#
# maintain.ps1 (Windows): updates and cleanup for this host. PowerShell 5.1, ASCII only.
#   no argument: dry run. Lists pending upgrades and what each cleanup item would free. Changes nothing
#                except refreshing package indexes (scoop update pulls scoop and its buckets).
#   --apply:     upgrade what UPDATE names, clean the items in CLEAN, report space freed.
#                cw doesn't elevate. If the session is already admin (an admin account over SSH gets an elevated
#                token), admin-only steps run directly; if not, each prints its command for the human to run in an
#                admin PowerShell. The dry run's first line says which.
#
# This is where the host's habits live. Edit CLEAN and UPDATE to fit the machine and its owner;
# an item missing here is never cleaned, whatever the dry run shows.
$CLEAN = 'usertemp winget scoop choco npm pip'
$UPDATE = 'winget scoop choco'
# winget ids --apply leaves alone; the dry run marks them [held]. Git and VS Code are often in use during a visit (cw's
# own shell runs on Git for Windows, whose installer then aborts). Add every package whose pending upgrade is a major
# version jump the owner hasn't chosen (Node.js 24 -> 26). To keep one out for good: winget pin add <id>.
$HOLD = @('Git.Git', 'Microsoft.VisualStudioCode')
# choco packages --apply leaves alone (choco --except). python and python3 are meta packages that follow the newest
# Python: upgrading them installs a new pythonXYZ beside the old one and moves python on PATH. For good: choco pin add -n python.
$CHOCO_HOLD = 'python,python3'
# Add desktop to UPDATE to remove the desktop shortcuts the upgrades add (OBS and Epic Games Launcher drop one on the
# Public desktop each time). Off by default: some owners want them.
#
# Items the dry run knows (on = in CLEAN):
#   usertemp    files in %TEMP% older than 7 days (counts old files of winget and choco below too)
#   winget      winget's installer downloads (%TEMP%\WinGet)
#   scoop       scoop's download cache and old app versions (scoop cache rm, scoop cleanup); size is the cache only
#   choco       choco's download cache (%TEMP%\chocolatey)
#   npm pip     package manager caches (re-downloaded when needed)
#   wudownload  Windows Update downloads (SoftwareDistribution\Download), re-downloaded if still needed. Admin.
#   recyclebin  empty the Recycle Bin on every drive. User data, irreversible. Only when the owner asked.
# Never touched: Windows.old, the component store (DISM), restore points: each ends a way back, ask separately.

$APPLY = $args -contains '--apply'
$ErrorActionPreference = 'SilentlyContinue'
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
function has($c) { [bool](Get-Command $c) }
function on($list, $x) { ($list -split ' ') -contains $x }
function sec($m) { ''; "## $m" }
function mb($bytes) { "$([math]::Round($bytes / 1MB))M" }
function freemb { [math]::Round((Get-PSDrive $env:SystemDrive.TrimEnd(':')).Free / 1MB) }
function strip { process { $_ -replace '^.*\r', '' } }   # winget redraws its spinner with carriage returns
# A winget row's id: names have spaces, ids don't. Rows end in id, version, available, source; a version can be "< 1.2".
function wgid($row) { $w = -split $row; $i = $w.Count - 4; if ($w[$i] -match '^[<>]$') { $i-- }; $w[$i] }

# Size of the files under a path (only those older than $days if given); says so when listing it was denied.
function size($path, $days) {
  if (-not $path -or -not (Test-Path $path)) { return }
  $e = $null
  $f = @(Get-ChildItem $path -Recurse -File -Force -ErrorVariable e)
  if ($days) { $cut = (Get-Date).AddDays(-$days); $f = @($f | Where-Object { $_.LastWriteTime -lt $cut }) }
  $s = mb ($f | Measure-Object Length -Sum).Sum
  if (-not $e) { $s } elseif ($f.Count) { "$s+ (part unreadable)" } else { 'unreadable without admin' }
}

# item <name> <size> <action> [admin]: one dry-run line; on --apply, clean if the item is in CLEAN.
function item($name, $size, $act, $needAdmin) {
  if (-not $size) { return }
  $state = 'off'; if (on $CLEAN $name) { $state = 'on' }
  '{0,-11} {1,-4} {2}' -f $name, $state, $size
  if (-not $APPLY -or $state -ne 'on') { return }
  $cmd = $act.ToString().Trim()
  if ($needAdmin -and -not $admin) { "  not admin, run in an admin PowerShell: $cmd"; return }
  # PS 5.1 puts a native command's redirected stderr into $Error (npm warns on --force): those count by exit code.
  "+ $cmd"; $Error.Clear(); $global:LASTEXITCODE = 0; & $act *> $null
  if ($LASTEXITCODE) { "  exit $LASTEXITCODE" }
  $e = @($Error | Where-Object { $_.FullyQualifiedErrorId -notlike 'NativeCommandError*' })
  if ($e.Count) { "  $($e.Count) error(s), e.g. files in use: $($e[0])" }
}

$before = freemb
if (-not $APPLY) {
  if ($admin) { 'admin: yes, admin-only steps (choco, wudownload) run directly on --apply' }
  else { 'admin: no, admin-only steps print their command instead' }
}

sec updates
# Shortcuts on both desktops before the upgrades; afterwards only ones not in this list and created since go.
# In a service or SSH profile GetFolderPath can return '' and a desktop can be missing: skipped.
$desk = $APPLY -and (on $UPDATE desktop)
function lnks { "$env:PUBLIC\Desktop", [Environment]::GetFolderPath('Desktop') | Where-Object { $_ -and (Test-Path $_) } | ForEach-Object { Get-ChildItem $_ -Filter *.lnk -Force } }
if ($desk) { $t0 = Get-Date; $lnk0 = @(lnks | ForEach-Object { $_.FullName }) }
if ((on $UPDATE winget) -and (has winget)) {
  # Rows end in their source; the table's other text is localized, the source names aren't. Only rows after the
  # table's ----- line: an error above it can end in the source name too ("Failed when searching source: winget").
  # Over SSH that error is common: the source isn't refreshed, the table is from the cached one. A second table
  # (pinned packages, or ones that need explicit targeting) isn't upgraded here: rows after its ----- don't count.
  $t = 0; $stale = $false
  $rows = @(winget upgrade --accept-source-agreements | strip |
    Where-Object { if ($_ -match '-{10}') { $t++ } elseif ($_ -match '\s(winget|msstore)\s*$') { if ($t -eq 1) { $true } elseif (-not $t) { $stale = $true } } })
  # A narrow console cuts long ids off with an ellipsis: those can't be named, so they aren't upgraded.
  $ids = @(); if ($rows.Count) { "winget: $($rows.Count) pending" } else { 'winget: all current' }
  foreach ($r in $rows) {
    $id = wgid $r
    if ($HOLD -contains $id) { "  $r [held]" } elseif ($id -notmatch '^[\w.+-]+$') { "  $r [id cut off, upgrade by hand]" } else { "  $r"; $ids += $id }
  }
  if ($stale) { 'INFO winget could not refresh its sources in this session (common over SSH): the list is from the cached source and may be out of date; run winget upgrade in a desktop session for a fresh one' }
  # A package whose installer wants elevation fails here without a UAC prompt to answer: winget names it.
  # One id at a time, not --all: --all would take the held ones too.
  if ($APPLY) {
    foreach ($id in $ids) {
      "+ winget upgrade --id $id --exact --silent"
      winget upgrade --id $id --exact --silent --accept-package-agreements --accept-source-agreements | strip |
        Where-Object { $_ -match '\S' -and $_ -notmatch '\u2588|\u2592|^\s*[-\\|/]\s*$' }
    }
  }
}
if ((on $UPDATE scoop) -and (has scoop)) {
  scoop update *> $null
  # Older scoop prints status with Write-Host only: it then reads as all current.
  $rows = @(scoop status 6> $null | Where-Object { $_.Name })
  if ($rows.Count) { "scoop: $($rows.Count) outdated"; $rows | ForEach-Object { "  $($_.Name) $($_.'Installed Version') -> $($_.'Latest Version')" } } else { 'scoop: all current' }
  if ($APPLY -and $rows.Count) { '+ scoop update *'; scoop update * }
}
if ((on $UPDATE choco) -and (has choco)) {
  $rows = @(choco outdated -r | Where-Object { $_ -like '*|*|*' })
  if ($rows.Count) { "choco: $($rows.Count) outdated" } else { 'choco: all current' }
  $rows | ForEach-Object { $p = $_ -split '\|'; $m = ''; if (($CHOCO_HOLD -split ',') -contains $p[0]) { $m = ' [held]' }; "  $($p[0]) $($p[1]) -> $($p[2])$m" }
  if ($APPLY -and $rows.Count) {
    # choco installs machine-wide: always admin.
    $cmd = "choco upgrade all -y --except=`"$CHOCO_HOLD`""
    if ($admin) { "+ $cmd"; choco upgrade all -y "--except=$CHOCO_HOLD" | Where-Object { $_ -match 'upgraded \d+/\d+|Failures|^ - ' } }
    else { "  not admin, run in an admin PowerShell: $cmd" }
  }
}
if ($desk) {
  foreach ($f in @(lnks | Where-Object { $lnk0 -notcontains $_.FullName -and $_.CreationTime -gt $t0 } | ForEach-Object { $_.FullName })) {
    # The Public desktop is all users': admin.
    if ($f -like "$env:PUBLIC\*" -and -not $admin) { "  not admin, run in an admin PowerShell: Remove-Item -LiteralPath '$f'" }
    else { "+ Remove-Item -LiteralPath '$f'"; Remove-Item -LiteralPath $f -Force }
  }
}
# Windows Update via its COM API, offline: what Windows' own last scan found. In a job, it can hang behind a running update.
$j = Start-Job {
  # The job is a child process: the loader's $ProgressPreference doesn't reach it, and its module-loading progress
  # comes back to stderr as CLIXML.
  $ProgressPreference = 'SilentlyContinue'
  $ErrorActionPreference = 'Stop'
  $s = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher(); $s.Online = $false
  @($s.Search('IsInstalled=0 and IsHidden=0').Updates | ForEach-Object { $_.Title })
}
if (Wait-Job $j -Timeout 60) {
  $wu = @(Receive-Job $j)
  if ($j.State -ne 'Completed') { 'Windows Update: search failed' }
  elseif ($wu.Count) { 'Windows Update (list only, as of its last scan; install from Settings, it reboots):'; $wu | ForEach-Object { "  $_" } }
  else { 'Windows Update: nothing pending (as of its last scan)' }
} else { 'Windows Update: search gave no answer in 60 s' }
Remove-Job $j -Force

sec 'cleanup (size, on/off)'
item usertemp (size $env:TEMP 7) { $cut = (Get-Date).AddDays(-7); Get-ChildItem $env:TEMP -Recurse -File -Force | Where-Object { $_.LastWriteTime -lt $cut } | Remove-Item -Force }
item winget (size "$env:TEMP\WinGet") { Remove-Item "$env:TEMP\WinGet\*" -Recurse -Force }
if (has scoop) {
  $sc = $env:SCOOP; if (-not $sc) { $sc = "$env:USERPROFILE\scoop" }
  item scoop (size "$sc\cache") { scoop cache rm *; scoop cleanup * }
}
item choco (size "$env:TEMP\chocolatey") { Remove-Item "$env:TEMP\chocolatey\*" -Recurse -Force }
if (has npm) { item npm (size "$(npm config get cache)\_cacache") { npm cache clean --force } }
if (has pip) { item pip (size "$(pip cache dir)") { pip cache purge } }
item wudownload (size "$env:SystemRoot\SoftwareDistribution\Download") { Stop-Service wuauserv -Force; Remove-Item "$env:SystemRoot\SoftwareDistribution\Download\*" -Recurse -Force; Start-Service wuauserv } $true
$rb = (New-Object -ComObject Shell.Application).NameSpace(10)
if ($rb) { item recyclebin (mb (@($rb.Items()) | Measure-Object Size -Sum).Sum) { Clear-RecycleBin -Force } }

sec report
if ($APPLY) { 'mode: applied' } else { 'mode: dry run, nothing changed' }
"free on $($env:SystemDrive) $($before)M before, $(freemb)M now"
if ($APPLY) {
  $cv = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion'
  if ((Test-Path "$cv\WindowsUpdate\Auto Update\RebootRequired") -or (Test-Path "$cv\Component Based Servicing\RebootPending")) { 'reboot pending: restart to finish the updates' }
}

exit 0
