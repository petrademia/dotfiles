# Windows setup - mirrors the macOS/WSL tool stack via Scoop + Winget.
#
# Default (no flags): one bootstrap runs both phases (admin is required).
#   Elevated PowerShell (recommended) -> admin phase installs all Winget IDs except
#     $WingetDenylist; then opens a visible non-elevated window for user phase
#   Normal PowerShell (alternative)     -> user phase (denylist/deferred) then UAC admin phase
#
# Explicit flags:
#   -UserPhase / -AdminPhase  run one phase only
#   -SkipAutoAdmin            do not auto-elevate or chain the other phase
#   -ScheduleAdminPhase        defer admin phase to next logon (with -UserPhase)

param(
    [switch]$AdminPhase,
    [switch]$UserPhase,
    [switch]$ScheduleAdminPhase,
    [switch]$SkipAutoAdmin
)

if ($AdminPhase -and $UserPhase) {
    Write-Error "Pass -AdminPhase or -UserPhase, not both."
    exit 1
}

$script:AdminPhasePending = $false
$script:RunAdminPhase = $false
$script:RunUserPhase = $false
$script:ChainAdminPhase = $false
$script:ChainUserPhase = $false
$script:DotfilesAdminTaskName = "DotfilesSetupAdminPhase"
$script:DotfilesUserTaskName = "DotfilesSetupUserPhase"
$script:WslBroken = $false
$wslDistro = "Ubuntu-24.04"
$wslPackageId = "Canonical.Ubuntu.2404"
$script:WingetDenylist = @(
    # Known Winget IDs that fail with "cannot be run from an administrator context".
    # Runtime refusals are appended to $env:TEMP\dotfiles-winget-user-phase.txt for the chained user phase.
)
$script:WingetDeferFile = Join-Path $env:TEMP "dotfiles-winget-user-phase.txt"
$script:UserPhaseLogFile = Join-Path $env:TEMP "dotfiles-windows-user-phase.log"
$script:UserPhaseTranscriptStarted = $false
$script:WingetApps = @(
    "DisplayLink.GraphicsDriver",
    "Microsoft.VCRedist.2015+.x64",
    "Microsoft.DotNet.DesktopRuntime.10",
    "PatchMyPC.PatchMyPC",
    "CodecGuide.K-LiteCodecPack.Full",
    "TheDocumentFoundation.LibreOffice",
    "ONLYOFFICE.DesktopEditors",
    "Valve.Steam",
    "ElectronicArts.EADesktop",
    "RiotGames.Valorant.AP",
    "SoftDeluxe.FreeDownloadManager",
    "seerge.g-helper",
    "AgileBits.1Password", "Surfshark.Surfshark", "OpenVPNTechnologies.OpenVPNConnect",
    "Anysphere.Cursor", "Anthropic.Claude", "MoonshotAI.Kimi", "GitHub.Copilot",
    "Microsoft.PowerToys",
    "Devolutions.UniGetUI",
    "voidtools.Everything",
    "Ollama.Ollama", "ElementLabs.LMStudio", "ggml.llamacpp", "SST.OpenCodeDesktop",
    "Google.Chrome", "Google.Chrome.Beta", "Google.Chrome.Canary",
    "Google.GoogleDrive", "Microsoft.OneDrive",
    "Google.Antigravity", "Google.AntigravityCLI",
    "Microsoft.VisualStudioCode", "Notepad++.Notepad++", "Microsoft.WindowsTerminal", "Postman.Postman",
    "Alacritty.Alacritty", "wez.wezterm", "Eugeny.Tabby", "Vercel.Hyper",
    "Zen-Team.Zen-Browser", "Mozilla.Firefox.DeveloperEdition", "Mozilla.Firefox.ESR",
    "Vivaldi.Vivaldi", "Brave.Brave", "Opera.Opera", "Opera.OperaGX", "Opera.OperaAir", "Ablaze.Floorp",
    "LibreWolf.LibreWolf", "Waterfox.Waterfox", "MullvadVPN.MullvadBrowser",
    "eloston.ungoogled-chromium",
    "Deskflow.Deskflow", "SlackTechnologies.Slack", "Discord.Discord",
    "UpNote.UpNote",
    "Streetwriters.Notesnook",
    "StandardNotes.StandardNotes", "Automattic.Simplenote",
    "Joplin.Joplin", "Obsidian.Obsidian",
    "FilesCommunity.Files",
    "VideoLAN.VLC", "Stremio.Stremio",
    "qBittorrent.qBittorrent", "Transmission.Transmission",
    "erez-c137.NetSpeedTray", "zhongyang219.TrafficMonitor.Lite"
)

$script:SetupResults = [ordered]@{
    Installed = 0
    Updated = 0
    Skipped = 0
    Failed = 0
}
$script:SetupFailures = [System.Collections.Generic.List[string]]::new()

function Set-DotfilesBootstrapExecutionPolicy {
    # Process scope only: enough for this bootstrap. Child phases pass -ExecutionPolicy Bypass.
    # Do not set CurrentUser here; when Process is already Bypass, that emits ExecutionPolicyOverride noise.
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
}

function Ensure-DotfilesCurrentUserExecutionPolicy {
    # New PowerShell sessions need RemoteSigned (or better) so $PROFILE scripts load.
    # Set CurrentUser from a child process without Process=Bypass to avoid override warnings.
    $list = Get-ExecutionPolicy -List
    foreach ($scope in @("MachinePolicy", "UserPolicy")) {
        $policy = $list[$scope]
        if ($policy -ne "Undefined" -and $policy -in @("Restricted", "AllSigned")) {
            Write-Host "[!] $scope is '$policy'; the PowerShell profile may not run until policy is relaxed." -ForegroundColor Yellow
            return
        }
    }

    $currentUser = $list["CurrentUser"]
    if ($currentUser -in @("RemoteSigned", "Unrestricted", "Bypass", "AllSigned")) { return }

    try {
        & powershell.exe -NoProfile -Command @'
$ErrorActionPreference = 'Stop'
if ((Get-ExecutionPolicy -Scope CurrentUser) -in 'Restricted','Undefined') {
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
}
'@
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[!] Could not set CurrentUser execution policy to RemoteSigned (exit $LASTEXITCODE)." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[!] Could not set CurrentUser execution policy to RemoteSigned: $_" -ForegroundColor Yellow
    }
}

# --- 0. Pre-Flight ---
Set-DotfilesBootstrapExecutionPolicy
# irm | iex often starts in System32; keep installers from writing into that tree.
Set-Location $HOME

function Add-SetupResult {
    param(
        [ValidateSet("Installed", "Updated", "Skipped", "Failed")]
        [string]$Status,
        [string]$Item
    )
    $script:SetupResults[$Status] = [int]$script:SetupResults[$Status] + 1
    if ($Status -eq "Failed" -and $Item) { $script:SetupFailures.Add($Item) }
}

function Write-SetupSummary {
    Write-Host ""
    Write-Host "Setup summary" -ForegroundColor Green
    foreach ($status in @("Installed", "Updated", "Skipped", "Failed")) {
        Write-Host ("  {0}: {1}" -f $status, $script:SetupResults[$status])
    }
    if ($script:SetupFailures.Count -gt 0) {
        Write-Host ("  Failed items: {0}" -f ($script:SetupFailures -join ", ")) -ForegroundColor Yellow
    }
}

function Update-SessionPath {
    $machine = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:PATH = "$user;$machine"
}

# Scoop clones GitHub over HTTPS. git/gitconfig rewrites that to SSH, which
# fails on a fresh machine before the 1Password agent is available.
function Protect-ScoopGit {
    param([scriptblock]$Block, $Arg)
    $empty = Join-Path $env:TEMP "dotfiles-empty.gitconfig"
    if (!(Test-Path $empty)) { New-Item -ItemType File -Path $empty -Force | Out-Null }
    $prev = $env:GIT_CONFIG_GLOBAL
    $env:GIT_CONFIG_GLOBAL = $empty
    try {
        if ($PSBoundParameters.ContainsKey("Arg")) { & $Block $Arg }
        else { & $Block }
    } finally {
        if ([string]::IsNullOrEmpty($prev)) { Remove-Item Env:GIT_CONFIG_GLOBAL -ErrorAction SilentlyContinue }
        else { $env:GIT_CONFIG_GLOBAL = $prev }
    }
}

function Add-UserPath {
    param([string]$Dir)
    if ([string]::IsNullOrWhiteSpace($Dir)) { return }
    if (!(Test-Path $Dir)) { New-Item -ItemType Directory -Path $Dir -Force | Out-Null }
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($user -notlike "*$Dir*") {
        [Environment]::SetEnvironmentVariable("Path", "$Dir;$user", "User")
    }
    if ($env:PATH -notlike "*$Dir*") { $env:PATH = "$Dir;$env:PATH" }
}

function Save-RemoteFile {
    param([string]$Uri, [string]$OutFile, [int]$Tries = 3)
    for ($i = 1; $i -le $Tries; $i++) {
        try {
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
            if ((Test-Path $OutFile) -and ((Get-Item $OutFile).Length -gt 0)) { return $true }
        } catch {}
        & curl.exe -fsSL $Uri -o $OutFile
        if (($LASTEXITCODE -eq 0) -and (Test-Path $OutFile) -and ((Get-Item $OutFile).Length -gt 0)) { return $true }
        Start-Sleep -Seconds ($i * 2)
    }
    return $false
}

function Sync-DotfilesClone {
    $dest = Join-Path $HOME "dotfiles"
    Protect-ScoopGit {
        if (!(Test-Path (Join-Path $dest ".git"))) {
            Write-Host "Cloning dotfiles..." -ForegroundColor Cyan
            git clone https://github.com/petrademia/dotfiles.git $dest
        } else {
            git -C $dest pull --ff-only --quiet 2>$null | Out-Null
        }
    }
    return $dest
}

function Get-DotfilesRoot {
    # Prefer the script being run so local unpushed fixes apply before git push.
    if ($PSScriptRoot) {
        $root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
        if (Test-Path (Join-Path $root "setup\windows.ps1")) { return $root }
    }
    return Sync-DotfilesClone
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = [Security.Principal.WindowsPrincipal]::new($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WindowsSetupScriptPath {
    if ($PSScriptRoot) {
        $local = Join-Path $PSScriptRoot "windows.ps1"
        if (Test-Path $local) { return (Resolve-Path $local).Path }
    }
    $cloned = Join-Path (Get-DotfilesRoot) "setup\windows.ps1"
    if (Test-Path $cloned) { return (Resolve-Path $cloned).Path }
    return $null
}

function Get-DotfilesAdminPhaseCommand {
    $path = Get-WindowsSetupScriptPath
    if ($path) {
        return "& `"$path`" -AdminPhase"
    }
    return "irm https://raw.githubusercontent.com/petrademia/dotfiles/main/setup/windows.ps1 | iex; .\setup\windows.ps1 -AdminPhase"
}

function Start-DotfilesAdminPhaseElevated {
    $path = Get-WindowsSetupScriptPath
    if (-not $path) {
        $path = Join-Path (Get-DotfilesRoot) "setup\windows.ps1"
        if (-not (Test-Path $path)) {
            Write-Host "[!] Could not resolve setup\windows.ps1 for elevation." -ForegroundColor Red
            return 1
        }
        $path = (Resolve-Path $path).Path
    }
    Write-Host "[+] Starting elevated admin phase (one UAC prompt)..." -ForegroundColor Yellow
    Write-Host "    The elevated window stays open when finished." -ForegroundColor Gray
    try {
        # No -Wait: -NoExit keeps that host open, so waiting would freeze this prompt
        # until the elevated window is closed. Do not exit this session afterward.
        $null = Start-Process -FilePath powershell.exe -Verb RunAs -ArgumentList @(
            "-NoProfile", "-NoExit", "-ExecutionPolicy", "Bypass",
            "-File", $path, "-AdminPhase", "-SkipAutoAdmin"
        ) -PassThru
    } catch {
        Write-Host "[!] Admin phase elevation was cancelled." -ForegroundColor Yellow
        return 1
    }
    return 0
}

function New-DotfilesPowerShellTaskAction {
    param(
        [string]$Path,
        [string[]]$ExtraArguments
    )

    $argumentString = @(
        "-NoProfile"
        "-ExecutionPolicy Bypass"
        "-File `"$Path`""
        $ExtraArguments
    ) -join " "

    return New-ScheduledTaskAction -Execute "powershell.exe" -Argument $argumentString
}

function Register-DotfilesAdminPhaseTask {
    $path = Get-WindowsSetupScriptPath
    if (-not $path) {
        Write-Host "[!] Cannot schedule admin phase; setup\windows.ps1 not found." -ForegroundColor Yellow
        return $false
    }
    try {
        $action = New-DotfilesPowerShellTaskAction -Path $path -ExtraArguments @("-AdminPhase")
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName $script:DotfilesAdminTaskName -Action $action -Trigger $trigger `
            -Settings $settings -Principal $principal -Force | Out-Null
        Write-Host "[+] Scheduled one-shot admin phase at next logon: $script:DotfilesAdminTaskName" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[!] Could not register admin phase task: $_" -ForegroundColor Yellow
        return $false
    }
}

function Unregister-DotfilesAdminPhaseTask {
    Unregister-ScheduledTask -TaskName $script:DotfilesAdminTaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
}

function Get-DotfilesUserPhaseProcesses {
    param([string]$Path)
    @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            ($_.CommandLine -like "*$Path*") -and
            ($_.CommandLine -like "*UserPhase*")
        })
}

function Start-DotfilesUserPhaseNonElevated {
    param([switch]$Wait)
    $path = Get-WindowsSetupScriptPath
    if (-not $path) {
        Write-Host "[!] Cannot chain user phase; setup\windows.ps1 not found." -ForegroundColor Yellow
        Write-Host "    Normal PS: irm https://raw.githubusercontent.com/petrademia/dotfiles/main/setup/windows.ps1 | iex" -ForegroundColor Cyan
        return 1
    }
    Unregister-ScheduledTask -TaskName $script:DotfilesUserTaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

    $wd = Split-Path $path
    $windowArgs = @(
        "-NoProfile", "-NoExit", "-ExecutionPolicy", "Bypass",
        "-File", $path, "-UserPhase", "-SkipAutoAdmin"
    )
    $manual = "& `"$path`" -UserPhase -SkipAutoAdmin"

    Write-Host "[+] Starting user phase (non-elevated)..." -ForegroundColor Cyan
    Write-Host "    Log: $script:UserPhaseLogFile" -ForegroundColor Gray

    if (Test-IsAdmin) {
        # ShellExecute from an elevated host drops to the normal user token and shows a window.
        $argString = ($windowArgs | ForEach-Object {
            if ($_ -match '\s') { "`"$_`"" } else { $_ }
        }) -join " "
        try {
            $shell = New-Object -ComObject Shell.Application
            $rc = $shell.ShellExecute("powershell.exe", $argString, $wd, "open", 1)
            if ($rc -is [int] -and $rc -le 32) {
                throw "ShellExecute returned $rc"
            }
        } catch {
            Write-Host "[!] Could not open user phase window: $_" -ForegroundColor Yellow
            Write-Host "    Normal PS: $manual" -ForegroundColor Cyan
            return 1
        }
        if ($Wait) {
            Write-Host "[+] Waiting for user phase window (close it when done)..." -ForegroundColor Gray
            $started = $false
            for ($i = 0; $i -lt 20; $i++) {
                Start-Sleep -Seconds 1
                if ((Get-DotfilesUserPhaseProcesses $path).Count -gt 0) { $started = $true; break }
            }
            if (-not $started) {
                Write-Host "[!] User phase window did not start." -ForegroundColor Yellow
                Write-Host "    Normal PS: $manual" -ForegroundColor Cyan
                return 1
            }
            do {
                Start-Sleep -Seconds 2
            } while ((Get-DotfilesUserPhaseProcesses $path).Count -gt 0)
            if (Test-Path $script:UserPhaseLogFile) {
                Write-Host "[+] User phase log: $script:UserPhaseLogFile" -ForegroundColor Green
            }
        } else {
            Write-Host "[+] User phase is running in a separate window." -ForegroundColor Green
        }
        return 0
    }

    if ($Wait) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $path -UserPhase -SkipAutoAdmin
        return $LASTEXITCODE
    }
    Start-Process -FilePath "powershell.exe" -ArgumentList $windowArgs -WorkingDirectory $wd -WindowStyle Normal
    return 0
}

function Initialize-DotfilesSetupPhase {
    if ($AdminPhase) { $script:RunAdminPhase = $true; return }
    if ($UserPhase) { $script:RunUserPhase = $true; return }
    if (Test-IsAdmin) {
        $script:RunAdminPhase = $true
        if (-not $SkipAutoAdmin) { $script:ChainUserPhase = $true }
    } else {
        $script:RunUserPhase = $true
        if (-not $SkipAutoAdmin) { $script:ChainAdminPhase = $true }
    }
}

function Test-DotfilesRunAdminPhase {
    return $AdminPhase -or $script:RunAdminPhase
}

function Test-DotfilesRunUserPhase {
    return $UserPhase -or $script:RunUserPhase
}

function Start-DotfilesUserPhaseLogging {
    if (-not (Test-DotfilesRunUserPhase)) { return }
    if ($script:UserPhaseTranscriptStarted) { return }
    try {
        Start-Transcript -Path $script:UserPhaseLogFile -Append -Force | Out-Null
        $script:UserPhaseTranscriptStarted = $true
        Write-Host "[+] User phase log: $script:UserPhaseLogFile" -ForegroundColor Gray
    } catch {
        Write-Host "[!] Could not start user phase log: $_" -ForegroundColor Yellow
    }
}

function Stop-DotfilesUserPhaseLogging {
    if (-not $script:UserPhaseTranscriptStarted) { return }
    try { Stop-Transcript | Out-Null } catch {}
    $script:UserPhaseTranscriptStarted = $false
}

function Write-DotfilesAdminPhaseNextSteps {
    if (-not $script:AdminPhasePending) { return }
    $path = Get-WindowsSetupScriptPath
    Write-Host ""
    Write-Host "Admin phase still needed (WSL host, HKLM defaults, DisplayLink, firewall):" -ForegroundColor Yellow
    Write-Host "  $(Get-DotfilesAdminPhaseCommand)" -ForegroundColor Cyan
    if ($path) {
        Write-Host "Or one UAC prompt now:" -ForegroundColor Yellow
        Write-Host "  Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File `"$path`" -AdminPhase'" -ForegroundColor Cyan
    }
    Write-Host "Or schedule at next logon (one UAC at logon):" -ForegroundColor Yellow
    Write-Host "  .\setup\windows.ps1 -UserPhase -ScheduleAdminPhase" -ForegroundColor Cyan
}

function Test-WingetExit1603 {
    param([string]$Text, [int]$Code)
    return ($Code -eq 1603) -or ($Text -match "exit code:\s*1603")
}

function Test-WingetAdminContext {
    param([string]$Text)
    return $Text -match "cannot be run from an administrator context"
}

function Test-WingetHashMismatch {
    param([string]$Text)
    return $Text -match "Installer hash does not match"
}

function Test-WingetNoChange {
    param([string]$Text)
    return $Text -match "No available upgrade found|No newer package versions are available|No applicable upgrade|No installed package found|No package found matching|version number cannot be determined"
}

# Winget's Warp.Warp installer URL is an HTML landing page, so `winget install`
# sits on "Downloading https://app.warp.dev/download/windows?..." forever.
function Install-Warp {
    $existing = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Warp\Warp.exe"),
        (Join-Path $env:LOCALAPPDATA "Warp\Warp.exe")
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    $show = winget show -e --id Warp.Warp --source winget 2>$null | Out-String
    if ($show -notmatch '(?m)^\s*Version:\s+(\S+)') {
        Write-Host "[!] Could not read Warp version from Winget. Skipping." -ForegroundColor Yellow
        Add-SetupResult Skipped "Warp.Warp"
        return
    }
    $ver = $Matches[1]
    if ($existing) {
        $current = (Get-Item $existing).VersionInfo.ProductVersion
        if ($current -and $current -eq $ver) {
            Write-Host "[-] Warp $current is current." -ForegroundColor Gray
            Add-SetupResult Skipped "Warp.Warp"
            return
        }
        Write-Host "[*] Updating Warp $current -> $ver..." -ForegroundColor Cyan
    } else {
        Write-Host "[+] Installing Warp $ver..." -ForegroundColor Cyan
    }
    $setup = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "WarpSetup-arm64.exe" } else { "WarpSetup.exe" }
    $url = "https://releases.warp.dev/stable/$ver/$setup"
    $out = Join-Path $env:TEMP $setup
    Write-Host "    $url"
    & curl.exe -fL --retry 3 $url -o $out
    if (($LASTEXITCODE -ne 0) -or !(Test-Path $out) -or ((Get-Item $out).Length -lt 1MB)) {
        Write-Host "[!] Warp download failed. Skipping." -ForegroundColor Yellow
        Add-SetupResult Failed "Warp.Warp"
        return
    }
    $proc = Start-Process -FilePath $out -ArgumentList "/VERYSILENT", "/NORESTART", "/SUPPRESSMSGBOXES" -Wait -PassThru
    Remove-Item $out -ErrorAction SilentlyContinue
    if ($proc.ExitCode -ne 0) {
        Write-Host "[!] Warp installer exit $($proc.ExitCode)." -ForegroundColor Yellow
        Add-SetupResult Failed "Warp.Warp"
    } else {
        if ($existing) { Add-SetupResult Updated "Warp.Warp" }
        else { Add-SetupResult Installed "Warp.Warp" }
        Write-Host "[+] Warp installed or updated." -ForegroundColor Green
    }
}

function Install-EjectLens {
    $root = Join-Path $env:LOCALAPPDATA "Programs\EjectLens"
    $exe = Join-Path $root "EjectLens.exe"
    $versionFile = Join-Path $root ".version"
    $api = "https://api.github.com/repos/weinianxue/EjectLens/releases/latest"

    try {
        $release = Invoke-RestMethod -Uri $api -UseBasicParsing -ErrorAction Stop
        $asset = $release.assets | Where-Object { $_.name -like "EjectLens-*-win-x64-portable.zip" } | Select-Object -First 1
        if (!$asset -or $asset.name -notmatch "EjectLens-v(?<version>[^-]+)-win-x64-portable\.zip") {
            throw "No Windows portable release asset found"
        }
        $version = $Matches.version
    } catch {
        Write-Host "[!] Could not resolve EjectLens release: $_" -ForegroundColor Yellow
        Add-SetupResult Failed "EjectLens"
        return
    }

    $current = if (Test-Path $versionFile) { (Get-Content $versionFile -Raw).Trim() } else { $null }
    if ((Test-Path $exe) -and $current -eq $version) {
        Write-Host "[-] EjectLens $version is current." -ForegroundColor Gray
        New-StartMenuShortcut -Name "EjectLens" -Target $exe
        Add-SetupResult Skipped "EjectLens"
        return
    }

    $zip = Join-Path $env:TEMP "EjectLens-$version.zip"
    $extract = Join-Path $env:TEMP "EjectLens-$version"
    try {
        Write-Host "[*] Installing or updating EjectLens $version..." -ForegroundColor Cyan
        if (!(Save-RemoteFile $asset.browser_download_url $zip)) { throw "Download failed" }
        if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
        Expand-Archive -Path $zip -DestinationPath $extract -Force
        $payload = Get-ChildItem -Path $extract -Filter "EjectLens.exe" -File -Recurse | Select-Object -First 1
        if (!$payload) { throw "EjectLens.exe was not found in the release archive" }
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        Copy-Item -Path (Join-Path $payload.DirectoryName "*") -Destination $root -Recurse -Force
        Set-Content -Path $versionFile -Value $version -Encoding ASCII
        New-StartMenuShortcut -Name "EjectLens" -Target $exe
        if ($current) { Add-SetupResult Updated "EjectLens" }
        else { Add-SetupResult Installed "EjectLens" }
        Write-Host "[+] EjectLens $version installed at $root" -ForegroundColor Green
    } catch {
        Write-Host "[!] EjectLens install/update failed: $_" -ForegroundColor Yellow
        Add-SetupResult Failed "EjectLens"
    } finally {
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# rustup-msvc / UniGetUI cargo managers need link.exe + a Windows SDK.
# Plain winget without --override only drops the VS installer, not the C++ workload.
function Test-VsCToolsInstalled {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (!(Test-Path $vswhere)) { return $false }
    $p = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    return -not [string]::IsNullOrWhiteSpace("$p")
}

function Install-VsBuildTools {
    if (Test-VsCToolsInstalled) {
        Write-Host "[-] Visual Studio C++ Build Tools already installed." -ForegroundColor Gray
        return
    }
    Write-Host "[+] Installing Visual Studio 2022 Build Tools (MSVC + Windows SDK)..." -ForegroundColor Cyan
    $override = "--wait --quiet --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
    winget install -e --id Microsoft.VisualStudio.2022.BuildTools --accept-package-agreements --accept-source-agreements --disable-interactivity --override $override --source winget
    if (($LASTEXITCODE -ne 0) -or -not (Test-VsCToolsInstalled)) {
        Write-Host "[!] VS Build Tools missing or failed. Elevated:" -ForegroundColor Yellow
        Write-Host "    winget install -e --id Microsoft.VisualStudio.2022.BuildTools --override `"$override`"" -ForegroundColor Cyan
    }
}

function Test-GeForceExperiencePresent {
    $arp = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "*GeForce Experience*" }
    return [bool]$arp
}

function Uninstall-GeForceExperience {
    if (-not (Test-GeForceExperiencePresent)) {
        Write-Host "[-] NVIDIA GeForce Experience not installed. Skipping..." -ForegroundColor Gray
        Add-SetupResult Skipped "GeForce Experience"
        return
    }
    if (-not (Test-IsAdmin)) {
        Write-Host "[-] GeForce Experience uninstall needs -AdminPhase (NVIDIA NVI2)." -ForegroundColor Gray
        $script:AdminPhasePending = $true
        Add-SetupResult Skipped "GeForce Experience"
        return
    }
    Write-Host "[+] Uninstalling NVIDIA GeForce Experience (replaced by NVIDIA App)..." -ForegroundColor Cyan
    $nvi2 = Join-Path $env:ProgramFiles "NVIDIA Corporation\Installer2\InstallerCore\NVI2.DLL"
    $rundll = Join-Path $env:SystemRoot "SysWOW64\rundll32.exe"
    if (!(Test-Path $rundll)) { $rundll = Join-Path $env:SystemRoot "System32\rundll32.exe" }
    if (Test-Path $nvi2) {
        # -silent = no wizard; -n = no reboot prompt (NVIDIA NVI2).
        $p = Start-Process -FilePath $rundll -ArgumentList @(
            "`"$nvi2`",UninstallPackage Display.GFExperience",
            "-silent",
            "-n"
        ) -Wait -PassThru
        if ($p -and $p.ExitCode -ne 0 -and (Test-GeForceExperiencePresent)) {
            Write-Host "[!] NVI2 uninstall exited $($p.ExitCode). Trying winget..." -ForegroundColor Yellow
            winget uninstall --name "NVIDIA GeForce Experience" --accept-source-agreements --silent --disable-interactivity
        }
    } else {
        winget uninstall --name "NVIDIA GeForce Experience" --accept-source-agreements --silent --disable-interactivity
    }
    Start-Sleep -Seconds 2
    if (Test-GeForceExperiencePresent) {
        Write-Host "[!] GeForce Experience is still installed." -ForegroundColor Yellow
        Add-SetupResult Failed "GeForce Experience"
    } else {
        Write-Host "[+] GeForce Experience removed." -ForegroundColor Green
        Add-SetupResult Updated "GeForce Experience"
    }
}

# GitHub releases ship macOS/Linux only. Compile with MSVC if link.exe exists,
# otherwise Scoop gcc + the gnu rustc triple.
function Install-AtlassianCli {
    $existing = @(
        (Join-Path $HOME ".cargo\bin\atlassian-cli.exe"),
        (Join-Path $HOME ".local\bin\atlassian-cli.exe")
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($existing -or (Get-Command atlassian-cli -ErrorAction SilentlyContinue)) {
        Write-Host "[-] atlassian-cli is already installed." -ForegroundColor Gray
        return
    }
    if (!(Get-Command cargo -ErrorAction SilentlyContinue)) {
        Write-Host "[!] cargo not found. Skipping atlassian-cli." -ForegroundColor Yellow
        return
    }

    if (Get-Command link.exe -ErrorAction SilentlyContinue) {
        Write-Host "[+] Installing atlassian-cli (cargo)..." -ForegroundColor Cyan
        cargo install atlassian-cli
        return
    }
    if (!(Get-Command gcc -ErrorAction SilentlyContinue)) {
        Write-Host "[!] gcc not found. Skipping atlassian-cli." -ForegroundColor Yellow
        return
    }
    $triple = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "aarch64-pc-windows-gnu" } else { "x86_64-pc-windows-gnu" }
    Write-Host "[+] Installing atlassian-cli (cargo + $triple; no Windows GitHub binary)..." -ForegroundColor Cyan
    rustup toolchain install "stable-$triple"
    & cargo "+stable-$triple" install atlassian-cli
}

function Install-UniGetUiCargoDeps {
    if (!(Get-Command cargo -ErrorAction SilentlyContinue)) {
        Write-Host "[!] cargo not found. Skipping UniGetUI cargo deps." -ForegroundColor Yellow
        return
    }
    foreach ($pair in @(
        @{ Crate = "cargo-update"; Command = "cargo-install-update" },
        @{ Crate = "cargo-binstall"; Command = "cargo-binstall" }
    )) {
        $bin = Join-Path $HOME ".cargo\bin\$($pair.Command).exe"
        if ((Test-Path $bin) -or (Get-Command $pair.Command -ErrorAction SilentlyContinue)) {
            Write-Host "[-] $($pair.Crate) already present. Skipping..." -ForegroundColor Gray
            Add-SetupResult Skipped $pair.Crate
            continue
        }
        Write-Host "[+] Installing $($pair.Crate) (UniGetUI cargo manager)..." -ForegroundColor Cyan
        cargo install $pair.Crate
        if ($LASTEXITCODE -eq 0) { Add-SetupResult Installed $pair.Crate }
        else { Add-SetupResult Failed $pair.Crate }
    }
}

# Same as right-click Unpin from taskbar. File Explorer has no shell verb; this COM
# API unpins the pin shortcut without deleting explorer.exe or restarting Explorer.
function Invoke-TaskbarUnpin {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not ("DotfilesTaskbarUnpin" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

[ComImport]
[Guid("4CD19ADA-25A5-4A32-B3B7-347BEE5BE36B")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IStartMenuPinnedList {
    [PreserveSig] int RemoveFromList(IntPtr pitem);
}

[ComImport]
[Guid("a2a9545d-a0c2-42b4-9708-a0b2badd77c8")]
class StartMenuPin {}

public static class DotfilesTaskbarUnpin {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
    static extern int SHCreateItemFromParsingName(string pszPath, IntPtr pbc, ref Guid riid, out IntPtr ppv);

    static readonly Guid IID_IShellItem = new Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE");

    public static int UnpinPath(string path) {
        IntPtr item;
        Guid iid = IID_IShellItem;
        int hr = SHCreateItemFromParsingName(path, IntPtr.Zero, ref iid, out item);
        if (hr != 0) return hr;
        try {
            var pin = (IStartMenuPinnedList)new StartMenuPin();
            return pin.RemoveFromList(item);
        } finally {
            Marshal.Release(item);
        }
    }
}
"@
    }
    [void][DotfilesTaskbarUnpin]::UnpinPath($Path)
}

function New-StartMenuShortcut {
    param([string]$Name, [string]$Target)
    if (!(Test-Path $Target)) { return }
    $dir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut((Join-Path $dir "$Name.lnk"))
    $lnk.TargetPath = $Target
    $lnk.WorkingDirectory = Split-Path $Target
    $lnk.Save()
}

function Set-UserRun {
    param([string]$Name, [string]$Target)
    if (!(Test-Path $Target)) { return }
    $reg = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    if (!(Test-Path $reg)) { New-Item -Path $reg -Force | Out-Null }
    Set-ItemProperty -Path $reg -Name $Name -Value "`"$Target`""
}

function Set-IniKeyPreserveEncoding {
    param([string]$Path, [string]$Key, [string]$Value)
    if (!(Test-Path $Path)) { return }
    $bytes = [IO.File]::ReadAllBytes($Path)
    $enc = New-Object System.Text.UTF8Encoding $false
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        $enc = [Text.Encoding]::Unicode
    } elseif ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $enc = New-Object System.Text.UTF8Encoding $true
    }
    $text = $enc.GetString($bytes)
    $pattern = "(?m)^" + [regex]::Escape($Key) + "\s*=.*$"
    $line = "$Key = $Value"
    if ($text -match $pattern) {
        $next = [regex]::Replace($text, $pattern, $line)
    } else {
        $next = [regex]::Replace($text, "(?m)^(\[config\])", "`$1`r`n$line")
    }
    if ($next -ne $text) { [IO.File]::WriteAllText($Path, $next, $enc) }
}

function Initialize-TrafficMonitor {
    $exe = $null
    $pkgRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    if (Test-Path $pkgRoot) {
        $pkg = Get-ChildItem -LiteralPath $pkgRoot -Directory -Filter "zhongyang219.TrafficMonitor.Lite*" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($pkg) {
            $candidate = Join-Path $pkg.FullName "TrafficMonitor\TrafficMonitor.exe"
            if (Test-Path $candidate) { $exe = $candidate }
        }
    }
    if (-not $exe) {
        $exe = Get-ChildItem -Path @($env:ProgramFiles, ${env:ProgramFiles(x86)}) -Filter "TrafficMonitor.exe" -Recurse -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName -First 1
    }
    if (-not $exe) {
        Write-Host "[!] TrafficMonitor.exe not found (WinGet package missing or install failed)." -ForegroundColor Yellow
        return
    }

    $ini = Join-Path (Split-Path $exe) "config.ini"
    $running = Get-Process TrafficMonitor -ErrorAction SilentlyContinue
    if (-not $running) { Set-IniKeyPreserveEncoding $ini "show_task_bar_wnd" "true" }

    New-StartMenuShortcut -Name "TrafficMonitor" -Target $exe
    Set-UserRun -Name "TrafficMonitor" -Target $exe
    if (-not $running) {
        Start-Process $exe -WorkingDirectory (Split-Path $exe)
        Write-Host "[+] TrafficMonitor started (Start Menu + autostart)." -ForegroundColor Green
    } else {
        Write-Host "[-] TrafficMonitor already running (Start Menu + autostart set)." -ForegroundColor Gray
    }
}

function Set-WindowsHostUserDefaults {
    Write-Host "Applying Windows user defaults..." -ForegroundColor Cyan

    $adv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    Set-ItemProperty -Path $adv -Name HideFileExt -Type DWord -Value 0 -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $adv -Name Hidden -Type DWord -Value 1 -ErrorAction SilentlyContinue
    # Folder Options > Open File Explorer to: This PC (1), not Home (2).
    Set-ItemProperty -Path $adv -Name LaunchTo -Type DWord -Value 1 -ErrorAction SilentlyContinue
    # Settings > System > For developers > End Task on the taskbar.
    $endTask = Join-Path $adv "TaskbarDeveloperSettings"
    if (!(Test-Path $endTask)) { New-Item -Path $endTask -Force | Out-Null }
    Set-ItemProperty -Path $endTask -Name TaskbarEndTask -Type DWord -Value 1 -ErrorAction SilentlyContinue
    # Settings > Personalization > Taskbar > Taskbar items: hide Search, Task view,
    # Widgets, Chat, Copilot, Resume. TaskbarDa is ACL-locked on some builds.
    Set-ItemProperty -Path $adv -Name MultiTaskingAltTabFilter -Type DWord -Value 3 -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $adv -Name ShowTaskViewButton -Type DWord -Value 0 -ErrorAction SilentlyContinue
    foreach ($name in @("TaskbarDa", "TaskbarMn", "ShowCopilotButton", "IsEnabled")) {
        & reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v $name /t REG_DWORD /d 0 /f 2>$null | Out-Null
    }
    # Win11: 0=small, 1=medium, 2=large. Unset defaults to medium.
    & reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v TaskbarSi /t REG_DWORD /d 0 /f 2>$null | Out-Null
    # ROG Flow X13 is a 2-in-1; the tablet-optimized bar is taller even in laptop posture.
    & reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ExpandableTaskbar /t REG_DWORD /d 0 /f 2>$null | Out-Null
    $search = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
    if (!(Test-Path $search)) { New-Item -Path $search -Force | Out-Null }
    Set-ItemProperty -Path $search -Name SearchboxTaskbarMode -Type DWord -Value 0
    Set-ItemProperty -Path $search -Name SearchboxTaskbarModeCache -Type DWord -Value 0
    Set-ItemProperty -Path $search -Name BingSearchEnabled -Type DWord -Value 0
    # Personalization > Start: more pins, no account nags or Store tips.
    Set-ItemProperty -Path $adv -Name Start_Layout -Type DWord -Value 1 -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $adv -Name Start_AccountNotifications -Type DWord -Value 0
    Set-ItemProperty -Path $adv -Name Start_IrisRecommendations -Type DWord -Value 0
    # Taskbar battery glyph shows a percent. Sticky Keys Flags is REG_SZ; 506
    # clears SKF_STICKYKEYSON and SKF_HOTKEYACTIVE (Shift five times).
    Set-ItemProperty -Path $adv -Name IsBatteryPercentageEnabled -Type DWord -Value 1
    Set-ItemProperty -Path "HKCU:\Control Panel\Accessibility\StickyKeys" -Name Flags -Value "506"
    if (-not (Set-HkcuRegValue "Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" 1)) {
        Write-Host "[!] DisableSearchBoxSuggestions policy failed." -ForegroundColor DarkYellow
    }
    if (-not (Set-HkcuRegValue "Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" "SettingsPageVisibility" "hide:home" -Type String)) {
        Write-Host "[!] SettingsPageVisibility policy failed." -ForegroundColor DarkYellow
    }
    $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    if (!(Test-Path $cdm)) { New-Item -Path $cdm -Force | Out-Null }
    foreach ($name in @("SubscribedContent-338393Enabled", "SubscribedContent-353694Enabled", "SubscribedContent-353696Enabled")) {
        Set-ItemProperty -Path $cdm -Name $name -Type DWord -Value 0
    }
    $settingsNags = "HKCU:\Software\Microsoft\Windows\CurrentVersion\SystemSettings\AccountNotifications"
    if (!(Test-Path $settingsNags)) { New-Item -Path $settingsNags -Force | Out-Null }
    Set-ItemProperty -Path $settingsNags -Name EnableAccountNotifications -Type DWord -Value 0
    $feeds = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds"
    if (!(Test-Path $feeds)) { New-Item -Path $feeds -Force | Out-Null }
    try { Set-ItemProperty -Path $feeds -Name ShellFeedsTaskbarViewMode -Type DWord -Value 2 -ErrorAction Stop } catch {}
    $resume = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration"
    if (!(Test-Path $resume)) { New-Item -Path $resume -Force | Out-Null }
    Set-ItemProperty -Path $resume -Name IsResumeAllowed -Type DWord -Value 0
    Set-ItemProperty -Path $resume -Name IsOneDriveResumeAllowed -Type DWord -Value 0

    # Windows Security > App & browser control: SmartScreen on, Smart App Control off.
    # SAC is currently Evaluation (2) on this SKU and can promote itself to On.
    $appHost = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AppHost"
    if (!(Test-Path $appHost)) { New-Item -Path $appHost -Force | Out-Null }
    Set-ItemProperty -Path $appHost -Name EnableWebContentEvaluation -Type DWord -Value 1

    $shots = Join-Path $HOME "Screenshots"
    New-Item -ItemType Directory -Path $shots -Force | Out-Null
    $shellFolders = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
    Set-ItemProperty -Path $shellFolders -Name "{B7BEDE81-DF25-465F-82AD-D4F0086DC39B}" -Value $shots

    Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name KeyboardDelay -Value "0"
    Set-ItemProperty -Path "HKCU:\Control Panel\Keyboard" -Name KeyboardSpeed -Value "31"

    $ptp = "HKCU:\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad"
    if (Test-Path $ptp) {
        Set-ItemProperty -Path $ptp -Name TapsEnabled -Type DWord -Value 1 -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $ptp -Name TapAndDrag -Type DWord -Value 0 -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $ptp -Name ThreeFingerSlideEnabled -Type DWord -Value 0
        Set-ItemProperty -Path $ptp -Name ThreeFingerTapEnabled -Type DWord -Value 0
    }

    try {
        $unpinNames = @(
            "Microsoft Edge",
            "Microsoft Store",
            "Store",
            "Copilot",
            "Microsoft Copilot",
            "Microsoft 365 Copilot",
            "Windows Copilot",
            "File Explorer",
            "Explorer",
            "Mail",
            "Outlook",
            "Microsoft Teams",
            "Teams",
            "Chat",
            "Xbox"
        )
        $unpinFromTaskbar = {
            param($item)
            if (-not $item) { return }
            $item.Verbs() | Where-Object { ($_.Name -replace "&", "") -match "Unpin from taskbar" } | ForEach-Object { $_.DoIt() }
        }
        $shell = New-Object -ComObject Shell.Application
        $appsFolder = $shell.NameSpace("shell:::{4234d49b-0245-4df3-b780-3893943456e1}")
        if ($appsFolder) {
            # Several apps share a display name (e.g. classic Outlook vs new Outlook).
            # Unpin every match; -First 1 hits Office Outlook which has no taskbar verb.
            foreach ($name in $unpinNames) {
                $appsFolder.Items() | Where-Object { $_.Name -eq $name } | ForEach-Object {
                    & $unpinFromTaskbar $_
                }
            }
        }
        # Same Unpin verb on the pin shortcut. File Explorer has none in AppsFolder;
        # IStartMenuPinnedList is the documented unpin (not deleting the .lnk by hand).
        $pinDir = Join-Path $env:APPDATA "Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
        if (Test-Path $pinDir) {
            $pinNs = $shell.NameSpace($pinDir)
            Get-ChildItem -LiteralPath $pinDir -Filter "*.lnk" -ErrorAction SilentlyContinue | Where-Object {
                $unpinNames -contains $_.BaseName
            } | ForEach-Object {
                if ($pinNs) { & $unpinFromTaskbar ($pinNs.ParseName($_.Name)) }
                Invoke-TaskbarUnpin $_.FullName
            }
        }
        Invoke-TaskbarUnpin (Join-Path $env:WINDIR "explorer.exe")
        Invoke-TaskbarUnpin "shell:AppsFolder\Microsoft.Windows.Explorer"
        Invoke-TaskbarUnpin "shell:AppsFolder\Microsoft.OutlookForWindows_8wekyb3d8bbwe!Microsoft.OutlookforWindows"
        Invoke-TaskbarUnpin "shell:AppsFolder\Microsoft.Office.OUTLOOK.EXE.15"
    } catch {}

    Set-WindowsStartupApps
}

function Test-RegValueEquals {
    param(
        [string]$PsPath,
        [string]$Name,
        [object]$Value,
        [string]$Type
    )
    if (!(Test-Path $PsPath)) { return $false }
    $current = (Get-ItemProperty -Path $PsPath -Name $Name -ErrorAction SilentlyContinue).$Name
    if ($null -eq $current) { return $false }
    if ($Type -eq "String") { return ([string]$current -eq [string]$Value) }
    return ([int]$current -eq [int]$Value)
}

function Set-HkcuRegValue {
    param(
        [Parameter(Mandatory)][string]$SubKey,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][object]$Value,
        [ValidateSet("DWord", "String")][string]$Type = "DWord"
    )
    $psPath = "HKCU:\$SubKey"
    $regType = if ($Type -eq "String") { "REG_SZ" } else { "REG_DWORD" }
    if (Test-RegValueEquals $psPath $Name $Value $Type) { return $true }
    try {
        if (!(Test-Path $psPath)) { New-Item -Path $psPath -Force -ErrorAction Stop | Out-Null }
        if ($Type -eq "String") {
            Set-ItemProperty -Path $psPath -Name $Name -Type String -Value [string]$Value -ErrorAction Stop
        } else {
            Set-ItemProperty -Path $psPath -Name $Name -Type DWord -Value ([int]$Value) -ErrorAction Stop
        }
        return $true
    } catch {
        & reg.exe add "HKCU\$SubKey" /v $Name /t $regType /d $Value /f 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { return $true }
        return (Test-RegValueEquals $psPath $Name $Value $Type)
    }
}

function Set-HklmRegValue {
    param(
        [Parameter(Mandatory)][string]$SubKey,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][object]$Value,
        [ValidateSet("DWord", "String")][string]$Type = "DWord"
    )
    $psPath = "HKLM:\$SubKey"
    $regType = if ($Type -eq "String") { "REG_SZ" } else { "REG_DWORD" }
    if (Test-RegValueEquals $psPath $Name $Value $Type) { return $true }
    try {
        if (!(Test-Path $psPath)) { New-Item -Path $psPath -Force | Out-Null }
        if ($Type -eq "String") {
            Set-ItemProperty -Path $psPath -Name $Name -Type String -Value [string]$Value -ErrorAction Stop
        } else {
            Set-ItemProperty -Path $psPath -Name $Name -Type DWord -Value ([int]$Value) -ErrorAction Stop
        }
        return $true
    } catch {
        & reg.exe add "HKLM\$SubKey" /v $Name /t $regType /d $Value /f 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { return $true }
        return (Test-RegValueEquals $psPath $Name $Value $Type)
    }
}

function Set-WindowsHostAdminDefaults {
    if (-not (Test-IsAdmin)) {
        Write-Host "[!] HKLM defaults skipped (run -AdminPhase elevated)." -ForegroundColor Yellow
        $script:AdminPhasePending = $true
        return
    }
    Write-Host "Applying Windows admin defaults..." -ForegroundColor Cyan

    if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy") {
        if (-not (Set-HklmRegValue "SYSTEM\CurrentControlSet\Control\CI\Policy" "VerifiedAndReputablePolicyState" 0)) {
            Write-Host "[!] Smart App Control policy failed." -ForegroundColor DarkYellow
        }
    }
    if (-not (Set-HklmRegValue "SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" "SmartScreenEnabled" "Warn" -Type String)) {
        Write-Host "[!] SmartScreen HKLM failed." -ForegroundColor DarkYellow
    }
    if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
        try { Set-MpPreference -PUAProtection 1 -ErrorAction Stop }
        catch { Write-Host "[!] PUA protection failed: $_" -ForegroundColor DarkYellow }
    }

    powercfg /hibernate on 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[!] Hibernate enable failed." -ForegroundColor DarkYellow
    }

    foreach ($pair in @(
        @{ SubKey = "SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings"; Name = "ShowHibernateOption"; Value = 1 },
        @{ SubKey = "SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings"; Name = "ShowSleepOption"; Value = 1 },
        @{ SubKey = "SYSTEM\CurrentControlSet\Control\FileSystem"; Name = "LongPathsEnabled"; Value = 1 },
        @{ SubKey = "SOFTWARE\Policies\Microsoft\Dsh"; Name = "AllowNewsAndInterests"; Value = 0 },
        @{ SubKey = "SOFTWARE\Policies\Microsoft\Windows\Windows Feeds"; Name = "EnableFeeds"; Value = 0 },
        @{ SubKey = "SOFTWARE\Policies\Microsoft\Windows\CloudContent"; Name = "DisableWindowsConsumerFeatures"; Value = 1 },
        @{ SubKey = "SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name = "HideRecommendedSection"; Value = 1 }
    )) {
        if (-not (Set-HklmRegValue $pair.SubKey $pair.Name $pair.Value)) {
            Write-Host ("[!] HKLM\{0}\{1} failed." -f $pair.SubKey, $pair.Name) -ForegroundColor DarkYellow
        }
    }
    Set-WindowsStartupAppsMachine
}

function Add-DotfilesWingetDefer {
    param([string]$App)
    if ([string]::IsNullOrWhiteSpace($App)) { return }
    $existing = @()
    if (Test-Path $script:WingetDeferFile) {
        $existing = Get-Content -LiteralPath $script:WingetDeferFile -ErrorAction SilentlyContinue
    }
    if ($existing -contains $App) { return }
    Add-Content -LiteralPath $script:WingetDeferFile -Value $App
}

function Get-DotfilesWingetAdminApps {
    $script:WingetApps | Where-Object { $_ -notin $script:WingetDenylist }
}

function Get-DotfilesWingetUserApps {
    $deferred = @()
    if (Test-Path $script:WingetDeferFile) {
        $deferred = Get-Content -LiteralPath $script:WingetDeferFile -ErrorAction SilentlyContinue |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }
    @($script:WingetDenylist + $deferred) | Select-Object -Unique
}

function Install-DeskflowFirewallRule {
    Write-Host "Opening Port 24800 for Deskflow..." -ForegroundColor Cyan
    $dfRule = "Deskflow Inbound (TCP 24800)"
    try {
        if (!(Get-NetFirewallRule -DisplayName $dfRule -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName $dfRule -Direction Inbound -LocalPort 24800 -Protocol TCP -Action Allow -Description "Deskflow KVM" -ErrorAction Stop | Out-Null
        }
    } catch {
        if (-not (Test-IsAdmin)) {
            Write-Host "[!] Deskflow firewall rule skipped (run -AdminPhase elevated)." -ForegroundColor Yellow
            $script:AdminPhasePending = $true
        } else {
            Write-Host "[!] Deskflow firewall rule failed: $_" -ForegroundColor Yellow
        }
    }
}

function Install-WingetApps {
    param(
        [string[]]$Apps,
        [switch]$AdminOnly,
        [switch]$UserOnly
    )
    foreach ($app in $Apps) {
        if ($UserOnly -and (Test-IsAdmin)) {
            Write-Host "[-] $app deferred (installer refuses elevated session)." -ForegroundColor Gray
            Add-SetupResult Skipped $app
            continue
        }
        if ($AdminOnly -and -not (Test-IsAdmin)) {
            Write-Host "[-] $app skipped (needs -AdminPhase)." -ForegroundColor Gray
            $script:AdminPhasePending = $true
            continue
        }
        $check = winget list --id $app --source winget 2>$null
        $checkText = @($check | ForEach-Object { "$_" }) -join "`n"
        if ([string]::IsNullOrWhiteSpace($checkText) -or (Test-WingetNoChange $checkText)) {
            Write-Host "[+] Installing $app..." -ForegroundColor Cyan
            $wingetLines = @()
            winget install -e --id $app --accept-package-agreements --accept-source-agreements --silent --source winget 2>&1 | Tee-Object -Variable wingetLines
            $wingetText = @($wingetLines | ForEach-Object { "$_" }) -join "`n"
            $wingetCode = $LASTEXITCODE
            $installSucceeded = $wingetCode -eq 0
            if (Test-WingetExit1603 $wingetText $wingetCode) {
                if ($app -eq "Deskflow.Deskflow") {
                    Write-Host "[!] Deskflow needs VC++ 14.50+ (Winget may still have 14.30). Upgrade Microsoft.VCRedist.2015+.x64, then re-run." -ForegroundColor Yellow
                } elseif ($AdminOnly) {
                    Write-Host "[!] $app installer failed (exit 1603). Reboot, then re-run -AdminPhase." -ForegroundColor Yellow
                } else {
                    Write-Host "[!] $app installer needs elevation or a reboot (exit 1603). Run -AdminPhase." -ForegroundColor Yellow
                    $script:AdminPhasePending = $true
                }
            } elseif (Test-WingetAdminContext $wingetText) {
                if ($AdminOnly) {
                    Write-Host "[-] $app deferred to user phase (installer refuses elevated session)." -ForegroundColor Gray
                    Add-DotfilesWingetDefer $app
                    Add-SetupResult Skipped $app
                } else {
                    Write-Host "[!] $app refuses an elevated session. Re-run -UserPhase." -ForegroundColor Yellow
                    Add-SetupResult Skipped $app
                }
                continue
            } elseif (Test-WingetHashMismatch $wingetText) {
                Write-Host "[!] $app Winget manifest/installer hash mismatch. Skipping; retry later." -ForegroundColor Yellow
            } elseif ($wingetCode -ne 0) {
                Write-Host "[!] Exact Winget install failed for $app. Skipping." -ForegroundColor Yellow
            }
            if ($installSucceeded) { Add-SetupResult Installed $app }
            else { Add-SetupResult Failed $app }
        } else {
            Write-Host "[-] $app already present. Skipping..." -ForegroundColor Gray
            Add-SetupResult Skipped $app
        }
    }
}

function Set-StartupApproved {
    param([string]$Key, [string]$Name, [bool]$Enabled)
    try {
        if (!(Test-Path $Key)) { New-Item -Path $Key -Force -ErrorAction Stop | Out-Null }
        # 12 bytes: status DWORD (02=on, 03=off) + FILETIME. A zero timestamp
        # makes Windows 11 Settings/Task Manager treat a disable as still On.
        $flag = if ($Enabled) { [byte]2 } else { [byte]3 }
        $bytes = [byte[]](@($flag, 0, 0, 0) + [BitConverter]::GetBytes([DateTime]::Now.ToFileTime()))
        New-ItemProperty -Path $Key -Name $Name -PropertyType Binary -Value $bytes -Force -ErrorAction Stop | Out-Null
    } catch {}
}

function Set-AppXStartupState {
    param([string]$FamilyPrefix, [string]$TaskName, [int]$State)
    $root = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData"
    if (!(Test-Path $root)) { return }
    Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | Where-Object {
        $_.PSIsContainer -and ($_.PSChildName -like "$FamilyPrefix*")
    } | ForEach-Object {
        $task = Join-Path $_.PSPath $TaskName
        if (Test-Path $task) {
            Set-ItemProperty -LiteralPath $task -Name State -Type DWord -Value $State
        }
    }
}

function Set-WindowsStartupAppsMachine {
    if (-not (Test-IsAdmin)) { return }
    $runLm = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
    $runLmWow = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32"
    foreach ($pair in @(
        @{ Key = $runLm; Name = "Virtual Pet"; On = $false },
        @{ Key = $runLm; Name = "Riot Vanguard"; On = $false },
        @{ Key = $runLm; Name = "Riot Client"; On = $false },
        @{ Key = $runLm; Name = "EADesktop"; On = $false },
        @{ Key = $runLm; Name = "SecurityHealth"; On = $true },
        @{ Key = $runLm; Name = "DisplayLinkTrayApp"; On = $false },
        @{ Key = $runLmWow; Name = "ASUS Smart Display Control"; On = $false }
    )) {
        Set-StartupApproved $pair.Key $pair.Name $pair.On
    }
    $everything = Get-Service -Name "Everything" -ErrorAction SilentlyContinue
    if ($everything -and $everything.StartType -eq "Automatic") {
        try { Set-Service -Name "Everything" -StartupType Manual -ErrorAction Stop }
        catch { Write-Host "[!] Everything service startup type failed: $_" -ForegroundColor DarkYellow }
    }
}

function Set-WindowsStartupApps {
    Write-Host "Applying startup app allow/deny list..." -ForegroundColor Cyan
    $run = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
    $folder = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder"

    # Default deny: optional tools, sync clients, launchers, and helpers start on demand.
    # TrafficMonitor and WindowSwitcher stay on; they are added to Run earlier.
    foreach ($name in @(
        "Surfshark",
        "GoogleDriveFS",
        "OneDrive",
        "Everything",
        "BraveSoftware Update",
        "Opera GX Browser Assistant",
        "Opera GX Stable",
        "Opera Air Browser Assistant",
        "Opera Air Stable",
        "Opera Browser Assistant",
        "Opera Stable",
        "Discord",
        "com.squirrel.slack.slack",
        "Warp",
        "org.openvpn.client",
        "Steam",
        "WingetUI",
        "Riot Vanguard",
        "Riot Client",
        "RiotClient",
        "EADM",
        "EADesktop",
        "EALauncher",
        "EA app",
        "EA Desktop",
        "Free Download Manager"
    )) { Set-StartupApproved $run $name $false }

    foreach ($name in @("TrafficMonitor", "WindowSwitcher")) {
        Set-StartupApproved $run $name $true
    }

    Set-StartupApproved $folder "Ollama.lnk" $false

    Set-AppXStartupState "Agilebits.1Password_" "1PasswordStartup" 2
    Set-AppXStartupState "*ThreeFinger*" "ThreeFingerDragOnWindows" 2
    Set-AppXStartupState "MicrosoftWindows.CrossDevice_" "CrossDevice.Start" 0
    Set-AppXStartupState "Microsoft.MicrosoftOfficeHub_" "WebViewHostStartupId" 0
    Set-AppXStartupState "MicrosoftTeams_" "TeamsStartupTask" 0
    Set-AppXStartupState "MSTeams_" "TeamsTfwStartupTask" 0
    Set-AppXStartupState "OpenAI.ChatGPT-Desktop_" "ChatGPT" 0
    Set-AppXStartupState "SpotifyAB.SpotifyMusic_" "Spotify" 0
    Set-AppXStartupState "AdvancedMicroDevicesInc-2.AMDRadeonSoftware_" "launcherrsxruntimeTask" 0
    Set-AppXStartupState "Microsoft.CommandPalette_" "CmdPalStartup" 0
    Set-AppXStartupState "Microsoft.YourPhone_" "YourPhone.Start" 0
    Set-AppXStartupState "Microsoft.Todos_" "ToDoStartupId" 0
    Set-AppXStartupState "Microsoft.GamingApp_" "Xbox.App.Tasks.FullTrustComponent" 0
    Set-AppXStartupState "Microsoft.PowerAutomateDesktop_" "AutoStartTask" 0
    Set-AppXStartupState "Microsoft.WindowsTerminal_" "StartTerminalOnLoginTask" 0
    Set-AppXStartupState "LGElectronics.LGMonitorApp_" "LGMonitorAutoStart" 0

    # WhatsApp's AppX startup task is a GUID that can change; disable every task in the family.
    $root = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData"
    if (Test-Path $root) {
        Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | Where-Object {
            $_.PSIsContainer -and ($_.PSChildName -like "5319275A.WhatsAppDesktop_*")
        } | ForEach-Object {
            Get-ChildItem $_.PSPath -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer } | ForEach-Object {
                if ($null -ne (Get-ItemProperty $_.PSPath -Name State -ErrorAction SilentlyContinue).State) {
                    Set-ItemProperty -LiteralPath $_.PSPath -Name State -Type DWord -Value 0
                }
            }
        }
    }
}

function Add-ScoopBucket {
    param([string]$Name)
    $listed = (scoop bucket list | Out-String)
    if ($listed -like "*$Name*") { return }
    Protect-ScoopGit { param($n) scoop bucket add $n | Out-Host } -Arg $Name
}

function Install-GitHubKnownHosts {
    $sshDir = Join-Path $HOME ".ssh"
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    $knownHosts = Join-Path $sshDir "known_hosts"
    $scan = Join-Path $HOME "scoop\apps\git\current\usr\bin\ssh-keyscan.exe"
    if (!(Test-Path $scan)) { return }
    $keys = & $scan -t ed25519,ecdsa,rsa github.com 2>$null
    if (-not $keys) { return }
    $existing = @()
    if (Test-Path $knownHosts) { $existing = Get-Content $knownHosts }
    foreach ($line in $keys) {
        if ($line -match '^\s*#' -or [string]::IsNullOrWhiteSpace($line)) { continue }
        if ($existing -notcontains $line) {
            Add-Content -Path $knownHosts -Value $line
            $existing += $line
        }
    }
}

Initialize-DotfilesSetupPhase
Start-DotfilesUserPhaseLogging

if ((Test-DotfilesRunAdminPhase) -and -not (Test-IsAdmin)) {
    [void](Start-DotfilesAdminPhaseElevated)
    return
}

if (Test-DotfilesRunUserPhase) {

if (!(Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Scoop..." -ForegroundColor Yellow
    irm get.scoop.sh | iex
    Update-SessionPath
}

# Git is required before scoop update / bucket add.
if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Installing git (required for Scoop buckets)..." -ForegroundColor Cyan
    scoop install git
    Update-SessionPath
}
Install-GitHubKnownHosts

Write-Host "Updating Scoop Manifests..." -ForegroundColor Cyan
Protect-ScoopGit { scoop update | Out-Host }
scoop config aria2-warning-enabled false 6>$null | Out-Null

# Repo-managed Scoop apps: install when missing; skip when already present.
# Upgrades are left to `scoop update *` / UniGetUI so re-runs stay mostly Skipped.
function Smart-Scoop {
    param([string]$app)
    $installedList = scoop export
    if ($installedList -like "*$app*") {
        Write-Host "[-] $app already present. Skipping..." -ForegroundColor Gray
        Add-SetupResult Skipped $app
    } else {
        Write-Host "[+] $app not found. Installing now..." -ForegroundColor Cyan
        scoop install $app
        if ($LASTEXITCODE -eq 0) { Add-SetupResult Installed $app }
        else { Add-SetupResult Failed $app }
    }
}

# --- 2. Core Dependencies & Buckets ---
foreach ($b in @("extras", "versions", "nerd-fonts", "java")) { Add-ScoopBucket $b }

$core = @("git", "7zip", "gh", "go", "rustup-msvc", "fastfetch", "aria2", "scoop-search")
foreach ($app in $core) { Smart-Scoop $app }

# --- 3. Main App Block (CLI & Portable) ---
$apps = @(
    "1password-cli", "localsend", "wiztree", "dust", "fzf", "jq",
    "fnm", "gcc", "jetbrains-toolbox", "JetBrainsMono-NF", "llvm",
    "ninja", "podman", "podman-desktop", "sudo", "uv", "gdb", "cheat-engine",
    "syncthing",
    "xmake", "cmake", "ripgrep", "neovim", "zellij", "helix", "zed", "lapce", "neovide", "trae", "graphviz", "zstd", "ngrok",
    "gradle", "maven", "plantuml", "z3", "sqlite",
    "kubectl", "kind", "k3d",
    "potplayer", "firefox-nightly", "thorium", "min", "chromium"
)
foreach ($app in $apps) { Smart-Scoop $app }

if (Get-Command rustup -ErrorAction SilentlyContinue) {
    rustup default stable 2>&1 | Out-Null
    $env:PATH = "$HOME\.cargo\bin;$env:PATH"
    Install-AtlassianCli
    Install-UniGetUiCargoDeps
}

if (Get-Command uv -ErrorAction SilentlyContinue) {
    uv python install 3 --default
}

# --- 4. Java matrix (same packages as bootstrap/java-windows.ps1) ---
# irm | iex uses ~/dotfiles; pull first so this is not a stale first-run clone.
$dotfiles = Sync-DotfilesClone
Write-Host "Installing Java matrix..." -ForegroundColor Cyan
$javaLocal = @(
    $(if ($PSScriptRoot) { Join-Path $PSScriptRoot "..\bootstrap\java-windows.ps1" }),
    (Join-Path $dotfiles "bootstrap\java-windows.ps1")
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if ($javaLocal) {
    Protect-ScoopGit { param($p) & $p } -Arg $javaLocal
} else {
    Protect-ScoopGit { irm "https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/java-windows.ps1" | iex }
}

# --- 5. Winget Apps (2026 Verified IDs) ---
# Admin phase installs all Winget IDs except $WingetDenylist; refusals defer to user phase via temp file.
Write-Host "Checking user-phase Winget apps..." -ForegroundColor Cyan
$userWinget = Get-DotfilesWingetUserApps
if ($userWinget.Count -gt 0) {
    Install-WingetApps -Apps $userWinget -UserOnly
} else {
    Write-Host "[-] No user-phase Winget apps (denylist empty, none deferred)." -ForegroundColor Gray
}

$uniGetUiExe = Join-Path $env:LOCALAPPDATA "Programs\UniGetUI\UniGetUI.exe"
New-StartMenuShortcut -Name "UniGetUI" -Target $uniGetUiExe

Install-Warp
Install-EjectLens

Initialize-TrafficMonitor

Uninstall-GeForceExperience

# --- 5b. Microsoft Store apps ---
# 9PLM9XGG6VKS = unified ChatGPT/Codex; 9NT1R1C2HH7J = ChatGPT Classic
# Spotify's Winget NSIS installer refuses an elevated / UAC-elevated session.
Write-Host "Checking Microsoft Store apps..." -ForegroundColor Cyan
$msStoreApps = @(
    @{ Id = "9PLM9XGG6VKS"; Label = "ChatGPT (unified Codex app)"; Appx = "OpenAI.Codex" }
    @{ Id = "9NT1R1C2HH7J"; Label = "ChatGPT Classic"; Appx = "OpenAI.ChatGPT-Desktop" }
    @{ Id = "9MSX91WQCM2V"; Label = "ThreeFingerDrag"; Appx = "50931ClmentGrennerat.ThreeFingersDragOnWindows" }
    @{ Id = "9NKSQGP7F2NH"; Label = "WhatsApp"; Appx = "*WhatsApp*" }
    @{ Id = "9NCBCSZSJRSB"; Label = "Spotify"; Appx = "SpotifyAB.SpotifyMusic" }
    @{ Id = "9P2B8MCSVPLN"; Label = "Realtek Audio Control"; Appx = "RealtekSemiconductorCorp.RealtekAudioControl" }
    @{ Id = "XP8CLZL93F5Z4P"; Label = "NVIDIA App"; Appx = "*NVIDIAApp*" }
)
foreach ($app in $msStoreApps) {
    if (Get-AppxPackage -Name $app.Appx -ErrorAction SilentlyContinue) {
        Write-Host "[-] $($app.Label) already present. Skipping..." -ForegroundColor Gray
        Add-SetupResult Skipped $app.Label
        continue
    }
    if ((Test-IsAdmin) -and $app.Label -eq "Spotify") {
        Write-Host "[-] $($app.Label) deferred (installer refuses elevated session). Re-run -UserPhase." -ForegroundColor Gray
        Add-SetupResult Skipped $app.Label
        continue
    }
    Write-Host "[+] Installing $($app.Label)..." -ForegroundColor Cyan
    winget install --id $app.Id --source msstore --accept-package-agreements --accept-source-agreements --silent
    if ($LASTEXITCODE -eq 0) { Add-SetupResult Installed $app.Label }
    else { Add-SetupResult Failed $app.Label }
}

# --- 6. Go Environment (GoLand GOROOT Fix) ---
Write-Host "Configuring Go Paths..." -ForegroundColor Cyan
$goRootPath = "$env:USERPROFILE\scoop\apps\go\current"
[System.Environment]::SetEnvironmentVariable("GOROOT", $goRootPath, "User")
[System.Environment]::SetEnvironmentVariable("GOPATH", "$env:USERPROFILE\go", "User")
$env:GOROOT = $goRootPath
$env:GOPATH = "$env:USERPROFILE\go"
$env:PATH = "$goRootPath\bin;$env:GOPATH\bin;$env:PATH"

# --- 6b. Shared Dotfiles ---
$dotfiles = Sync-DotfilesClone

function Sync-Dotfile {
    param([string]$Source, [string]$Destination)

    $parent = Split-Path $Destination -Parent
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

    if (Test-Path $Source -PathType Container) {
        if (Test-Path $Destination -PathType Leaf) {
            Write-Host "[!] Cannot sync directory over file: $Destination" -ForegroundColor Yellow
            Add-SetupResult Failed $Destination
            return
        }
        $destinationExisted = Test-Path $Destination
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        & robocopy.exe $Source $Destination /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
        $code = $LASTEXITCODE
        if ($code -le 7) {
            if ($code -eq 0) {
                Add-SetupResult Skipped $Destination
            } elseif ($destinationExisted) {
                Add-SetupResult Updated $Destination
            } else {
                Add-SetupResult Installed $Destination
            }
        } else {
            Write-Host "[!] Directory sync failed: $Destination (robocopy $code)" -ForegroundColor Yellow
            Add-SetupResult Failed $Destination
        }
    } else {
        if (!(Test-Path $Source -PathType Leaf)) {
            Write-Host "[!] Dotfile source missing: $Source" -ForegroundColor Yellow
            Add-SetupResult Failed $Source
            return
        }
        $destinationExists = Test-Path $Destination -PathType Leaf
        if ($destinationExists -and (Get-FileHash $Source).Hash -eq (Get-FileHash $Destination).Hash) {
            Add-SetupResult Skipped $Destination
            return
        }
        try {
            Copy-Item $Source $Destination -Force -ErrorAction Stop
            Add-SetupResult $(if ($destinationExists) { "Updated" } else { "Installed" }) $Destination
        } catch {
            Write-Host "[!] File sync failed: $Destination - $_" -ForegroundColor Yellow
            Add-SetupResult Failed $Destination
        }
    }
}

Sync-Dotfile (Join-Path $dotfiles "global\AGENTS.md") (Join-Path $HOME "AGENTS.md")
Sync-Dotfile (Join-Path $dotfiles "global\AGENTS.md") (Join-Path $HOME ".claude\CLAUDE.md")
Sync-Dotfile (Join-Path $dotfiles "config\nvim") (Join-Path $env:LOCALAPPDATA "nvim")
Sync-Dotfile (Join-Path $dotfiles "config\zellij") (Join-Path $HOME ".config\zellij")
Sync-Dotfile (Join-Path $dotfiles "cursor\cli-config.json") (Join-Path $HOME ".cursor\cli-config.json")

# Podman docker shims for Make/cmd (aliases are PowerShell-only).
if (Get-Command podman -ErrorAction SilentlyContinue) {
    $localBin = Join-Path $HOME ".local\bin"
    New-Item -ItemType Directory -Path $localBin -Force | Out-Null
    Sync-Dotfile (Join-Path $dotfiles "bin\docker.cmd") (Join-Path $localBin "docker.cmd")
    Sync-Dotfile (Join-Path $dotfiles "bin\docker-compose.cmd") (Join-Path $localBin "docker-compose.cmd")
    # Git Bash / MSYS Make look for extensionless names too.
    Sync-Dotfile (Join-Path $dotfiles "bin\docker") (Join-Path $localBin "docker")
    Sync-Dotfile (Join-Path $dotfiles "bin\docker-compose") (Join-Path $localBin "docker-compose")
    Add-UserPath $localBin
}

foreach ($command in @("grammar", "leetcode", "handoff")) {
    Sync-Dotfile (Join-Path $dotfiles "ai\commands\$command.md") (Join-Path $HOME ".cursor\commands\$command.md")
    Sync-Dotfile (Join-Path $dotfiles "ai\commands\$command.md") (Join-Path $HOME ".claude\commands\$command.md")
    Sync-Dotfile (Join-Path $dotfiles "ai\commands\$command.md") (Join-Path $HOME ".zai\commands\$command.md")
    Sync-Dotfile (Join-Path $dotfiles "ai\gemini\$command.toml") (Join-Path $HOME ".gemini\commands\$command.toml")
    $skillSrc = Join-Path $dotfiles "ai\codex\$command"
    Sync-Dotfile $skillSrc (Join-Path $HOME ".agents\skills\$command")
    Sync-Dotfile $skillSrc (Join-Path $HOME ".codex\skills\$command")
    # Antigravity Desktop/CLI/IDE use different roots; config/skills is shared by all.
    Sync-Dotfile $skillSrc (Join-Path $HOME ".gemini\config\skills\$command")
    Sync-Dotfile $skillSrc (Join-Path $HOME ".gemini\antigravity\skills\$command")
    Sync-Dotfile $skillSrc (Join-Path $HOME ".gemini\antigravity-cli\skills\$command")
    Sync-Dotfile $skillSrc (Join-Path $HOME ".gemini\skills\$command")
}

foreach ($name in @("grill-with-docs", "grill-me", "grilling", "domain-modeling")) {
    $src = Join-Path $HOME ".agents\skills\$name"
    if (Test-Path $src) {
        Sync-Dotfile $src (Join-Path $HOME ".gemini\config\skills\$name")
        Sync-Dotfile $src (Join-Path $HOME ".gemini\antigravity\skills\$name")
        Sync-Dotfile $src (Join-Path $HOME ".gemini\antigravity-cli\skills\$name")
        Sync-Dotfile $src (Join-Path $HOME ".gemini\skills\$name")
    }
}

$goEnv = go env GOENV
if ($goEnv) { Sync-Dotfile (Join-Path $dotfiles "go\env") $goEnv }

git config --global include.path (Join-Path $dotfiles "git\gitconfig")
git config --global core.hooksPath (Join-Path $dotfiles "git\hooks")
# Git for Windows ships its own ssh.exe, which cannot use the 1Password SSH agent.
git config --global core.sshCommand "C:/Windows/System32/OpenSSH/ssh.exe"

function Sync-1PasswordSshAgentConfig {
    param([string]$SourceRoot)
    $src = Join-Path $SourceRoot "config\1password\ssh-agent.toml"
    if (!(Test-Path $src)) { return }
    $destDir = Join-Path $env:LOCALAPPDATA "1Password\config\ssh"
    $dest = Join-Path $destDir "agent.toml"
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    $content = Get-Content -LiteralPath $src -Raw
    if ((Test-Path $dest) -and ((Get-Content -LiteralPath $dest -Raw) -eq $content)) {
        Write-Host "[-] 1Password SSH agent config unchanged." -ForegroundColor Gray
        return
    }
    Set-Content -LiteralPath $dest -Value $content -Encoding UTF8
    Write-Host "[+] Synced 1Password SSH agent config ($dest)." -ForegroundColor Green
}

$sshAgentSvc = Get-Service -Name ssh-agent -ErrorAction SilentlyContinue
if ($sshAgentSvc -and $sshAgentSvc.StartType -ne 'Disabled') {
    if ($sshAgentSvc.Status -eq 'Running') { Stop-Service -Name ssh-agent -Force -ErrorAction SilentlyContinue }
    try {
        Set-Service -Name ssh-agent -StartupType Disabled -ErrorAction Stop
        Write-Host "[+] Disabled Windows OpenSSH Authentication Agent (1Password SSH agent)." -ForegroundColor Green
    } catch {
        Write-Host "[!] Could not disable ssh-agent service (run admin once): $_" -ForegroundColor Yellow
    }
} else {
    Write-Host "[-] Windows OpenSSH Authentication Agent already disabled." -ForegroundColor Gray
}
Sync-1PasswordSshAgentConfig -SourceRoot $dotfiles

# --- 8. Window Switcher (sigoden/window-switcher) ---
Write-Host "Checking Alt-Backtick Switcher (sigoden)..." -ForegroundColor Cyan

$wsScoop = Join-Path $HOME "scoop\apps\window-switcher\current"
if (!(Test-Path $wsScoop) -and !(Get-Command window-switcher -ErrorAction SilentlyContinue)) {
    Write-Host "[+] Installing window-switcher via Scoop..." -ForegroundColor Yellow
    Add-ScoopBucket extras
    scoop install window-switcher
}

$wsExe = Get-ChildItem -Path "$env:USERPROFILE\scoop\apps\window-switcher" -Recurse -Filter "window-switcher.exe" | Select-Object -ExpandProperty FullName -First 1

if ($wsExe) {
    if (!(Get-Process window-switcher -ErrorAction SilentlyContinue)) {
        Start-Process $wsExe -WindowStyle Hidden
        Write-Host "Window-Switcher (sigoden) started." -ForegroundColor Green
    }

    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    Set-ItemProperty -Path $regPath -Name "WindowSwitcher" -Value "`"$wsExe`""
}

# --- 9. Profile Injection ---
if (!(Test-Path $PROFILE)) { New-Item -Type File -Path $PROFILE -Force | Out-Null }
$profileLogic = @"
# --- AI & Dev Environment Setup ---
`$env:GOROOT = "$goRootPath"
`$env:GOPATH = "`$HOME\go"
if (`$env:PATH -notlike "*`$HOME\.local\bin*") { `$env:PATH = "`$HOME\.local\bin;`$env:PATH" }
if (`$env:PATH -notlike "*`$HOME\.cargo\bin*") { `$env:PATH = "`$HOME\.cargo\bin;`$env:PATH" }
if (`$env:PATH -notlike "*`$HOME\go\bin*") { `$env:PATH = "`$HOME\go\bin;`$env:PATH" }
if (Get-Command fnm -ErrorAction SilentlyContinue) { fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression }
`$env:PODMAN_COMPOSE_WARNING_LOGS = "false"

# AI keys
function Get-Keys {
    `$env:OPENROUTER_API_KEY = op read "op://Private/OpenRouter/credential"
    `$env:ZAI_API_KEY = op read "op://Private/ZAI/credential"
    `$env:ANTHROPIC_API_KEY = op read "op://Private/Anthropic/credential"
    `$env:GEMINI_API_KEY = op read "op://Private/Gemini/credential"
    Write-Host "AI Keys Loaded from 1Password." -ForegroundColor Green
}

# Aliases
function cc { claude @args }
function ccr { claude --resume @args }
function cdc { Set-Location "`$HOME\code" }
function conf { notepad `$PROFILE }
function jv { param([string]`$name) if (!`$name) { scoop list | Select-String "jdk|lts|liberica|zulu|corretto" } else { scoop reset `$name } }
Set-Alias neofetch fastfetch
Set-Alias vim nvim
Set-Alias vi nvim
"@
if (!(Select-String -Path $PROFILE -Pattern "AI & Dev Environment Setup" -Quiet)) { Add-Content $PROFILE "`n$profileLogic" }
Ensure-DotfilesCurrentUserExecutionPolicy
Add-UserPath (Join-Path $HOME ".local\bin")

# --- 10. AI Agent Initializations ---
Write-Host "Checking AI Agents..." -ForegroundColor Yellow

if (!(Get-Command claude -ErrorAction SilentlyContinue)) { irm https://claude.ai/install.ps1 | iex }

if (!(Get-Command hermes -ErrorAction SilentlyContinue)) {
    $hermesInstaller = Join-Path $env:TEMP "hermes-install.ps1"
    Invoke-WebRequest "https://hermes-agent.nousresearch.com/install.ps1" -OutFile $hermesInstaller
    # Child git inherits this; otherwise git/gitconfig insteadOf rewrites GitHub HTTPS to SSH.
    Protect-ScoopGit {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $hermesInstaller -SkipSetup -NonInteractive
    }
    Remove-Item $hermesInstaller -ErrorAction SilentlyContinue
}

if (!(Get-Command kimi -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Kimi Code CLI..." -ForegroundColor Cyan
    irm https://code.kimi.com/kimi-code/install.ps1 | iex
}

if (Get-Command fnm -ErrorAction SilentlyContinue) {
    fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression
    fnm use --install-if-missing lts-latest
    fnm default lts-latest
}

if (Get-Command npm -ErrorAction SilentlyContinue) {
    function Smart-NpmGlobal {
        param([string]$Package, [string]$Command, [switch]$IgnoreScripts)
        if ($Command -and (Get-Command $Command -ErrorAction SilentlyContinue)) {
            Write-Host "[-] $Command already present. Skipping..." -ForegroundColor Gray
            Add-SetupResult Skipped $Package
            return $true
        }
        Write-Host "[+] Installing $Package..." -ForegroundColor Cyan
        if ($IgnoreScripts) { npm install -g --ignore-scripts $Package --silent | Out-Null }
        else { npm install -g $Package --silent | Out-Null }
        if ($LASTEXITCODE -eq 0) {
            Add-SetupResult Installed $Package
            return $true
        }
        Add-SetupResult Failed $Package
        return $false
    }
    # Pi / Reasonix / dsh / OpenClaw / Impeccable are Node-only. Codex CLI is npm on Windows.
    # OpenCode is Scoop; Copilot is built into gh; Z.ai is uv zai-cli.
    [void](Smart-NpmGlobal "@earendil-works/pi-coding-agent" "pi" -IgnoreScripts)
    [void](Smart-NpmGlobal "reasonix" "reasonix")
    [void](Smart-NpmGlobal "@deepseek-ai/dsh" "dsh")
    [void](Smart-NpmGlobal "wrangler" "wrangler")
    [void](Smart-NpmGlobal "@openai/codex" "codex")
    [void](Smart-NpmGlobal "openclaw@latest" "openclaw")
    [void](Smart-NpmGlobal "impeccable" "impeccable")
    [void](Smart-NpmGlobal "playwright" "playwright")
    $pwBrowsers = Join-Path $env:LOCALAPPDATA "ms-playwright"
    $hasChromium = $false
    if (Test-Path $pwBrowsers) {
        $hasChromium = @(Get-ChildItem -LiteralPath $pwBrowsers -Directory -Filter "chromium*" -ErrorAction SilentlyContinue).Count -gt 0
    }
    if ($hasChromium) {
        Write-Host "[-] Playwright Chromium already installed. Skipping..." -ForegroundColor Gray
    } else {
        npx playwright install chromium
    }
    if (Test-Path (Join-Path $HOME ".cursor\skills\impeccable")) {
        Write-Host "[-] impeccable skills already installed. Skipping..." -ForegroundColor Gray
    } else {
        cmd /c "echo Y| npx --yes impeccable install --scope=global --providers=claude,codex,cursor,gemini,opencode,pi --force"
    }
}

if (!(Get-Command opencode -ErrorAction SilentlyContinue)) {
    Write-Host "[+] Installing OpenCode via Scoop..." -ForegroundColor Cyan
    Add-ScoopBucket extras
    scoop install opencode
}

if (!(Get-Command omp -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Oh My Pi (omp)..." -ForegroundColor Cyan
    irm https://omp.sh/install.ps1 | iex
}

# Goose CLI: Scoop extras first (release tag download_cli.ps1 is 404). Desktop zip is separate.
if (!(Get-Command goose -ErrorAction SilentlyContinue)) {
    $gooseScoop = Join-Path $HOME "scoop\apps\goose\current"
    if (!(Test-Path $gooseScoop)) {
        Write-Host "Installing Goose CLI..." -ForegroundColor Cyan
        Add-ScoopBucket extras
        scoop install goose
        Update-SessionPath
    }
}
if (!(Get-Command goose -ErrorAction SilentlyContinue) -and !(Test-Path (Join-Path $HOME "scoop\apps\goose\current"))) {
    Write-Host "Installing Goose CLI (download_cli.ps1)..." -ForegroundColor Cyan
    $gooseInstaller = Join-Path $env:TEMP "goose-download_cli.ps1"
    $gooseOk = $false
    foreach ($gooseUrl in @(
        "https://raw.githubusercontent.com/block/goose/main/download_cli.ps1",
        "https://raw.githubusercontent.com/aaif-goose/goose/main/download_cli.ps1"
    )) {
        if (Save-RemoteFile $gooseUrl $gooseInstaller) {
            $env:CONFIGURE = "false"
            try {
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $gooseInstaller
                $gooseOk = $true
            } finally {
                Remove-Item Env:CONFIGURE -ErrorAction SilentlyContinue
                Remove-Item $gooseInstaller -ErrorAction SilentlyContinue
            }
            if ($gooseOk) { break }
        }
    }
    if (-not $gooseOk) {
        Write-Host "[!] Goose CLI install failed." -ForegroundColor Yellow
    }
}

$gooseDesktopDir = Join-Path $env:LOCALAPPDATA "Programs\Goose"
$gooseDesktopExe = Join-Path $gooseDesktopDir "Goose.exe"
if (!(Test-Path $gooseDesktopExe)) {
    Write-Host "Installing Goose Desktop..." -ForegroundColor Cyan
    $gooseZip = Join-Path $env:TEMP "Goose-win32-x64.zip"
    $gooseExtract = Join-Path $env:TEMP "Goose-win32-x64"
    try {
        Invoke-WebRequest "https://github.com/aaif-goose/goose/releases/download/stable/Goose-win32-x64.zip" -OutFile $gooseZip
        if (Test-Path $gooseExtract) { Remove-Item $gooseExtract -Recurse -Force }
        Expand-Archive -Path $gooseZip -DestinationPath $gooseExtract -Force
        New-Item -ItemType Directory -Force -Path $gooseDesktopDir | Out-Null
        # Zip may contain a nested folder or files at the root
        $goosePayload = Get-ChildItem $gooseExtract -Directory | Select-Object -First 1
        if ($null -ne $goosePayload) {
            Copy-Item -Path (Join-Path $goosePayload.FullName "*") -Destination $gooseDesktopDir -Recurse -Force
        } else {
            Copy-Item -Path (Join-Path $gooseExtract "*") -Destination $gooseDesktopDir -Recurse -Force
        }
        Write-Host "Goose Desktop installed to $gooseDesktopDir" -ForegroundColor Green
    } catch {
        Write-Host "[!] Goose Desktop install failed: $_" -ForegroundColor Yellow
    } finally {
        Remove-Item $gooseZip -ErrorAction SilentlyContinue
        Remove-Item $gooseExtract -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (Get-Command uv -ErrorAction SilentlyContinue) {
    if (Get-Command zai -ErrorAction SilentlyContinue) {
        Write-Host "[-] zai already present. Skipping..." -ForegroundColor Gray
        Add-SetupResult Skipped "zai-cli"
    } else {
        uv tool install --upgrade zai-cli --python 3
        if ($LASTEXITCODE -eq 0) { Add-SetupResult Installed "zai-cli" }
    }
    if (Get-Command graphify -ErrorAction SilentlyContinue) {
        Write-Host "[-] graphify already present. Skipping..." -ForegroundColor Gray
        Add-SetupResult Skipped "graphifyy"
    } else {
        uv tool install --upgrade graphifyy --python 3
        if ($LASTEXITCODE -eq 0) { Add-SetupResult Installed "graphifyy" }
    }
}

if (Get-Command go -ErrorAction SilentlyContinue) {
    if (Get-Command crush -ErrorAction SilentlyContinue) {
        Write-Host "[-] crush already present. Skipping..." -ForegroundColor Gray
        Add-SetupResult Skipped "crush"
    } else {
        go install github.com/charmbracelet/crush@latest
        if ($LASTEXITCODE -eq 0) { Add-SetupResult Installed "crush" }
    }
}

# GitHub Copilot CLI is winget GitHub.Copilot (`copilot`).
# Do not install github/gh-copilot; that retired extension collides with gh.

# --- 10b. Claude Code & Codex plugins (caveman, ponytail) ---
if (Get-Command claude -ErrorAction SilentlyContinue) {
    Write-Host "Installing Claude Code plugins..." -ForegroundColor Cyan
    Protect-ScoopGit {
        claude plugin marketplace add https://github.com/JuliusBrussee/caveman 2>$null
        claude plugin marketplace add https://github.com/DietrichGebert/ponytail 2>$null
        claude plugin install caveman 2>$null
        claude plugin install ponytail 2>$null
    }
}
if (Get-Command codex -ErrorAction SilentlyContinue) {
    Write-Host "Installing Codex plugins..." -ForegroundColor Cyan
    Protect-ScoopGit {
        codex plugin marketplace add JuliusBrussee/caveman 2>$null
        codex plugin marketplace add DietrichGebert/ponytail 2>$null
        codex plugin add caveman@caveman 2>$null
        codex plugin add ponytail@ponytail 2>$null
    }
}

} # end UserPhase

# --- 11. WSL host provisioning ---
Write-Host "Checking WSL..." -ForegroundColor Cyan

function Get-WslLinuxSetupCommand {
    $root = Get-DotfilesRoot
    $wslRoot = ((& wsl.exe -d $wslDistro -- wslpath -a $root 2>$null | Out-String) -replace "`0", "").Trim()
    if ($wslRoot) {
        # Local clone / checkout: picks up unpushed setup fixes.
        return "bash `"$wslRoot/setup.sh`""
    }
    return "curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/setup.sh | bash"
}

function Write-WslLinuxSetupNextStep {
    Write-Host "[-] WSL Linux stack is separate from Windows setup." -ForegroundColor Gray
    Write-Host "    In Ubuntu, run:" -ForegroundColor Yellow
    Write-Host "      $(Get-WslLinuxSetupCommand)" -ForegroundColor Cyan
}

function Ensure-WslHostReady {
    if (!(Test-WslDistroInstalled $wslDistro)) { return $false }
    if (-not (Ensure-WslNormalUser)) {
        Add-SetupResult Failed "WSL normal user"
        return $false
    }
    wsl.exe -d $wslDistro -- bash -lc "echo ok" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[!] $wslDistro not ready yet (reboot or open Ubuntu once)." -ForegroundColor Yellow
        return $false
    }
    Add-SetupResult Skipped "WSL host"
    return $true
}

function Get-WslListRaw {
    if (!(Get-Command wsl.exe -ErrorAction SilentlyContinue)) { return "" }
    $raw = & wsl.exe -l -v 2>&1 | Out-String
    return ($raw -replace "`0", "")
}

function Test-WslComBroken {
    param([string]$Raw)
    return ($Raw -match "REGDB_E_CLASSNOTREG|Class not registered")
}

function Test-WslDistroInstalled {
    param([string]$Name)
    $raw = Get-WslListRaw
    if (Test-WslComBroken $raw) {
        $script:WslBroken = $true
        return $false
    }
    if ([string]::IsNullOrWhiteSpace($raw)) { return $false }
    if ($raw -match "no installed distributions") { return $false }
    return ($raw -match [regex]::Escape($Name))
}

function Get-WslFeatureState {
    param([string]$FeatureName)
    try {
        return (Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction Stop).State
    } catch {
        return $null
    }
}

function Test-WslVmPlatformReady {
    $state = Get-WslFeatureState "VirtualMachinePlatform"
    return ($state -eq "Enabled") -and (Test-Path "$env:SystemRoot\System32\vmcompute.exe")
}

function Test-WslHypervisorReady {
    if ((Get-CimInstance Win32_ComputerSystem).HypervisorPresent) { return $true }
    $st = if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
        ((& wsl.exe --status 2>&1 | Out-String) -replace "`0", "")
    } else { "" }
    return -not ($st -match "virtualization is not enabled|Virtual Machine Platform")
}

function Write-WslRebootNeeded {
    Write-Host "[!] Virtual Machine Platform needs a reboot before WSL2 can start." -ForegroundColor Yellow
    Write-Host "    Ubuntu is not registered or configured yet. Do not install it from the Store." -ForegroundColor Yellow
    Write-Host "    Start menu > Restart (not Shutdown), then re-run setup." -ForegroundColor Yellow
}

function Write-WslManualVmPlatform {
    Write-Host "[!] Virtual Machine Platform could not be enabled automatically." -ForegroundColor Yellow
    Write-Host "    Do not install Ubuntu from the Store." -ForegroundColor Yellow
    Write-Host "    Use Turn Windows features on or off after checking the DISM log:" -ForegroundColor Yellow
    Write-Host "      Virtual Machine Platform (and Windows Subsystem for Linux if it is off)" -ForegroundColor Cyan
    Write-Host "    Or elevated, after a clean boot (enable only, no disable):" -ForegroundColor Yellow
    Write-Host "      dism /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart" -ForegroundColor Cyan
    Write-Host "    Restart, then:  ubuntu2404.exe install --root" -ForegroundColor Cyan
    Write-Host "    Then Linux: $(Get-WslLinuxSetupCommand)" -ForegroundColor DarkGray
}

function Enable-WslOptionalFeature {
    param([string]$FeatureName)
    if (-not (Test-IsAdmin)) {
        Write-Host "[!] ${FeatureName} needs -AdminPhase (elevated)." -ForegroundColor Yellow
        $script:AdminPhasePending = $true
        return 1
    }
    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName
        if ($feature.State -eq 'Enabled') { return 0 }
        $result = Enable-WindowsOptionalFeature -Online -FeatureName $FeatureName -All -NoRestart
        if ($result.RestartNeeded) { return 3010 }
        if ((Get-WindowsOptionalFeature -Online -FeatureName $FeatureName).State -eq 'Enabled') { return 0 }
        return 1
    } catch {
        Write-Host "[!] Could not enable ${FeatureName}: $_" -ForegroundColor Yellow
        return 1
    }
}

function Ensure-WslVmPlatform {
    $state = Get-WslFeatureState "VirtualMachinePlatform"
    if ($state -eq "Enabled") { return $true }
    if ($state -eq "EnablePending") {
        Write-WslRebootNeeded
        return $false
    }

    Write-Host "[+] Enabling Virtual Machine Platform..." -ForegroundColor Yellow
    $code = Enable-WslOptionalFeature "VirtualMachinePlatform"
    if ($code -eq 3010 -or (Get-WslFeatureState "VirtualMachinePlatform") -eq "EnablePending") {
        Write-WslRebootNeeded
        return $false
    }
    if ($code -ne 0 -or -not (Test-WslVmPlatformReady)) {
        Write-WslManualVmPlatform
        return $false
    }
    Write-Host "[+] Virtual Machine Platform enabled." -ForegroundColor Green
    return $true
}

function Install-UbuntuViaLauncher {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\ubuntu2404.exe"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\ubuntu.exe")
    )
    $ubuntu = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $ubuntu) { return $false }

    Write-Host "[+] Registering Ubuntu with WSL ($ubuntu install --root)..." -ForegroundColor Yellow
    $out = @(& $ubuntu install --root 2>&1 | ForEach-Object { "$_" })
    $out | ForEach-Object { Write-Host $_ }
    if (Test-WslDistroInstalled $wslDistro) { return $true }

    $text = $out -join "`n"
    if ($text -match "0x80370114|required feature is not installed") {
        Write-Host "[!] ubuntu.exe hit 0x80370114 (required Windows feature not active yet)." -ForegroundColor Yellow
        Write-WslRebootNeeded
    }
    return $false
}

function Ensure-WslNormalUser {
    $linuxUser = ($env:USERNAME.ToLower() -replace "[^a-z0-9_-]", "")
    if ([string]::IsNullOrWhiteSpace($linuxUser)) { $linuxUser = "dev" }

    $defaultUser = (& wsl.exe -d $wslDistro -- whoami 2>$null | Out-String).Trim()
    $readyCheck = @"
set -eu
id -u '$linuxUser' >/dev/null
id -nG '$linuxUser' | tr ' ' '\n' | grep -qx sudo
grep -Fxq '$linuxUser ALL=(ALL) NOPASSWD:ALL' '/etc/sudoers.d/dotfiles-$linuxUser'
"@
    & wsl.exe -d $wslDistro -u root -- bash -lc $readyCheck 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0 -and $defaultUser -eq $linuxUser) {
        Write-Host "[-] WSL user $linuxUser is already configured." -ForegroundColor Gray
        return $true
    }

    $userSetup = @'
set -eu
if ! id -u '__DOTFILES_USER__' >/dev/null 2>&1; then
    useradd -m -s /bin/bash -G sudo '__DOTFILES_USER__'
else
    usermod -a -G sudo '__DOTFILES_USER__'
fi
install -d -m 0755 /etc/sudoers.d
printf '%s ALL=(ALL) NOPASSWD:ALL\n' '__DOTFILES_USER__' > '/etc/sudoers.d/dotfiles-__DOTFILES_USER__'
chmod 0440 '/etc/sudoers.d/dotfiles-__DOTFILES_USER__'
'@ -replace "__DOTFILES_USER__", $linuxUser

    Write-Host "[+] Configuring WSL user $linuxUser in $wslDistro..." -ForegroundColor Cyan
    & wsl.exe -d $wslDistro -u root -- bash -lc $userSetup 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[!] Could not create the normal WSL user $linuxUser." -ForegroundColor Yellow
        return $false
    }

    $launcher = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\ubuntu2404.exe"
    if (Test-Path -LiteralPath $launcher) {
        & $launcher config --default-user $linuxUser 2>&1 | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -eq 0) {
            & wsl.exe --terminate $wslDistro 2>$null
            return $true
        }
    }

    $defaultSetup = @'
set -eu
if [ -f /etc/wsl.conf ] && grep -q '^\[user\]' /etc/wsl.conf; then
    if grep -q '^default=' /etc/wsl.conf; then
        sed -i "/^\[user\]/,/^\[/ s/^default=.*/default=__DOTFILES_USER__/" /etc/wsl.conf
    else
        sed -i "/^\[user\]/a default=__DOTFILES_USER__" /etc/wsl.conf
    fi
else
    printf '\n[user]\ndefault=__DOTFILES_USER__\n' >> /etc/wsl.conf
fi
'@ -replace "__DOTFILES_USER__", $linuxUser
    & wsl.exe -d $wslDistro -u root -- bash -lc $defaultSetup 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[!] Could not set $linuxUser as the WSL default user." -ForegroundColor Yellow
        return $false
    }
    & wsl.exe --terminate $wslDistro 2>$null
    return $true
}

# VMP can be Enabled while the hypervisor never starts if this BCD flag is missing.
function Set-HypervisorLaunchAuto {
    $enum = (& bcdedit.exe /enum "{current}" 2>&1 | Out-String)
    if ($enum -match "hypervisorlaunchtype\s+Auto") { return $true }
    if (-not (Test-IsAdmin)) {
        Write-Host "[!] hypervisorlaunchtype Auto needs -AdminPhase (elevated)." -ForegroundColor Yellow
        $script:AdminPhasePending = $true
        return $false
    }
    Write-Host "[+] Setting hypervisorlaunchtype Auto (needed for WSL2)..." -ForegroundColor Yellow
    & bcdedit.exe /set '{current}' hypervisorlaunchtype Auto
    return ($LASTEXITCODE -eq 0)
}

function Get-WslMsiUrl {
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "x64" }
    try {
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/WSL/releases/latest" -Headers @{ "User-Agent" = "dotfiles-setup" }
        $asset = $rel.assets | Where-Object { $_.name -like "wsl.*.$arch.msi" } | Select-Object -First 1
        if ($asset) { return $asset.browser_download_url }
    } catch {
        Write-Host "[!] GitHub WSL release lookup failed: $_" -ForegroundColor Yellow
    }
    return $null
}

# CLASSNOTREG means wsl --install cannot run the inbox MSI. Installing the
# GitHub wsl.msi as admin is the usual repair; UAC is required.
function Invoke-WslMsiRepair {
    param([string]$Distro)
    if (-not (Test-IsAdmin)) {
        Write-Host "[!] WSL repair needs -AdminPhase (elevated)." -ForegroundColor Yellow
        $script:AdminPhasePending = $true
        return $false
    }
    $url = Get-WslMsiUrl
    if (-not $url) {
        Write-Host "[!] Could not resolve official wsl.msi from GitHub releases." -ForegroundColor Yellow
        return $false
    }

    Write-Host "[+] WSL COM is broken. Installing official wsl.msi..." -ForegroundColor Yellow
    $msi = Join-Path $env:TEMP "wsl-setup.msi"
    if (-not (Save-RemoteFile $url $msi)) {
        Write-Host "[!] Failed to download wsl.msi after retries. Re-run, or install from https://github.com/microsoft/WSL/releases" -ForegroundColor Yellow
        return $false
    }

    $log = Join-Path $env:TEMP "dotfiles-wsl-msi.log"
    try {
        Write-Host 'Enabling WSL Windows features (no reboot yet)...'
        & dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
        & dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
        Write-Host 'Installing wsl.msi...'
        $p = Start-Process msiexec.exe -ArgumentList @('/i', $msi, '/qn', '/norestart', '/L*v', $log) -Wait -PassThru
        Write-Host ("msiexec exit " + $p.ExitCode)
        if ($p.ExitCode -notin 0, 1641, 3010) { return $false }
        Write-Host "Installing distro $Distro..."
        & wsl.exe --install -d $Distro --no-launch
        if ($LASTEXITCODE -ne 0) { return $false }
    } catch {
        Write-Host "[!] WSL repair failed: $_" -ForegroundColor Yellow
        Write-Host "    Manual: msiexec /i $msi ; wsl --install -d $Distro" -ForegroundColor DarkGray
        return $false
    }

    $script:WslBroken = $false
    $raw = Get-WslListRaw
    if (Test-WslComBroken $raw) {
        $script:WslBroken = $true
        Write-Host "[!] WSL still reports CLASSNOTREG. Reboot, then re-run -AdminPhase." -ForegroundColor Yellow
        Write-Host "    MSI log: $log" -ForegroundColor DarkGray
        Write-Host "    If it persists after reboot, Windows repair install is the remaining fix." -ForegroundColor DarkGray
        return $false
    }
    return $true
}

function Invoke-DotfilesWslAdminProvisioning {
    $script:WslBroken = $false
    $wslInstalled = Test-WslDistroInstalled $wslDistro
    if (-not (Test-WslHypervisorReady)) {
        [void](Set-HypervisorLaunchAuto)
    }

    $wslVmReady = Test-WslVmPlatformReady
    if (-not $wslVmReady) {
        $wslVmReady = Ensure-WslVmPlatform
    }

    if ($wslVmReady -and $script:WslBroken) {
        [void](Invoke-WslMsiRepair $wslDistro)
        $wslInstalled = Test-WslDistroInstalled $wslDistro
    }

    if ($wslInstalled) {
        Write-Host "[-] WSL $wslDistro is already installed." -ForegroundColor Gray
        if ($wslVmReady) {
            if (Ensure-WslHostReady) { Write-WslLinuxSetupNextStep }
        } else {
            Write-WslRebootNeeded
        }
    } elseif ($wslVmReady) {
        Write-Host "[+] Installing $wslDistro via Winget..." -ForegroundColor Yellow
        winget install -e --id $wslPackageId --accept-package-agreements --accept-source-agreements --silent --source winget 2>&1 | Out-Host
        $repaired = (Test-WslDistroInstalled $wslDistro)
        if (-not $repaired) {
            $repaired = Install-UbuntuViaLauncher
        }
        if ($repaired) {
            if (Ensure-WslHostReady) { Write-WslLinuxSetupNextStep }
        } elseif (-not (Test-WslVmPlatformReady)) {
            Write-WslRebootNeeded
        } else {
            Write-Host "[!] Ubuntu did not register a WSL distro." -ForegroundColor Yellow
            Write-Host "    Do not Store-install Ubuntu. After the WSL host is ready: re-run -AdminPhase." -ForegroundColor Yellow
        }
    }
}

function Invoke-DotfilesUserPhaseWslCheck {
    if (Test-WslDistroInstalled $wslDistro) {
        if (Ensure-WslHostReady) { Write-WslLinuxSetupNextStep }
        return
    }
    if (-not (Test-WslVmPlatformReady) -or -not (Test-WslHypervisorReady)) {
        Write-Host "[!] WSL host features are not ready. Run -AdminPhase (elevated)." -ForegroundColor Yellow
        $script:AdminPhasePending = $true
        return
    }
    Write-Host "[!] Ubuntu is not registered yet. Run -AdminPhase (elevated)." -ForegroundColor Yellow
    $script:AdminPhasePending = $true
}

function Invoke-DotfilesAdminPhase {
    Write-Host "==> Dotfiles admin phase (elevated)" -ForegroundColor Cyan
    Set-WindowsHostAdminDefaults
    Install-DeskflowFirewallRule
    Remove-Item -LiteralPath $script:WingetDeferFile -Force -ErrorAction SilentlyContinue
    Write-Host "[+] Upgrading Microsoft.VCRedist.2015+.x64 if a newer build exists..." -ForegroundColor Cyan
    winget upgrade -e --id Microsoft.VCRedist.2015+.x64 --accept-package-agreements --accept-source-agreements --silent --source winget
    $adminWinget = Get-DotfilesWingetAdminApps
    Write-Host "[+] Installing Winget apps in admin phase ($($adminWinget.Count) packages, denylist $($script:WingetDenylist.Count))..." -ForegroundColor Cyan
    Install-WingetApps -Apps $adminWinget -AdminOnly
    Install-VsBuildTools
    Uninstall-GeForceExperience
    Invoke-DotfilesWslAdminProvisioning
    Unregister-DotfilesAdminPhaseTask
}

# --- 12. Final Polish ---
if (Test-DotfilesRunAdminPhase) {
    Invoke-DotfilesAdminPhase
    if ($script:SetupResults.Failed -eq 0) {
        Write-Host "ADMIN PHASE COMPLETE." -ForegroundColor Green
    } else {
        Write-Host "ADMIN PHASE FINISHED WITH FAILURES." -ForegroundColor Yellow
    }
    Write-SetupSummary
    if ($script:ChainUserPhase) {
        Write-Host ""
        Start-DotfilesUserPhaseNonElevated -Wait | Out-Null
    } else {
        Write-Host ""
        Write-Host "Next: reboot if WSL reported a pending feature change, then start WSL Linux setup." -ForegroundColor Yellow
        Write-Host "  $(Get-WslLinuxSetupCommand)" -ForegroundColor Cyan
    }
    return
}

Invoke-DotfilesUserPhaseWslCheck
Set-WindowsHostUserDefaults
if (Test-DotfilesRunUserPhase) { scoop cleanup * }
if ($script:SetupResults.Failed -eq 0) {
    Write-Host "SETUP COMPLETE." -ForegroundColor Green
} else {
    Write-Host "SETUP FINISHED WITH FAILURES." -ForegroundColor Yellow
}
Write-SetupSummary
if ($script:ChainAdminPhase -and $script:AdminPhasePending) {
    Write-Host ""
    Write-Host "[+] Admin phase required. Elevating (one UAC)..." -ForegroundColor Yellow
    $adminCode = Start-DotfilesAdminPhaseElevated
    if ($adminCode -ne 0) {
        Write-Host "[!] Admin phase did not start (exit $adminCode)." -ForegroundColor Yellow
        Write-DotfilesAdminPhaseNextSteps
    }
} elseif ($script:AdminPhasePending) {
    Write-DotfilesAdminPhaseNextSteps
    if ($ScheduleAdminPhase) {
        Register-DotfilesAdminPhaseTask
    }
}
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Reboot if WSL host reported a pending feature change" -ForegroundColor Yellow
Write-Host "  2. WSL Linux stack (in Ubuntu):" -ForegroundColor Yellow
Write-Host "     $(Get-WslLinuxSetupCommand)" -ForegroundColor Cyan
Write-Host "  3. Sign into 1Password, then:" -ForegroundColor Yellow
Write-Host "     irm https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/post-setup.ps1 | iex" -ForegroundColor Cyan
Write-Host "  4. Bitbucket repo sync (after SSH agent ready):" -ForegroundColor Yellow
Write-Host "     `$s=`$env:TEMP\post-setup.ps1; irm https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/post-setup.ps1 -OutFile `$s; & `$s -SyncBitbucket" -ForegroundColor Cyan
Write-Host ""
Write-Host "Manual follow-ups:" -ForegroundColor Yellow
Write-Host "  - NVIDIA App: update the Game Ready driver in the app (GFE is uninstalled)"
Write-Host "  - G-Helper: uninstall or quit Armoury Crate if both are installed"
Write-Host "  - DisplayLink: reboot after -AdminPhase if Winget still reports 1603"
Write-Host "  - Deskflow: needs VC++ 14.50+; setup upgrades Microsoft.VCRedist.2015+.x64 first"
Write-Host "  - LibreOffice: reboot if the MSI asked to finish install"
Write-Host "  - WSL host: -AdminPhase enables Virtual Machine Platform; reboot before Linux setup if Windows reports a pending feature change"
Write-Host "  - Hibernate / long paths / Smart App Control Off: applied by -AdminPhase"
Write-Host "  - ThreeFingerDrag: log off once if three-finger still opens Task View"
Write-Host "  - Wavlink: install drivers for your model from https://www.wavlink.com/en_us/Drivers.html"
Write-Host "  - C920: disable HD Pro Webcam C920 under Sound, video and game controllers if Windows Audio dies (leave the Cameras entry on)"
Write-Host "  - Antigravity / Goose / Cursor / Claude: sign in in each desktop app"
Write-Host "  - Ollama: pull a model (e.g. ollama pull llama3.2)"
Write-Host "  - Kubernetes: kind create cluster / k3d cluster create when Podman is running"
Write-Host "  - Java: jv temurin21-jdk"
Stop-DotfilesUserPhaseLogging
if ((Test-DotfilesRunUserPhase) -and (Test-Path $script:UserPhaseLogFile)) {
    Write-Host ""
    Write-Host "User phase log: $script:UserPhaseLogFile" -ForegroundColor Gray
}
