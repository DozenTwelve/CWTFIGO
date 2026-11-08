# Probe (Windows): this boot's errors, unexpected shutdowns, crashes, recent software changes, pending reboot. Read-only.
# Run for crashes, freezes, "it broke after an update". No admin needed: the Security log and admin-only dumps are skipped.
# Logs can hold names, paths and tokens: redact before quoting or storing. PowerShell 5.1, ASCII only.
$ErrorActionPreference = 'SilentlyContinue'

$script:open = $false
function sec($name) { if ($script:open) { '```' }; ''; "## $name"; '```'; $script:open = $true }
function has($c) { [bool](Get-Command $c) }
function when($t) { if ($t) { $t.ToString('yyyy-MM-dd HH:mm') } }
function ev($e) {
  $s = '{0} {1} {2} {3}: {4}' -f (when $e.TimeCreated), $e.LogName, $e.ProviderName, $e.Id, ($e.Message -replace '\s+', ' ')
  if ($s.Length -gt 200) { $s.Substring(0, 200) } else { $s }
}
# Every query is filtered on the server side and capped: a full scan of a busy log takes minutes.
function q($filter, $n) { Get-WinEvent -FilterHashtable $filter -MaxEvents $n }

$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime

sec "errors this boot (Critical and Error, System and Application, newest 500 each), by provider"
$err = @()
if ($boot) { foreach ($log in 'System', 'Application') { $err += @(q @{ LogName = $log; Level = 1, 2; StartTime = $boot } 500) } }
$err | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 15 | ForEach-Object { '{0,5} {1}' -f $_.Count, $_.Name }
sec "errors this boot, last 10"
$err | Sort-Object TimeCreated -Descending | Select-Object -First 10 | ForEach-Object { ev $_ }

# After a freeze or crash the user has usually rebooted already: these say whether the last shutdown was clean.
sec "boot and unexpected shutdowns"
"boot: $(when $boot)"
$bad = @(q @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41 } 3) + @(q @{ LogName = 'System'; ProviderName = 'EventLog'; Id = 6008 } 3)
$bad = @($bad | Where-Object { $_ } | Sort-Object TimeCreated -Descending)
if ($boot -and @($bad | Where-Object { $_.TimeCreated -ge $boot }).Count) { 'previous shutdown: UNEXPECTED (logged this boot)' } elseif ($boot) { 'previous shutdown: clean' }
$bad | ForEach-Object { ev $_ }

sec "app crashes (Application Error 1000, Windows Error Reporting 1001), last 5 each"
q @{ LogName = 'Application'; ProviderName = 'Application Error'; Id = 1000 } 5 | ForEach-Object { ev $_ }
q @{ LogName = 'Application'; ProviderName = 'Windows Error Reporting'; Id = 1001 } 5 | ForEach-Object { ev $_ }

# Names only, no paths: the user's profile path carries their name. Minidump is usually admin-only.
sec "crash dumps (Minidump, then user CrashDumps), newest 5"
foreach ($d in "$env:SystemRoot\Minidump", "$env:LOCALAPPDATA\CrashDumps") {
  if ($env:SystemRoot -and (Test-Path $d)) {
    Get-ChildItem $d -File | Sort-Object LastWriteTime -Descending | Select-Object -First 5 |
      ForEach-Object { '{0} {1,8} KB {2}' -f (when $_.LastWriteTime), [math]::Round($_.Length / 1KB), $_.Name }
  }
}

sec "recent software changes (MsiInstaller 11707 install / 11724 removal, WindowsUpdateClient 19)"
$msi = @(q @{ LogName = 'Application'; ProviderName = 'MsiInstaller'; Id = 11707, 11724 } 10)
# Defender's signature and platform updates (KB2267602, KB4052623) come through Windows Update several times a day
# and need no reboot: counted, they'd crowd out the rest and flag every machine as not rebooted. Matched on the KB,
# which stays in the localized title. ponytail: newest 100 then filtered, a machine with more Defender runs shows fewer.
$wu = @(q @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WindowsUpdateClient'; Id = 19 } 100 | Where-Object { $_.Message -notmatch 'KB2267602|KB4052623' } | Select-Object -First 10)
$msi + $wu | Where-Object { $_ } | Sort-Object TimeCreated -Descending | ForEach-Object { ev $_ }
sec "hotfixes, newest 5"
Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 5 | ForEach-Object { '{0:yyyy-MM-dd} {1} {2}' -f $_.InstalledOn, $_.HotFixID, $_.Description }

# An update isn't in effect until the reboot: Windows flags it in the registry, and the last KB update can be compared with
# the boot. Only KB updates: MSI installs and Store app updates (also WindowsUpdateClient 19, no KB) need no reboot.
sec "reboot pending"
$cv = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion'
if (Test-Path "$cv\WindowsUpdate\Auto Update\RebootRequired") { 'Windows Update: RebootRequired' }
if (Test-Path "$cv\Component Based Servicing\RebootPending") { 'Component Based Servicing: RebootPending' }
# Installers leave this one behind often: weak on its own.
if ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager').PendingFileRenameOperations) { 'Session Manager: PendingFileRenameOperations (weak: installers leave it often)' }
$last = $wu | Where-Object { $_.Message -match 'KB\d+' } | Select-Object -First 1
if ($last -and $boot) {
  if ($last.TimeCreated -gt $boot) { $r = 'NOT rebooted since' } else { $r = 'rebooted since' }
  "${r}: last KB update $(when $last.TimeCreated) ($([regex]::Match($last.Message, 'KB\d+').Value)), boot $(when $boot)"
}

'```'
exit 0
