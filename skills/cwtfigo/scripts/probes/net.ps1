# Probe (Windows): addresses, listening ports and their processes, running services, containers. Read-only, no admin needed.
# Run for network or "what's running" requests. PowerShell 5.1, ASCII only.
$ErrorActionPreference = 'SilentlyContinue'

$script:open = $false
function sec($name) { if ($script:open) { '```' }; ''; "## $name"; '```'; $script:open = $true }
function has($c) { [bool](Get-Command $c) }

# Connected interfaces only: disconnected adapters and loopback are noise. A 169.254 address here means DHCP failed.
sec addresses
$up = @(Get-NetIPInterface -ConnectionState Connected | ForEach-Object { $_.InterfaceIndex })
Get-NetIPAddress | Where-Object {
  $up -contains $_.InterfaceIndex -and $_.InterfaceAlias -notlike 'Loopback*' -and $_.IPAddress -notlike 'fe80:*'
} | Sort-Object InterfaceAlias, AddressFamily | ForEach-Object { "$($_.InterfaceAlias) $($_.IPAddress)/$($_.PrefixLength) $($_.PrefixOrigin)" }

sec listening
$name = @{}
Get-Process | ForEach-Object { $name[$_.Id] = $_.ProcessName }
Get-NetTCPConnection -State Listen | ForEach-Object {
  $a = $_.LocalAddress; if ($a -like '*:*') { $a = "[$a]" }
  "${a}:$($_.LocalPort) $($name[[int]$_.OwningProcess])"
} | Sort-Object -Unique

sec services
Get-Service | Where-Object { $_.Status -eq 'Running' } | Sort-Object Name | ForEach-Object { $_.Name }
if (has docker) { docker ps -a --format '{{.Names}}\t{{.State}}' 2>$null }

'```'
exit 0
