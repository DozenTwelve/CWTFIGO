# Probe (Windows): uptime and CPU load, memory, disks, automatic services that aren't running. Read-only, no admin needed.
# Run when a request is about slowness, space or "something's off". PowerShell 5.1, ASCII only.
$ErrorActionPreference = 'SilentlyContinue'

$script:open = $false
function sec($name) { if ($script:open) { '```' }; ''; "## $name"; '```'; $script:open = $true }
function gb($bytes) { [math]::Round($bytes / 1GB, 1) }

$os = Get-CimInstance Win32_OperatingSystem

sec uptime
if ($os.LastBootUpTime) {
  $up = (Get-Date) - $os.LastBootUpTime
  "up $($up.Days)d $($up.Hours)h $($up.Minutes)m, since $($os.LastBootUpTime.ToString('yyyy-MM-dd HH:mm'))"
}
Get-CimInstance Win32_Processor | ForEach-Object { "cpu load: $($_.LoadPercentage)%" }

sec memory
# Win32_OperatingSystem counts in KB. Commit is RAM plus page file: near its limit, programs fail to allocate.
if ($os) {
  "physical: $(gb ($os.TotalVisibleMemorySize * 1KB)) GB, available $(gb ($os.FreePhysicalMemory * 1KB)) GB"
  "commit: $(gb (($os.TotalVirtualMemorySize - $os.FreeVirtualMemory) * 1KB)) GB used of $(gb ($os.TotalVirtualMemorySize * 1KB)) GB"
}

sec disks
Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 3' | ForEach-Object {
  $pct = 0; if ($_.Size) { $pct = [math]::Round(100 * $_.FreeSpace / $_.Size) }
  "$($_.DeviceID) $(gb $_.Size) GB, $(gb $_.FreeSpace) GB free ($pct%) $($_.FileSystem)"
}

# Windows' closest thing to systemctl --failed. Delayed and trigger-start services stop or wait by design, so they're
# left out (read from the service's registry key). Ceiling: an automatic service that ran and exited on purpose still
# shows; exit 0 usually means that, 1067 or a service-specific code means it died. Netlogon is left out off a domain:
# on a workgroup machine it is Auto and stopped with exit 0 by design.
sec failed-services
$svc = 'HKLM:\SYSTEM\CurrentControlSet\Services'
$domain = (Get-CimInstance Win32_ComputerSystem).PartOfDomain
Get-CimInstance Win32_Service -Filter "StartMode = 'Auto' AND State <> 'Running'" | Where-Object {
  ($domain -or $_.Name -ne 'Netlogon') -and
  -not (Get-ItemProperty "$svc\$($_.Name)").DelayedAutostart -and -not (Test-Path "$svc\$($_.Name)\TriggerInfo")
} | Sort-Object Name | ForEach-Object { "$($_.Name) $($_.State) exit=$($_.ExitCode) ($($_.DisplayName))" }

'```'
exit 0
