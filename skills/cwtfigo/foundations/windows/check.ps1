# CWTFIGO-FOUNDATION: adapt to this host from its record, then delete this line. cw won't approve it before.
#
# check.ps1 (Windows): READ-ONLY health and drift check. One line per check: OK / BAD / WARN / INFO.
# Grow it per machine: every fix that could silently revert gets a line here. No admin needed: what a normal
# user can't read says so on an INFO line. Offline: nothing here asks a server. PowerShell 5.1, ASCII only.
$ErrorActionPreference = 'SilentlyContinue'

function ok($m) { "OK   $m" }
function bad($m) { "BAD  $m" }
function warn($m) { "WARN $m" }
function info($m) { "INFO $m" }
function has($c) { [bool](Get-Command $c) }

# Disk: the system drive. Feature updates want about 20 GB free.
$d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID = '$env:SystemDrive'"
if ($d.Size) {
  $gb = [math]::Round($d.FreeSpace / 1GB); $pct = [math]::Round(100 * $d.FreeSpace / $d.Size)
  if ($gb -lt 20 -or $pct -lt 10) { warn "disk $env:SystemDrive ${gb}G free ($pct%)" } else { ok "disk $env:SystemDrive ${gb}G free ($pct%)" }
}

# Pending package upgrades (winget, scoop, choco) are in maintain.ps1's dry run, not here: winget and choco refresh
# their sources over the network with no time limit, and a failed listing read as "all current".
# Windows Update via its COM API, offline: what Windows' own last scan found, no new scan. It can still hang
# behind a running update, so it runs in a job with a timeout.
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
  if ($j.State -ne 'Completed') { info 'Windows Update: search failed' }
  elseif ($wu.Count) { warn "Windows Update: $($wu.Count) pending (as of its last scan): $($wu -join '; ')" }
  else { ok 'Windows Update: nothing pending (as of its last scan)' }
} else { info 'Windows Update: search gave no answer in 60 s' }
Remove-Job $j -Force

# Defender: real-time protection and signature age. Passive mode means another antivirus is primary.
$mp = Get-MpComputerStatus
if ($mp) {
  if ($mp.RealTimeProtectionEnabled) { ok 'Defender real-time protection on' }
  elseif ("$($mp.AMRunningMode)" -like 'Passive*') { info 'Defender passive: another antivirus is primary' }
  else { bad 'Defender real-time protection off' }
  $age = ((Get-Date) - $mp.AntivirusSignatureLastUpdated).Days
  if ($age -gt 7) { warn "Defender signatures $age days old" } else { ok "Defender signatures $age day(s) old" }
} else { info 'Defender status unreadable (turned off, or another antivirus)' }
$av = @(Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct | ForEach-Object { $_.displayName })
if ($av.Count) { info "antivirus registered: $($av -join ', ')" }

# Firewall: enabled, not just present. ActiveStore is what's in force, group policy included.
$fw = @(Get-NetFirewallProfile -PolicyStore ActiveStore)
$off = @($fw | Where-Object { "$($_.Enabled)" -ne 'True' } | ForEach-Object { $_.Name })
if (-not $fw.Count) { info 'firewall state unreadable' }
elseif ($off.Count) { warn "firewall off for profile(s): $($off -join ', ')" }
else { ok 'firewall on for every profile' }

# Reboot pending: the same registry flags Windows itself sets.
$cv = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion'
$why = @()
if (Test-Path "$cv\WindowsUpdate\Auto Update\RebootRequired") { $why += 'Windows Update' }
if (Test-Path "$cv\Component Based Servicing\RebootPending") { $why += 'Component Based Servicing' }
if ($why.Count) { warn "reboot pending: $($why -join ', ')" } else { ok 'no reboot pending' }
# Installers leave this one behind often: weak on its own.
if ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager').PendingFileRenameOperations) { info 'PendingFileRenameOperations set (weak: installers leave it often)' }

$os = Get-CimInstance Win32_OperatingSystem
if ($os.LastBootUpTime) { $up = (Get-Date) - $os.LastBootUpTime; info "up $($up.Days)d $($up.Hours)h, cpu load $((Get-CimInstance Win32_Processor | Select-Object -First 1).LoadPercentage)%" }

# Host-specific checks go below this line, above exit: drift checks for this host's tweaks (a disabled service,
# a power plan, a firewall rule) and parked issues' recheck lines from notes.md.

exit 0
