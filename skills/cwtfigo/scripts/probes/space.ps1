# Probe (Windows): where the disk space went. Drives, system files, dev caches and toolchains, models, WSL and Docker
# disks, Steam games (size and last played, from their manifests), browser caches, then the biggest folders one level
# under Program Files, the profile, AppData, ProgramData and Downloads. Read-only, sizes only, no admin needed: a folder
# it can't read shows as "unreadable", one with unreadable subfolders as "partial". Seconds to a minute.
# PowerShell 5.1, ASCII only.
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

$st = @{ open = $false }
function sec($name) { if ($st.open) { '```' }; ''; "## $name"; '```'; $st.open = $true }
function gb($b) { '{0,7:N1}G' -f ($b / 1GB) }

# Its own walk, not Get-ChildItem -Recurse: that follows junctions in 5.1 (counted twice, or in a loop) and is slower.
# Reparse points are skipped, so OneDrive's and scoop's links count once, where they live. Sizes are kept by path.
$memo = @{}
function bytes($p) {
  if ($memo.ContainsKey($p)) { return $memo[$p] }
  $r = @{ b = 0.0; partial = $false }
  $todo = New-Object System.Collections.Stack
  $todo.Push((New-Object IO.DirectoryInfo $p))
  while ($todo.Count) {
    $d = $todo.Pop()
    try {
      foreach ($i in $d.EnumerateFileSystemInfos()) {
        if ($i -is [IO.FileInfo]) { $r.b += $i.Length }
        elseif (-not ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $todo.Push($i) }
      }
    } catch { $r.partial = $true }
  }
  $memo[$p] = $r; $r
}
function size($b, $partial) { if ($partial -and -not $b) { return 'unreadable' }; $s = gb $b; if ($partial) { $s += ' partial' }; $s }
function row($label, $p) {
  if (-not $p -or -not (Test-Path -LiteralPath $p)) { return }
  $r = bytes $p
  if ($r.b -lt 50MB -and -not $r.partial) { return }
  '{0,-22} {1}  {2}' -f $label, (size $r.b $r.partial), $p
}
function file($label, $p) { $i = Get-Item -LiteralPath $p -Force; if ($i) { '{0,-22} {1}  {2}' -f $label, (gb $i.Length), $i.FullName } }
# Biggest folders one level under a root, top n of those over 200M.
function top($root, $n) {
  if (-not $root -or -not (Test-Path -LiteralPath $root)) { return }
  sec "biggest under $root"
  Get-ChildItem -LiteralPath $root -Directory -Force | Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } |
    ForEach-Object { $r = bytes $_.FullName; @{ n = $_.FullName; b = $r.b; partial = $r.partial } } |
    Sort-Object { $_.b } -Descending | Select-Object -First $n | Where-Object { $_.b -ge 200MB } |
    ForEach-Object { '{0}  {1}' -f (size $_.b $_.partial), $_.n }
}

$U = $env:USERPROFILE; $L = $env:LOCALAPPDATA; $R = $env:APPDATA; $P = $env:ProgramData; $W = $env:windir; $SD = $env:SystemDrive
$PF = $env:ProgramFiles; $PF86 = ${env:ProgramFiles(x86)}
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

sec drives
"admin: $admin"
Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 3' | ForEach-Object { '{0} used {1}, free {2}' -f $_.DeviceID, (gb ($_.Size - $_.FreeSpace)), (gb $_.FreeSpace) }

sec 'system files'
file 'hiberfil.sys' "$SD\hiberfil.sys"
file 'swapfile.sys' "$SD\swapfile.sys"
Get-CimInstance Win32_PageFileUsage | ForEach-Object { '{0,-22} {1}  {2}' -f 'page file', (gb ($_.AllocatedBaseSize * 1MB)), $_.Name }
file 'MEMORY.DMP' "$W\MEMORY.DMP"
row 'Windows.old' "$SD\Windows.old"
row 'Windows Temp' "$W\Temp"
row 'WU downloads' "$W\SoftwareDistribution\Download"
row 'Delivery Optim.' "$W\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"
row 'Windows Installer' "$W\Installer"
row 'LiveKernelReports' "$W\LiveKernelReports"
row 'Minidump' "$W\Minidump"
row 'Package Cache' "$P\Package Cache"
row 'NVIDIA installers' "$SD\NVIDIA"
row 'NVIDIA downloader' "$P\NVIDIA Corporation\Downloader"
row 'WER reports' "$P\Microsoft\Windows\WER"
$rb = (New-Object -ComObject Shell.Application).NameSpace(10)
if ($rb) { '{0,-22} {1}' -f 'Recycle Bin', (gb ((@($rb.Items()) | Measure-Object Size -Sum).Sum)) }

sec 'dev caches and toolchains'
row 'npm cache' "$L\npm-cache"
row 'pip cache' "$L\pip\Cache"
row 'uv cache' "$L\uv\cache"
row 'uv pythons' "$R\uv\python"
row 'cargo registry' "$U\.cargo\registry"
row 'cargo git' "$U\.cargo\git"
row 'rustup toolchains' "$U\.rustup\toolchains"
row 'go mod cache' "$U\go\pkg\mod"
row 'go build cache' "$L\go-build"
row 'mise installs' "$L\mise"
row 'nuget packages' "$U\.nuget\packages"
row 'gradle' "$U\.gradle"
row 'maven' "$U\.m2\repository"
row 'yarn cache' "$L\Yarn\Cache"
row 'pnpm store' "$L\pnpm"
row 'conda pkgs' "$U\.conda\pkgs"
row 'scoop cache' "$U\scoop\cache"
row 'choco lib-bkp' "$P\chocolatey\lib-bkp"
row 'VS Code ext' "$U\.vscode\extensions"
row 'VS Code cache' "$R\Code\Cache"
row 'VS Code CachedData' "$R\Code\CachedData"
row 'VS installer cache' "$P\Microsoft\VisualStudio\Packages"

sec 'models, WSL, Docker'
row 'LM Studio models' "$U\.lmstudio\models"
row 'LM Studio cache' "$U\.cache\lm-studio"
$om = $env:OLLAMA_MODELS; if (-not $om) { $om = "$U\.ollama\models" }
row 'Ollama models' $om
row 'HF cache' "$U\.cache\huggingface"
row 'Docker' "$L\Docker"
# Every WSL distro's disk, wherever it was imported to, from its registry key; store installs keep it in LocalState.
Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' | ForEach-Object {
  $k = Get-ItemProperty $_.PSPath
  if ($k.BasePath) { file "WSL $($k.DistributionName)" ((($k.BasePath -replace '^\\\\\?\\', '')) + '\ext4.vhdx') }
}

# Steam games on every library: size and last played from appmanifest_*.acf, no folder walk. Manifests are UTF-8.
sec 'Steam games over 1G (size, last played)'
$sr = (Get-ItemProperty 'HKCU:\Software\Valve\Steam').SteamPath
if ($sr) { $sr = $sr -replace '/', '\' } else { $sr = "$PF86\Steam" }
$libs = @("$sr\steamapps") + @(Select-String -LiteralPath "$sr\steamapps\libraryfolders.vdf" -Pattern '"path"\s+"([^"]+)"' |
  ForEach-Object { ($_.Matches[0].Groups[1].Value -replace '\\\\', '\') + '\steamapps' })
$libs | Sort-Object -Unique | ForEach-Object { Get-ChildItem -LiteralPath $_ -Filter 'appmanifest_*.acf' } | ForEach-Object {
  $t = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
  $n = [regex]::Match($t, '"name"\s+"([^"]+)"').Groups[1].Value
  $s = [double][regex]::Match($t, '"SizeOnDisk"\s+"(\d+)"').Groups[1].Value
  $lp = [long][regex]::Match($t, '"LastPlayed"\s+"(\d+)"').Groups[1].Value
  $d = 'never     '; if ($lp) { $d = ([DateTimeOffset]::FromUnixTimeSeconds($lp)).LocalDateTime.ToString('yyyy-MM-dd') }
  @{ b = $s; line = '{0}  last played {1}  {2}  ({3})' -f (gb $s), $d, $n, $_.DirectoryName }
} | Where-Object { $_.b -ge 1GB } | Sort-Object { $_.b } -Descending | ForEach-Object { $_.line }

sec 'browser and app caches'
row 'Edge cache' "$L\Microsoft\Edge\User Data\Default\Cache"
row 'Chrome cache' "$L\Google\Chrome\User Data\Default\Cache"
row 'Brave cache' "$L\BraveSoftware\Brave-Browser\User Data\Default\Cache"
row 'Firefox cache' "$L\Mozilla\Firefox\Profiles"
row 'Discord cache' "$R\discord\Cache"
row 'Teams cache' "$L\Packages\MSTeams_8wekyb3d8bbwe\LocalCache"
row 'Spotify cache' "$L\Spotify\Data"
row 'NV DXCache' "$L\NVIDIA\DXCache"
row 'NV GLCache' "$L\NVIDIA\GLCache"
row 'D3D shader cache' "$L\D3DSCache"
row 'Steam shadercache' "$sr\steamapps\shadercache"
row 'CrashDumps' "$L\CrashDumps"
row 'User Temp' $env:TEMP

top $PF 12
top $PF86 8
top $U 15
top $L 15
top $R 10
top $P 10
top "$U\Downloads" 10

'```'
exit 0
