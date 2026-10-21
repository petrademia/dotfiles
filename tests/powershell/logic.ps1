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

# ---- 2. the graphify block
$if = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -match 'Get-Command uv' -and $n.Extent.Text -match 'graphifyBefore' }, $true) | Select-Object -First 1
$block = $if.Extent.Text
"graphify block"
$script:results = @()
function Add-SetupResult { param($Status, $Item) $script:results += "$Status $Item" }
$bin = Join-Path $Work 'bin'
New-Item -ItemType Directory -Force -Path $bin | Out-Null
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
exit $fail
