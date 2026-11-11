# Probe (Windows): PATH and environment audit, Machine and User scope as new processes get them. Read-only, no admin.
# PATH in search order: scope, missing or empty folders, duplicates, %var% entries; commands found in several PATH
# folders (the first wins); non-default variables and the ones pointing at a missing path. Run for "wrong version
# runs", "command not found", "it broke after an install". Secret-looking values are never printed, only their length:
# by name (key, token, secret, pass, pwd, credential, auth, cookie, session, webhook, dsn, conn, sas, signature), by value
# (token prefixes, user:pass@ URLs, password= token= key= sig= and the like anywhere in it, Slack and Discord webhook
# URLs, long single words). PowerShell 5.1, ASCII only.
$ErrorActionPreference = 'SilentlyContinue'

$st = @{ open = $false }
function sec($name) { if ($st.open) { '```' }; ''; "## $name"; '```'; $st.open = $true }
function ex($p) { [Environment]::ExpandEnvironmentVariables($p) }
function norm($p) { (ex $p).TrimEnd('\').ToLower() }
$prog = '^\.(exe|cmd|bat|com)$'

$mach = @([Environment]::GetEnvironmentVariable('Path', 'Machine') -split ';' | Where-Object { $_ })
$user = @([Environment]::GetEnvironmentVariable('Path', 'User') -split ';' | Where-Object { $_ })
$all = @($mach | ForEach-Object { @{ s = 'M'; p = $_ } }) + @($user | ForEach-Object { @{ s = 'U'; p = $_ } })

# Machine comes before User. A program that writes its folder to the front of Machine PATH wins over the user's own.
sec "PATH in search order (M = Machine, U = User), length Machine $(($mach -join ';').Length), User $(($user -join ';').Length) chars"
$seen = @{}; $i = 0
foreach ($e in $all) {
  $i++; $n = norm $e.p; $x = ex $e.p; $flag = @()
  if (-not (Test-Path -LiteralPath $x)) { $flag += 'MISSING' }
  elseif (-not (Get-ChildItem -LiteralPath $x -File -Force | Where-Object { $_.Extension -match '^\.(exe|cmd|bat|com|ps1)$' } | Select-Object -First 1)) { $flag += 'no programs' }
  if ($seen[$n]) { $flag += "DUPLICATE of #$($seen[$n])" } else { $seen[$n] = $i }
  if ($e.p -ne $x) { $flag += 'uses %var%' }
  $tail = ''; if ($flag) { $tail = '   <- ' + ($flag -join ', ') }
  '{0,3} {1} {2}{3}' -f $i, $e.s, $e.p, $tail
}

# Within one folder PATHEXT decides (.com before .exe before .bat); across folders the first folder wins.
# WindowsApps holds the Store aliases (python, python3 that open the Store): they count too.
sec 'commands in several PATH folders (first one wins)'
$owner = @{}; $done = @{}
foreach ($e in $all) {
  $x = ex $e.p; $n = norm $e.p
  if ($done[$n] -or -not (Test-Path -LiteralPath $x)) { continue }; $done[$n] = 1
  Get-ChildItem -LiteralPath $x -File -Force | Where-Object { $_.Extension -match $prog } | ForEach-Object {
    $k = $_.BaseName.ToLower(); if (-not $owner[$k]) { $owner[$k] = New-Object System.Collections.ArrayList }
    if ($owner[$k] -notcontains $x) { [void]$owner[$k].Add($x) }
  }
}
$owner.Keys | Sort-Object | Where-Object { $owner[$_].Count -gt 1 -and $_ -notmatch '^(unins\d*|uninstall|setup|update|crashpad_handler|elevate)$' } |
  ForEach-Object { '{0,-16} {1}' -f $_, ($owner[$_] -join '  >  ') }

sec 'environment variables (non-default)'
$default = '^(Path|PATHEXT|ComSpec|OS|PROCESSOR_.*|NUMBER_OF_PROCESSORS|windir|SystemRoot|DriverData|PSModulePath|TEMP|TMP|' +
  'USERNAME|OneDrive|OneDriveConsumer|OneDriveCommercial|__PSLockdownPolicy|ZES_ENABLE_SYSMAN|CommonProgramFiles.*|ProgramFiles.*|' +
  'ProgramData|ProgramW6432|ALLUSERSPROFILE|APPDATA|LOCALAPPDATA|USERPROFILE|HOMEDRIVE|HOMEPATH|LOGONSERVER|USERDOMAIN.*|' +
  'COMPUTERNAME|PUBLIC|SystemDrive|SESSIONNAME)$'
$byname = '(?i)key|token|secret|pass|pwd|credential|auth|cookie|session|webhook|dsn|conn|sas|signature'
# Token prefixes (OpenAI/Anthropic sk-, GitHub, GitLab, Slack, AWS, JWT), credentials in a URL, or one long word
# without path or list separators. A GUID or a hash hides too: a hidden harmless value costs only a question.
$byvalue = '^(sk-|ghp_|gho_|ghs_|github_pat_|glpat-|xox[abprs]-|AKIA|ASIA|eyJ)|://[^/\s]*@|^[^\s\\/;:]{24,}$'
# Anywhere in the value: a secret after its name (connection strings and URL queries: Password=, PWD=, AccountKey=,
# ?token=, &sig=), and Slack and Discord webhook URLs, which are secrets whole.
$byvalue += '|(pass(word|wd)?|pwd|token|secret|key|sig(nature)?)=|hooks\.slack\.com|discord(app)?\.com/api/webhooks'
function secret($k, $v) { $k -match $byname -or $v -match $byvalue -or (ex $v) -match $byvalue }
foreach ($scope in 'Machine', 'User') {
  $h = [Environment]::GetEnvironmentVariables($scope)
  foreach ($k in ($h.Keys | Sort-Object)) {
    if ($k -match $default) { continue }
    $v = [string]$h[$k]; $x = ex $v
    if (secret $k $v) { $show = "<hidden, $($v.Length) chars>" } else { $show = $v }
    $flag = ''
    if ($x -match '^[A-Za-z]:\\' -and $x -notmatch ';' -and -not (Test-Path -LiteralPath $x)) { $flag = '   <- MISSING path' }
    '{0,-7} {1} = {2}{3}' -f $scope, $k, $show, $flag
  }
}

'```'
exit 0
