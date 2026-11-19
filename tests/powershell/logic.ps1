param([string]$Script, [string]$Work)
# Extracts two pieces from setup/windows.ps1 by AST and runs them against stubs: the exact-name Scoop
# check and the graphify install/update/current/failed reporting. Needs pwsh and a POSIX sh for the uv stub.
$ErrorActionPreference = 'Stop'
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($Script, [ref]$tokens, [ref]$errors)
$fail = 0
function Check($label, $ok) { if ($ok) { "  ok    $label" } else { "  FAIL  $label"; $script:fail++ } }

# ---- 1. Test-ScoopAppInstalled
$fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-ScoopAppInstalled' }, $true)
Invoke-Expression $fn.Extent.Text
"Test-ScoopAppInstalled"
$root = Join-Path $Work 'scoop'
$sep = [System.IO.Path]::DirectorySeparatorChar
foreach ($name in 'git', 'github-cli-helper', 'goose') {
    New-Item -ItemType Directory -Force -Path (Join-Path $root "apps$sep$name$sep" "current") | Out-Null
}
"  (Join-Path gives: " + (Join-Path $root 'apps\git\current').Replace($Work, '<work>') + ")"
$env:SCOOP = $root
$env:SCOOP_GLOBAL = $null
Check "git (installed) is found"                       (Test-ScoopAppInstalled 'git')
Check "gh is NOT found although 'github-cli-helper' is installed"  (-not (Test-ScoopAppInstalled 'gh'))
Check "go is NOT found although 'goose' is installed"  (-not (Test-ScoopAppInstalled 'go'))
Check "bucket prefix extras/git is found"              (Test-ScoopAppInstalled 'extras/git')
Check "version suffix git@2.50 is found"               (Test-ScoopAppInstalled 'git@2.50')
Check "missing app is not found"                       (-not (Test-ScoopAppInstalled 'ripgrep'))
$globalRoot = Join-Path $Work 'scoop-global'
New-Item -ItemType Directory -Force -Path (Join-Path $globalRoot "apps$sep" "ripgrep$sep" "current") | Out-Null
$env:SCOOP_GLOBAL = $globalRoot
Check "an app under SCOOP_GLOBAL is found"             (Test-ScoopAppInstalled 'ripgrep')
# what the old substring match would have said, for contrast
$export = '{"buckets":[{"Name":"main","Source":"https://github.com/ScoopInstaller/Main"}],"apps":[{"Name":"7zip"}]}'
Check "old logic: 'git' matched 'github.com' in a bucket URL (the real collision)"  ($export -like '*git*')
Check "old logic: 'go' matched the installed 'goose'" ('7zip goose' -like '*go*')
Check "(gh is NOT a substring of github, so it was never at risk from URLs)" (-not ($export -like '*gh*'))

# ---- 2. Invoke-NativeWithTimeout (kills a stalled install, keeps output and exit code otherwise)
$fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-NativeWithTimeout' }, $true)
Invoke-Expression $fn.Extent.Text
"Invoke-NativeWithTimeout"
$pwshExe = (Get-Process -Id $PID).Path
function EncodedArgs($cmd) { @('-NoProfile', '-EncodedCommand', [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))) }
$sw = [Diagnostics.Stopwatch]::StartNew()
$r = Invoke-NativeWithTimeout $pwshExe (EncodedArgs 'Start-Sleep -Seconds 60') 2 | Select-Object -Last 1
Check "a stalled command is killed at the timeout" ($r.TimedOut -and $r.Code -eq -1 -and $sw.Elapsed.TotalSeconds -lt 30)
$r = Invoke-NativeWithTimeout $pwshExe (EncodedArgs 'Write-Output hello; exit 3') 30 | Select-Object -Last 1
Check "a finished command keeps its exit code and output" ((-not $r.TimedOut) -and $r.Code -eq 3 -and $r.Text -match 'hello')
$o = @(Invoke-NativeWithTimeout $pwshExe (EncodedArgs 'Write-Output keep; Write-Output "No available upgrade found."') 30 '^No available' 6>&1)
$shown = ($o | Where-Object { $_ -is [Management.Automation.InformationRecord] } | ForEach-Object { "$_" }) -join ''
$r = $o | Where-Object { $_ -isnot [Management.Automation.InformationRecord] } | Select-Object -Last 1
Check "a hidden line is not echoed but stays in the captured text" (($shown -match 'keep') -and ($shown -notmatch 'No available') -and ($r.Text -match 'No available upgrade found'))

# ---- 3. the graphify block
$if = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -match 'Get-Command uv' -and $n.Extent.Text -match 'graphifyBefore' }, $true) | Select-Object -First 1
$block = $if.Extent.Text
"graphify block"
$script:results = @()
function Add-SetupResult { param($Status, $Item) $script:results += "$Status $Item" }
$bin = Join-Path $Work 'bin'
New-Item -ItemType Directory -Force -Path $bin | Out-Null
if ([System.IO.Path]::DirectorySeparatorChar -eq '\') {
    # Windows cannot run an extensionless sh script; a .cmd stub is resolved through PATHEXT.
    @'
@echo off
set "list=%STUB_DIR%\uvlist"
if "%1 %2"=="tool list" goto list
if "%1 %2"=="tool install" goto install
exit /b 99
:list
if exist "%list%" type "%list%"
exit /b 0
:install
if defined STUB_FAIL exit /b 1
if defined STUB_UPGRADE_TO goto upgrade
if not exist "%list%" (echo graphifyy v0.9.92& echo - graphify) > "%list%"
exit /b 0
:upgrade
(echo graphifyy %STUB_UPGRADE_TO%& echo - graphify) > "%list%"
exit /b 0
'@ -replace "`r?`n", "`r`n" | Set-Content -Path (Join-Path $bin 'uv.cmd')   # cmd.exe needs CRLF
} else {
    $uv = Join-Path $bin 'uv'
    @'
#!/bin/sh
list="$STUB_DIR/uvlist"
case "$1 $2" in
  "tool list") [ -f "$list" ] && cat "$list"; exit 0 ;;
  "tool install")
    [ -z "$STUB_FAIL" ] || exit 1
    if [ -n "$STUB_UPGRADE_TO" ]; then printf 'graphifyy %s\n- graphify\n' "$STUB_UPGRADE_TO" > "$list"
    elif [ ! -f "$list" ]; then printf 'graphifyy v0.9.92\n- graphify\n' > "$list"; fi
    exit 0 ;;
esac
exit 99
'@ | Set-Content -Path $uv -NoNewline
    chmod +x $uv
}
$env:PATH = "$bin$([System.IO.Path]::PathSeparator)$env:PATH"
$env:STUB_DIR = $Work
$list = Join-Path $Work 'uvlist'
function Run-Graphify($installed, $upgradeTo, $failInstall) {
    $script:results = @()
    Remove-Item $list -ErrorAction SilentlyContinue
    if ($installed) { "graphifyy $installed`n- graphify" | Set-Content -Path $list }
    $env:STUB_UPGRADE_TO = $upgradeTo
    $env:STUB_FAIL = $failInstall
    Invoke-Expression $block | Out-Null
    return ($script:results -join ',')
}
Check "installed, same version  -> Skipped"   ((Run-Graphify 'v0.9.92' '' '') -eq 'Skipped graphifyy')
Check "installed, newer version -> Updated"   ((Run-Graphify 'v0.9.92' 'v0.9.93' '') -eq 'Updated graphifyy')
Check "not installed            -> Installed" ((Run-Graphify '' '' '') -eq 'Installed graphifyy')
Check "install fails            -> Failed"    ((Run-Graphify 'v0.9.92' '' '1') -eq 'Failed graphifyy')
# ---- Test-WingetUpgradeAvailable (stubbed winget)
$fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-WingetUpgradeAvailable' }, $true)
Invoke-Expression $fn.Extent.Text
"Test-WingetUpgradeAvailable"
function winget { if ($env:STUB_WINGET_OUTDATED -eq '1') { 'Name Id Version Available'; '---'; 'Discord Discord.Discord 1.0.9268 1.0.9269' } else { 'No installed package found matching input criteria.' } }
$env:STUB_WINGET_OUTDATED = '1'
Check "still-outdated package is reported"  (Test-WingetUpgradeAvailable 'Discord.Discord')
$env:STUB_WINGET_OUTDATED = '0'
Check "current package is not reported"     (-not (Test-WingetUpgradeAvailable 'Discord.Discord'))
# ---- Winget prefilter token sets
foreach ($name in 'ConvertTo-WingetTokenSet', 'Test-WingetTokenSetHas') {
    $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    Invoke-Expression $fn.Extent.Text
}
"Winget token sets"
$ellipsis = [string][char]0x2026
$outdated = ConvertTo-WingetTokenSet @(
    'Name Id Version Available',
    'UpNote 9.22.2 UpNote.UpNote 9.22.2 9.22.9',
    "Visual Studio Build Tools Microsoft.VisualStudio.2022.Bui$ellipsis 17.14.39 17.14.45")
Check "whole ID in the outdated listing is found"            (Test-WingetTokenSetHas $outdated 'UpNote.UpNote')
Check "ID behind a truncated token counts as possibly outdated" (Test-WingetTokenSetHas $outdated 'Microsoft.VisualStudio.2022.BuildTools')
Check "unrelated ID is not found"                            (-not (Test-WingetTokenSetHas $outdated 'Microsoft.VisualStudioCode'))
$installed = ConvertTo-WingetTokenSet @("Visual Studio Code Microsoft.VisualStudioCode 1.146.0", "Microsoft.Visual$ellipsis")
Check "installed set trusts only whole tokens"               ($installed.Whole.Contains('microsoft.visualstudiocode') -and -not $installed.Whole.Contains('Microsoft.VisualStudio.2022.BuildTools'))

# ---- npm status from the batched state
$fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-NpmPackageStatus' }, $true)
Invoke-Expression $fn.Extent.Text
"Get-NpmPackageStatus (batched state)"
$script:NpmState = @{ Installed = @('npm', 'wrangler'); Outdated = @('npm') }
Check "installed and outdated -> outdated" ((Get-NpmPackageStatus 'npm') -eq 'outdated')
Check "installed and current  -> current"  ((Get-NpmPackageStatus 'wrangler') -eq 'current')
Check "not installed          -> missing"  ((Get-NpmPackageStatus 'pnpm') -eq 'missing')
exit $fail
