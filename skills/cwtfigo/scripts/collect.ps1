# First-visit collector for Windows: what this machine is, nothing more. PowerShell 5.1, read-only, ASCII only.
# No logs, ports, processes or sensors: those are probes/, run only when a request needs them.
# Run by cw (stdin into powershell); same Markdown sections as collect.sh, so facts.md diffs the same way.
$ErrorActionPreference = 'SilentlyContinue'

$script:open = $false
function sec($name) { if ($script:open) { '```' }; ''; "## $name"; '```'; $script:open = $true }
function has($c) { [bool](Get-Command $c) }
function cim($class) { Get-CimInstance $class }

sec identity
"hostname: $([Net.Dns]::GetHostName())"
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
"admin: $admin"
# Only a hash is printed: enough to tell "same machine?", useless as a tracker. MachineGuid survives NIC swaps.
$guid = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Cryptography').MachineGuid
$sha = [Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes("$guid"))
"id: " + (-join ($sha | ForEach-Object { $_.ToString('x2') })).Substring(0, 16)

sec os
$os = cim Win32_OperatingSystem
"$($os.Caption) $env:PROCESSOR_ARCHITECTURE"
$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
"version: $($cv.DisplayVersion) build $($cv.CurrentBuild).$($cv.UBR)"
"powershell: $($PSVersionTable.PSVersion)"

sec hardware
$cs = cim Win32_ComputerSystem
"model: $($cs.Manufacturer) $($cs.Model)"
"cpu: $((cim Win32_Processor | Select-Object -First 1).Name)"
"memory: $([math]::Round($cs.TotalPhysicalMemory / 1GB)) GB"
cim Win32_VideoController | ForEach-Object { "gpu: $($_.Name)" }

sec packages
# winget list is slow and counts every installed program, not only winget's: presence is enough.
if (has winget) { 'winget: present' }
if (has scoop) { "scoop: $(@(scoop list).Count)" }
# choco before v2 lists the remote feed unless --local-only; v2 lists local packages only and dropped the flag.
if (has choco) { $l = if ("$(choco --version)" -match '^[01]\.') { @(choco list --local-only -r) } else { @(choco list -r) }; "choco: $($l.Count)" }

'```'
exit 0
