# Windows setup - mirrors the macOS/WSL tool stack via Scoop + Winget.

# --- 0. Pre-Flight ---
# Restricted is the Windows default, so the profile fails to load until this is set.
# CurrentUser first (persists). Process Bypass after that, or PowerShell errors that
# CurrentUser is overridden by the more specific Process scope.
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
# irm | iex often starts in System32; keep installers from writing into that tree.
Set-Location $HOME

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

function Test-WingetExit1603 {
    param([string]$Text, [int]$Code)
    return ($Code -eq 1603) -or ($Text -match "exit code:\s*1603")
}

function Test-WingetAdminContext {
    param([string]$Text)
    return $Text -match "cannot be run from an administrator context"
}

# Winget's Warp.Warp installer URL is an HTML landing page, so `winget install`
# sits on "Downloading https://app.warp.dev/download/windows?..." forever.
function Install-Warp {
    $existing = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Warp\Warp.exe"),
        (Join-Path $env:LOCALAPPDATA "Warp\Warp.exe")
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($existing) {
        Write-Host "[-] Warp is already installed." -ForegroundColor Gray
        return
    }

    Write-Host "[+] Installing Warp..." -ForegroundColor Cyan
    $show = winget show -e --id Warp.Warp --source winget 2>$null | Out-String
    if ($show -notmatch '(?m)^\s*Version:\s+(\S+)') {
        Write-Host "[!] Could not read Warp version from Winget. Skipping." -ForegroundColor Yellow
        return
    }
    $ver = $Matches[1]
    $setup = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "WarpSetup-arm64.exe" } else { "WarpSetup.exe" }
    $url = "https://releases.warp.dev/stable/$ver/$setup"
    $out = Join-Path $env:TEMP $setup
    Write-Host "    $url"
    & curl.exe -fL --retry 3 $url -o $out
    if (($LASTEXITCODE -ne 0) -or !(Test-Path $out) -or ((Get-Item $out).Length -lt 1MB)) {
        Write-Host "[!] Warp download failed. Skipping." -ForegroundColor Yellow
        return
    }
    $proc = Start-Process -FilePath $out -ArgumentList "/VERYSILENT", "/NORESTART", "/SUPPRESSMSGBOXES" -Wait -PassThru
    Remove-Item $out -ErrorAction SilentlyContinue
    if ($proc.ExitCode -ne 0) {
        Write-Host "[!] Warp installer exit $($proc.ExitCode)." -ForegroundColor Yellow
    } else {
        Write-Host "[+] Warp installed." -ForegroundColor Green
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

function Set-WindowsHostDefaults {
    Write-Host "Applying Windows defaults..." -ForegroundColor Cyan

    $adv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    Set-ItemProperty -Path $adv -Name HideFileExt -Type DWord -Value 0 -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $adv -Name Hidden -Type DWord -Value 1 -ErrorAction SilentlyContinue
    # Settings > Personalization > Taskbar > Taskbar items: hide Search, Task view,
    # Widgets, Chat, Copilot, Resume. TaskbarDa is ACL-locked on some builds.
    Set-ItemProperty -Path $adv -Name MultiTaskingAltTabFilter -Type DWord -Value 3 -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $adv -Name ShowTaskViewButton -Type DWord -Value 0 -ErrorAction SilentlyContinue
    foreach ($name in @("TaskbarDa", "TaskbarMn", "ShowCopilotButton", "IsEnabled")) {
        & reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v $name /t REG_DWORD /d 0 /f 2>$null | Out-Null
    }
    $search = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
    if (!(Test-Path $search)) { New-Item -Path $search -Force | Out-Null }
    Set-ItemProperty -Path $search -Name SearchboxTaskbarMode -Type DWord -Value 0
    Set-ItemProperty -Path $search -Name SearchboxTaskbarModeCache -Type DWord -Value 0
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
    try {
        $sac = "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy"
        if (Test-Path $sac) {
            Set-ItemProperty -Path $sac -Name VerifiedAndReputablePolicyState -Type DWord -Value 0 -ErrorAction Stop
        }
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name SmartScreenEnabled -Type String -Value "Warn" -ErrorAction Stop
        if (Get-Command Set-MpPreference -ErrorAction SilentlyContinue) {
            Set-MpPreference -PUAProtection 1 -ErrorAction Stop
        }
    } catch {
        Write-Host "[!] Smart App Control Off / SmartScreen HKLM skipped (needs elevation)." -ForegroundColor Yellow
    }

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

    powercfg /hibernate on 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[!] Hibernate skipped (needs an elevated PowerShell)." -ForegroundColor Yellow
    } else {
        try {
            $fly = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings"
            if (!(Test-Path $fly)) { New-Item -Path $fly -Force -ErrorAction Stop | Out-Null }
            Set-ItemProperty -Path $fly -Name ShowHibernateOption -Type DWord -Value 1 -ErrorAction Stop
            Set-ItemProperty -Path $fly -Name ShowSleepOption -Type DWord -Value 1 -ErrorAction Stop
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name LongPathsEnabled -Type DWord -Value 1 -ErrorAction Stop
            $dsh = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
            if (!(Test-Path $dsh)) { New-Item -Path $dsh -Force -ErrorAction Stop | Out-Null }
            Set-ItemProperty -Path $dsh -Name AllowNewsAndInterests -Type DWord -Value 0 -ErrorAction Stop
            $winFeeds = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds"
            if (!(Test-Path $winFeeds)) { New-Item -Path $winFeeds -Force -ErrorAction Stop | Out-Null }
            Set-ItemProperty -Path $winFeeds -Name EnableFeeds -Type DWord -Value 0 -ErrorAction Stop
        } catch {
            Write-Host "[!] Hibernate power-menu / long paths / Widgets policy skipped (needs elevation)." -ForegroundColor Yellow
        }
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
            foreach ($name in $unpinNames) {
                $item = $appsFolder.Items() | Where-Object { $_.Name -eq $name } | Select-Object -First 1
                & $unpinFromTaskbar $item
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
    } catch {}

    Set-WindowsStartupApps
}

function Set-StartupApproved {
    param([string]$Key, [string]$Name, [bool]$Enabled)
    if (!(Test-Path $Key)) { New-Item -Path $Key -Force | Out-Null }
    $flag = if ($Enabled) { [byte]2 } else { [byte]3 }
    $bytes = [byte[]](@($flag) + @(0) * 11)
    New-ItemProperty -Path $Key -Name $Name -PropertyType Binary -Value $bytes -Force -ErrorAction SilentlyContinue | Out-Null
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

function Set-WindowsStartupApps {
    Write-Host "Applying startup app allow/deny list..." -ForegroundColor Cyan
    $run = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
    $folder = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder"
    $runLm = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
    $runLmWow = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32"

    foreach ($name in @(
        "TrafficMonitor",
        "WindowSwitcher",
        "Surfshark",
        "GoogleDriveFS",
        "OneDrive",
        "Everything",
        "Free Download Manager"
    )) { Set-StartupApproved $run $name $true }

    foreach ($name in @(
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
        "WingetUI"
    )) { Set-StartupApproved $run $name $false }

    Set-StartupApproved $folder "Ollama.lnk" $false

    foreach ($pair in @(
        @{ Key = $runLm; Name = "Virtual Pet"; On = $false },
        @{ Key = $runLm; Name = "SecurityHealth"; On = $true },
        @{ Key = $runLm; Name = "DisplayLinkTrayApp"; On = $true },
        @{ Key = $runLmWow; Name = "ASUS Smart Display Control"; On = $false }
    )) {
        try { Set-StartupApproved $pair.Key $pair.Name $pair.On } catch {}
    }

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

# Scoop check - skip packages already in scoop export.
function Smart-Scoop {
    param([string]$app)
    $installedList = scoop export
    if ($installedList -like "*$app*") {
        Write-Host "[-] $app is already installed. Skipping..." -ForegroundColor Gray
    } else {
        Write-Host "[+] $app not found. Installing now..." -ForegroundColor Cyan
        scoop install $app
    }
}

# --- 2. Core Dependencies & Buckets ---
foreach ($b in @("extras", "versions", "nerd-fonts", "java")) { Add-ScoopBucket $b }

$core = @("git", "7zip", "gh", "go", "rustup-msvc", "fastfetch", "aria2")
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
Write-Host "Checking Winget Apps..." -ForegroundColor Cyan
# Deskflow's MSI requires VC++ 14.50+. Winget can report the ID installed at 14.30.
Write-Host "[+] Upgrading Microsoft.VCRedist.2015+.x64 if a newer build exists..." -ForegroundColor Cyan
winget upgrade -e --id Microsoft.VCRedist.2015+.x64 --accept-package-agreements --accept-source-agreements --silent --source winget

$wingetApps = @(
    "Microsoft.VCRedist.2015+.x64",
    "Microsoft.DotNet.DesktopRuntime.10",
    "AgileBits.1Password", "Surfshark.Surfshark", "OpenVPNTechnologies.OpenVPNConnect",
    "Anysphere.Cursor", "Anthropic.Claude", "MoonshotAI.Kimi", "Microsoft.PowerToys",
    "Devolutions.UniGetUI", "PatchMyPC.PatchMyPC",
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
    "TheDocumentFoundation.LibreOffice", "ONLYOFFICE.DesktopEditors",
    "FilesCommunity.Files",
    "VideoLAN.VLC", "Stremio.Stremio",
    "CodecGuide.K-LiteCodecPack.Full",
    "qBittorrent.qBittorrent", "Transmission.Transmission",
    "SoftDeluxe.FreeDownloadManager",
    "Valve.Steam",
    "ElectronicArts.EADesktop",
    "RiotGames.Valorant.AP",
    "DisplayLink.GraphicsDriver",
    "seerge.g-helper",
    "erez-c137.NetSpeedTray", "zhongyang219.TrafficMonitor.Lite"
)

foreach ($app in $wingetApps) {
    $check = winget list --id $app --source winget 2>$null
    if ($null -eq $check -or $check -match "No installed package found") {
        Write-Host "[+] Installing $app..." -ForegroundColor Cyan
        $wingetLines = @()
        winget install -e --id $app --accept-package-agreements --accept-source-agreements --silent --source winget 2>&1 | Tee-Object -Variable wingetLines
        $wingetText = @($wingetLines | ForEach-Object { "$_" }) -join "`n"
        $wingetCode = $LASTEXITCODE
        if (Test-WingetExit1603 $wingetText $wingetCode) {
            if ($app -eq "Deskflow.Deskflow") {
                Write-Host "[!] Deskflow needs VC++ 14.50+ (Winget may still have 14.30). Upgrade Microsoft.VCRedist.2015+.x64, then re-run." -ForegroundColor Yellow
            } else {
                Write-Host "[!] $app installer needs elevation or a reboot (exit 1603). Skipping retry." -ForegroundColor Yellow
            }
        } elseif (Test-WingetAdminContext $wingetText) {
            Write-Host "[!] $app installer refuses an elevated session. Skipping retry." -ForegroundColor Yellow
        } elseif ($wingetCode -ne 0) {
            Write-Host "[!] Exact ID failed for $app. Attempting search-install..." -ForegroundColor Yellow
            winget install $app --accept-package-agreements --accept-source-agreements --silent
        }
    } else {
        Write-Host "[-] $app is already installed." -ForegroundColor Gray
    }
}

Install-Warp

Initialize-TrafficMonitor

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
)
foreach ($app in $msStoreApps) {
    if (Get-AppxPackage -Name $app.Appx -ErrorAction SilentlyContinue) {
        Write-Host "[-] $($app.Label) is already installed." -ForegroundColor Gray
        continue
    }
    Write-Host "[+] Installing $($app.Label)..." -ForegroundColor Cyan
    winget install --id $app.Id --source msstore --accept-package-agreements --accept-source-agreements --silent
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
        if (Test-Path $Destination) { Remove-Item $Destination -Recurse -Force }
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        Copy-Item (Join-Path $Source "*") $Destination -Recurse -Force
    } else {
        Copy-Item $Source $Destination -Force
    }
}

Sync-Dotfile (Join-Path $dotfiles "global\AGENTS.md") (Join-Path $HOME "AGENTS.md")
Sync-Dotfile (Join-Path $dotfiles "global\AGENTS.md") (Join-Path $HOME ".claude\CLAUDE.md")
Sync-Dotfile (Join-Path $dotfiles "config\nvim") (Join-Path $env:LOCALAPPDATA "nvim")
Sync-Dotfile (Join-Path $dotfiles "config\zellij") (Join-Path $HOME ".config\zellij")
Sync-Dotfile (Join-Path $dotfiles "cursor\cli-config.json") (Join-Path $HOME ".cursor\cli-config.json")

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

# --- 7. Deskflow Firewall Rule ---
Write-Host "Opening Port 24800 for Deskflow..." -ForegroundColor Cyan
$dfRule = "Deskflow Inbound (TCP 24800)"
try {
    if (!(Get-NetFirewallRule -DisplayName $dfRule -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $dfRule -Direction Inbound -LocalPort 24800 -Protocol TCP -Action Allow -Description "Deskflow KVM" -ErrorAction Stop | Out-Null
    }
} catch {
    Write-Host "[!] Deskflow firewall rule skipped (needs an elevated PowerShell)." -ForegroundColor Yellow
}

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
        if ($Command -and (Get-Command $Command -ErrorAction SilentlyContinue)) { return $false }
        Write-Host "[+] Installing $Package..." -ForegroundColor Cyan
        if ($IgnoreScripts) { npm install -g --ignore-scripts $Package --silent | Out-Null }
        else { npm install -g $Package --silent | Out-Null }
        return $true
    }
    # Pi / Reasonix / dsh / OpenClaw / Impeccable are Node-only. Codex CLI is npm on Windows.
    # OpenCode is Scoop; Copilot is built into gh; Z.ai is uv zai-cli.
    $installedAny = $false
    $installedAny = (Smart-NpmGlobal "@earendil-works/pi-coding-agent" "pi" -IgnoreScripts) -or $installedAny
    $installedAny = (Smart-NpmGlobal "reasonix" "reasonix") -or $installedAny
    $installedAny = (Smart-NpmGlobal "@deepseek-ai/dsh" "dsh") -or $installedAny
    $installedAny = (Smart-NpmGlobal "wrangler" "wrangler") -or $installedAny
    $installedAny = (Smart-NpmGlobal "@openai/codex" "codex") -or $installedAny
    $installedAny = (Smart-NpmGlobal "openclaw@latest" "openclaw") -or $installedAny
    $installedAny = (Smart-NpmGlobal "impeccable" "impeccable") -or $installedAny
    $installedAny = (Smart-NpmGlobal "playwright" "playwright") -or $installedAny
    if (-not $installedAny) {
        Write-Host "[-] Node AI CLIs already installed. Skipping..." -ForegroundColor Gray
    }
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
    uv tool install zai-cli --python 3
    uv tool install graphifyy --python 3
}

if (Get-Command go -ErrorAction SilentlyContinue) {
    go install github.com/charmbracelet/crush@latest
}

# gh ships a built-in `copilot` command; github/gh-copilot collides with it.

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

# --- 11. WSL host provisioning ---
Write-Host "Checking WSL..." -ForegroundColor Cyan

$wslDistro = "Ubuntu"
$wslSetupCmd = "curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/setup.sh | bash"

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = [Security.Principal.WindowsPrincipal]::new($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
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

function Test-WslVmPlatformReady {
    return (Test-Path "$env:SystemRoot\System32\vmcompute.exe") -or [bool](Get-Service vmcompute -ErrorAction SilentlyContinue)
}

function Test-WslHypervisorReady {
    if ((Get-CimInstance Win32_ComputerSystem).HypervisorPresent) { return $true }
    $st = if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
        ((& wsl.exe --status 2>&1 | Out-String) -replace "`0", "")
    } else { "" }
    return -not ($st -match "virtualization is not enabled|Virtual Machine Platform")
}

function Write-WslRebootNeeded {
    Write-Host "[!] Hyper-V Host Compute (vmcompute) is still missing." -ForegroundColor Yellow
    Write-Host "    Ubuntu is not registered yet. Do not install it from the Store." -ForegroundColor Yellow
    Write-Host "    Start menu > Restart (not Shutdown), then re-run setup." -ForegroundColor Yellow
}

function Enable-WslWindowsFeatures {
    if (Test-WslVmPlatformReady) { return $true }
    Write-Host "[+] Reinstalling Virtual Machine Platform (UAC). DISM enable-only is a no-op here." -ForegroundColor Yellow
    $helper = Join-Path $env:TEMP "dotfiles-wsl-features.ps1"
    $log = Join-Path $env:TEMP "dotfiles-wsl-features.log"
    @"
`$ErrorActionPreference = 'Continue'
`$log = '$($log -replace "'", "''")'
Start-Transcript -Path `$log -Force | Out-Null
foreach (`$f in @('VirtualMachinePlatform','HypervisorPlatform','Microsoft-Windows-Subsystem-Linux')) {
    Write-Host ("disable " + `$f)
    dism.exe /online /disable-feature /featurename:`$f /norestart
}
foreach (`$f in @('VirtualMachinePlatform','HypervisorPlatform','Microsoft-Windows-Subsystem-Linux')) {
    Write-Host ("enable " + `$f)
    dism.exe /online /enable-feature /featurename:`$f /all /norestart
}
Stop-Transcript | Out-Null
exit 0
"@ | Set-Content -Path $helper -Encoding ASCII
    try {
        if (Test-IsAdmin) {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $helper
        } else {
            $proc = Start-Process -FilePath powershell.exe -Verb RunAs -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $helper) -Wait -PassThru
            if ($null -eq $proc) { throw "elevation returned no process" }
        }
    } catch {
        Write-Host "[!] Could not repair WSL Windows features: $_" -ForegroundColor Yellow
        Write-Host "    Elevated DISM disable+enable VirtualMachinePlatform, HypervisorPlatform, Microsoft-Windows-Subsystem-Linux" -ForegroundColor Cyan
        return $false
    }
    if (Test-WslVmPlatformReady) { return $true }
    Write-Host "    DISM log: $log" -ForegroundColor DarkGray
    return $false
}

function Install-UbuntuViaLauncher {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\ubuntu.exe"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\ubuntu2404.exe"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\ubuntu2204.exe")
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

# VMP can be Enabled while the hypervisor never starts if this BCD flag is missing.
function Set-HypervisorLaunchAuto {
    $enum = (& bcdedit.exe /enum "{current}" 2>&1 | Out-String)
    if ($enum -match "hypervisorlaunchtype\s+Auto") { return $true }
    Write-Host "[+] Setting hypervisorlaunchtype Auto (needed for WSL2)..." -ForegroundColor Yellow
    $helper = Join-Path $env:TEMP "dotfiles-hv-launch.ps1"
    "bcdedit.exe /set '{current}' hypervisorlaunchtype Auto; exit `$LASTEXITCODE" | Set-Content -Path $helper -Encoding ASCII
    try {
        if (Test-IsAdmin) {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $helper
            return ($LASTEXITCODE -eq 0)
        }
        $proc = Start-Process -FilePath powershell.exe -Verb RunAs -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $helper) -Wait -PassThru
        if ($null -eq $proc) { throw "elevation returned no process" }
        return ($proc.ExitCode -eq 0)
    } catch {
        Write-Host "[!] Could not set hypervisorlaunchtype Auto: $_" -ForegroundColor Yellow
        Write-Host "    Elevated: bcdedit /set `{current`} hypervisorlaunchtype Auto" -ForegroundColor Cyan
        return $false
    }
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
    $url = Get-WslMsiUrl
    if (-not $url) {
        Write-Host "[!] Could not resolve official wsl.msi from GitHub releases." -ForegroundColor Yellow
        return $false
    }

    Write-Host "[+] WSL COM is broken. Installing official wsl.msi (UAC prompt)..." -ForegroundColor Yellow
    $msi = Join-Path $env:TEMP "wsl-setup.msi"
    if (-not (Save-RemoteFile $url $msi)) {
        Write-Host "[!] Failed to download wsl.msi after retries. Re-run, or install from https://github.com/microsoft/WSL/releases" -ForegroundColor Yellow
        return $false
    }

    $helper = Join-Path $env:TEMP "dotfiles-wsl-repair.ps1"
    $log = Join-Path $env:TEMP "dotfiles-wsl-msi.log"
    @"
`$ErrorActionPreference = 'Continue'
Write-Host 'Enabling WSL Windows features (no reboot yet)...'
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
Write-Host 'Installing wsl.msi...'
`$p = Start-Process msiexec.exe -ArgumentList @('/i', '$($msi -replace "'", "''")', '/qn', '/norestart', '/L*v', '$($log -replace "'", "''")') -Wait -PassThru
Write-Host ("msiexec exit " + `$p.ExitCode)
if (`$p.ExitCode -notin 0, 1641, 3010) { exit `$p.ExitCode }
Write-Host 'Installing distro $Distro...'
wsl.exe --install -d '$($Distro -replace "'", "''")' --no-launch
exit `$LASTEXITCODE
"@ | Set-Content -Path $helper -Encoding UTF8

    try {
        if (Test-IsAdmin) {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $helper
        } else {
            $proc = Start-Process -FilePath powershell.exe -Verb RunAs -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $helper) -Wait -PassThru
            if ($null -eq $proc) { throw "elevation returned no process" }
        }
    } catch {
        Write-Host "[!] WSL repair elevation cancelled or failed: $_" -ForegroundColor Yellow
        Write-Host "    Manual: msiexec /i $msi ; wsl --install -d $Distro" -ForegroundColor DarkGray
        return $false
    }

    $script:WslBroken = $false
    $raw = Get-WslListRaw
    if (Test-WslComBroken $raw) {
        $script:WslBroken = $true
        Write-Host "[!] WSL still reports CLASSNOTREG. Reboot, then re-run setup." -ForegroundColor Yellow
        Write-Host "    MSI log: $log" -ForegroundColor DarkGray
        Write-Host "    If it persists after reboot, Windows repair install is the remaining fix." -ForegroundColor DarkGray
        return $false
    }
    return $true
}

function Invoke-WslLinuxSetup {
    if (!(Test-WslDistroInstalled $wslDistro)) { return }

    wsl.exe -d $wslDistro -- bash -lc "echo ok" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[!] $wslDistro not ready yet (reboot or open Ubuntu once)." -ForegroundColor Yellow
        Write-Host "    Then re-run setup or: $wslSetupCmd" -ForegroundColor DarkGray
        return
    }

    $needsSetup = wsl.exe -d $wslDistro -- bash -lc 'grep -q "MISSION READY DEV ENV" ~/.bashrc 2>/dev/null || grep -q "MISSION READY DEV ENV" ~/.zshrc 2>/dev/null; echo $?'
    if ($needsSetup -match "0") {
        Write-Host "[-] WSL Linux stack already configured." -ForegroundColor Gray
        return
    }

    Write-Host "[+] Running Linux setup inside $wslDistro (may take a while)..." -ForegroundColor Cyan
    wsl.exe -d $wslDistro -- bash -lc $wslSetupCmd
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[+] WSL Linux stack deployed." -ForegroundColor Green
    } else {
        Write-Host "[!] WSL setup failed (exit $LASTEXITCODE). Run manually in Ubuntu:" -ForegroundColor Yellow
        Write-Host "    $wslSetupCmd" -ForegroundColor Cyan
    }
}

$script:WslBroken = $false
if (Test-WslDistroInstalled $wslDistro) {
    Write-Host "[-] WSL $wslDistro is already installed." -ForegroundColor Gray
    Invoke-WslLinuxSetup
} else {
    if (-not (Test-WslHypervisorReady)) {
        [void](Set-HypervisorLaunchAuto)
    }
    if ($script:WslBroken) {
        [void](Invoke-WslMsiRepair $wslDistro)
    } elseif (-not (Test-WslVmPlatformReady)) {
        [void](Enable-WslWindowsFeatures)
    }

    if (-not (Test-WslVmPlatformReady)) {
        Write-WslRebootNeeded
    } else {
        # Canonical.Ubuntu can be "installed" in Winget while wsl -l is still empty.
        # wsl --install -d Ubuntu re-runs DISM and never registers the distro.
        Write-Host "[+] Installing $wslDistro via Winget..." -ForegroundColor Yellow
        winget install -e --id Canonical.Ubuntu --accept-package-agreements --accept-source-agreements --silent --source winget 2>&1 | Out-Host
        $repaired = (Test-WslDistroInstalled $wslDistro)
        if (-not $repaired) {
            $repaired = Install-UbuntuViaLauncher
        }
        if ($repaired) {
            Invoke-WslLinuxSetup
        } elseif (-not (Test-WslVmPlatformReady)) {
            Write-WslRebootNeeded
        } else {
            Write-Host "[!] Ubuntu did not register a WSL distro." -ForegroundColor Yellow
            Write-Host "    Do not Store-install Ubuntu. After vmcompute exists: re-run setup." -ForegroundColor Yellow
        }
    }
}

# --- 12. Browser extensions (manual: browsers block silent installs) ---
# ~\dotfiles\bootstrap\browser-extensions.ps1        # Chrome, Brave, Firefox, Edge
# ~\dotfiles\bootstrap\browser-extensions.ps1 -All   # every installed catalog browser

# --- 13. Final Polish ---
Set-WindowsHostDefaults
scoop cleanup *
Write-Host "SYSTEM IS MISSION READY." -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Sign into 1Password, then:" -ForegroundColor Yellow
Write-Host "     irm https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/post-setup.ps1 | iex" -ForegroundColor Cyan
Write-Host "  2. Bitbucket repo sync (after SSH agent ready):" -ForegroundColor Yellow
Write-Host "     `$s=`$env:TEMP\post-setup.ps1; irm https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/post-setup.ps1 -OutFile `$s; & `$s -SyncBitbucket" -ForegroundColor Cyan
Write-Host ""
Write-Host "Manual follow-ups:" -ForegroundColor Yellow
Write-Host "  - G-Helper: uninstall or quit Armoury Crate if both are installed"
Write-Host "  - DisplayLink: reboot, then re-run elevated if Winget still reports 1603"
Write-Host "  - Deskflow: needs VC++ 14.50+; setup upgrades Microsoft.VCRedist.2015+.x64 first"
Write-Host "  - LibreOffice: reboot if the MSI asked to finish install"
Write-Host "  - WSL: vmcompute is missing until VMP is reinstalled. Accept UAC (disable+enable), Restart, re-run. Do not Store-install Ubuntu."
Write-Host "  - Hibernate / long paths / Smart App Control Off: re-run an elevated PowerShell if those were skipped"
Write-Host "  - ThreeFingerDrag: log off once if three-finger still opens Task View"
Write-Host "  - Wavlink: install drivers for your model from https://www.wavlink.com/en_us/Drivers.html"
Write-Host "  - Antigravity / Goose / Cursor / Claude: sign in in each desktop app"
Write-Host "  - Ollama: pull a model (e.g. ollama pull llama3.2)"
Write-Host "  - Kubernetes: kind create cluster / k3d cluster create when Podman is running"
Write-Host "  - Java: jv temurin21-jdk"
Write-Host "  - Browser extensions (uBlock, 1Password, FDM): ~\dotfiles\bootstrap\browser-extensions.ps1"
