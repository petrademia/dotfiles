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
    Write-Host "📦 Installing Scoop..." -ForegroundColor Yellow
    irm get.scoop.sh | iex
    Update-SessionPath
}

# Git is required before scoop update / bucket add.
if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "📦 Installing git (required for Scoop buckets)..." -ForegroundColor Cyan
    scoop install git
    Update-SessionPath
}
Install-GitHubKnownHosts

Write-Host "🔄 Updating Scoop Manifests..." -ForegroundColor Cyan
Protect-ScoopGit { scoop update | Out-Host }

# --- 1. Intelligence Layer: Scoop Check Function ---
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
    "kubectl", "kind", "k3d"
)
foreach ($app in $apps) { Smart-Scoop $app }

if (Get-Command rustup -ErrorAction SilentlyContinue) {
    rustup default stable | Out-Null
    $env:PATH = "$HOME\.cargo\bin;$env:PATH"
    $atlassianCli = Join-Path $HOME ".cargo\bin\atlassian-cli.exe"
    if (!(Get-Command atlassian-cli -ErrorAction SilentlyContinue) -and !(Test-Path $atlassianCli)) {
        if (Get-Command link.exe -ErrorAction SilentlyContinue) {
            cargo install atlassian-cli
        } else {
            Write-Host "[!] Skipping atlassian-cli: MSVC linker (link.exe) not found. Install Visual Studio Build Tools (MSVC + Windows SDK), then re-run." -ForegroundColor Yellow
        }
    }
}

if (Get-Command uv -ErrorAction SilentlyContinue) {
    uv python install 3 --default
}

# --- 4. Java matrix (same packages as bootstrap/java-windows.ps1) ---
Write-Host "☕ Installing Java matrix..." -ForegroundColor Cyan
$javaLocal = @(
    $(if ($PSScriptRoot) { Join-Path $PSScriptRoot "..\bootstrap\java-windows.ps1" }),
    (Join-Path $HOME "dotfiles\bootstrap\java-windows.ps1")
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if ($javaLocal) {
    Protect-ScoopGit { param($p) & $p } -Arg $javaLocal
} else {
    Protect-ScoopGit { irm "https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/java-windows.ps1" | iex }
}

# --- 5. Winget Apps (2026 Verified IDs) ---
Write-Host "📦 Checking Winget Apps..." -ForegroundColor Cyan

$wingetApps = @(
    "Microsoft.VCRedist.2015+.x64",
    "AgileBits.1Password", "Surfshark.Surfshark", "Anysphere.Cursor",
    "Anthropic.Claude", "MoonshotAI.Kimi", "Microsoft.PowerToys",
    "Ollama.Ollama", "ElementLabs.LMStudio", "ggml.llamacpp",
    "Google.Chrome", "Google.GoogleDrive", "Microsoft.OneDrive",
    "Google.Antigravity", "Google.AntigravityCLI",
    "Microsoft.VisualStudioCode", "Zen-Team.Zen-Browser",
    "Mozilla.Firefox.DeveloperEdition", "Vivaldi.Vivaldi", "Brave.Brave",
    "Opera.OperaGX", "Ablaze.Floorp",
    "Deskflow.Deskflow", "SlackTechnologies.Slack", "Discord.Discord",
    "UpNote.UpNote",
    "Streetwriters.Notesnook",
    "StandardNotes.StandardNotes", "Automattic.Simplenote",
    "Joplin.Joplin", "Obsidian.Obsidian",
    "DisplayLink.GraphicsDriver",
    "seerge.g-helper",
    "erez-c137.NetSpeedTray", "zhongyang219.TrafficMonitor.Lite"
)

foreach ($app in $wingetApps) {
    $check = winget list --id $app --source winget 2>$null
    if ($null -eq $check -or $check -match "No installed package found") {
        Write-Host "[+] Installing $app..." -ForegroundColor Cyan
        winget install -e --id $app --accept-package-agreements --accept-source-agreements --silent --source winget

        if ($LASTEXITCODE -eq 1603) {
            Write-Host "[!] $app installer needs elevation or a reboot (exit 1603). Skipping retry." -ForegroundColor Yellow
        } elseif ($LASTEXITCODE -ne 0) {
            Write-Host "[!] Exact ID failed for $app. Attempting search-install..." -ForegroundColor Yellow
            winget install $app --accept-package-agreements --accept-source-agreements --silent
        }
    } else {
        Write-Host "[-] $app is already installed." -ForegroundColor Gray
    }
}

# --- 5b. OpenAI Desktop Apps (Microsoft Store) ---
# 9PLM9XGG6VKS = new unified ChatGPT/Codex app (Chat+Work+Codex); 9NT1R1C2HH7J = ChatGPT Classic
Write-Host "💬 Checking OpenAI desktop apps..." -ForegroundColor Cyan
$msStoreApps = [ordered]@{
    "9PLM9XGG6VKS" = "ChatGPT (unified Codex app)"
    "9NT1R1C2HH7J" = "ChatGPT Classic"
}
foreach ($id in $msStoreApps.Keys) {
    $name = $msStoreApps[$id]
    $check = winget list --id $id --source msstore 2>$null
    if ($null -eq $check -or $check -match "No installed package found") {
        Write-Host "[+] Installing $name..." -ForegroundColor Cyan
        winget install --id $id --source msstore --accept-package-agreements --accept-source-agreements --silent
    } else {
        Write-Host "[-] $name is already installed." -ForegroundColor Gray
    }
}

# --- 6. Go Environment (GoLand GOROOT Fix) ---
Write-Host "🐹 Configuring Go Paths..." -ForegroundColor Cyan
$goRootPath = "$env:USERPROFILE\scoop\apps\go\current"
[System.Environment]::SetEnvironmentVariable("GOROOT", $goRootPath, "User")
[System.Environment]::SetEnvironmentVariable("GOPATH", "$env:USERPROFILE\go", "User")
$env:GOROOT = $goRootPath
$env:GOPATH = "$env:USERPROFILE\go"
$env:PATH = "$goRootPath\bin;$env:GOPATH\bin;$env:PATH"

# --- 6b. Shared Dotfiles ---
$dotfiles = Join-Path $HOME "dotfiles"
if (!(Test-Path (Join-Path $dotfiles ".git"))) {
    Write-Host "📁 Cloning dotfiles..." -ForegroundColor Cyan
    git clone https://github.com/petrademia/dotfiles.git $dotfiles
}

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
Write-Host "🌐 Opening Port 24800 for Deskflow..." -ForegroundColor Cyan
$dfRule = "Deskflow Inbound (TCP 24800)"
try {
    if (!(Get-NetFirewallRule -DisplayName $dfRule -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $dfRule -Direction Inbound -LocalPort 24800 -Protocol TCP -Action Allow -Description "Deskflow KVM" | Out-Null
    }
} catch {
    Write-Host "[!] Deskflow firewall rule skipped (needs an elevated PowerShell)." -ForegroundColor Yellow
}

# --- 8. Window Switcher (sigoden/window-switcher) ---
Write-Host "🪟 Checking Alt-Backtick Switcher (sigoden)..." -ForegroundColor Cyan

if (!(Get-Command window-switcher -ErrorAction SilentlyContinue)) {
    Write-Host "[+] Installing window-switcher via Scoop..." -ForegroundColor Yellow
    Add-ScoopBucket extras
    scoop install window-switcher
}

$wsExe = Get-ChildItem -Path "$env:USERPROFILE\scoop\apps\window-switcher" -Recurse -Filter "window-switcher.exe" | Select-Object -ExpandProperty FullName -First 1

if ($wsExe) {
    if (!(Get-Process window-switcher -ErrorAction SilentlyContinue)) {
        Start-Process $wsExe -WindowStyle Hidden
        Write-Host "🚀 Window-Switcher (sigoden) started." -ForegroundColor Green
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
    Write-Host "🔑 AI Keys Loaded from 1Password." -ForegroundColor Green
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
Write-Host "🤖 Checking AI Agents..." -ForegroundColor Yellow

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
    Write-Host "📦 Installing Node-based AI Agents..." -ForegroundColor Cyan
    npm install -g --ignore-scripts @earendil-works/pi-coding-agent --silent
    npm install -g reasonix --silent
    npm install -g @deepseek-ai/dsh --silent
    npm install -g wrangler --silent
    npm install -g @openai/codex @z_ai/coding-helper opencode-ai @github/copilot openclaw@latest impeccable playwright --silent
    npx playwright install chromium
    cmd /c "echo Y| npx --yes impeccable install --scope=global --providers=claude,codex,cursor,gemini,opencode,pi --force"
}

if (!(Get-Command omp -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Oh My Pi (omp)..." -ForegroundColor Cyan
    irm https://omp.sh/install.ps1 | iex
}

# Goose CLI (native Windows) + Desktop (no winget ID; zip from GitHub stable)
if (!(Get-Command goose -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Goose CLI..." -ForegroundColor Cyan
    $gooseInstaller = Join-Path $env:TEMP "goose-download_cli.ps1"
    try {
        Invoke-WebRequest "https://github.com/aaif-goose/goose/releases/download/stable/download_cli.ps1" -OutFile $gooseInstaller
        $env:CONFIGURE = "false"
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $gooseInstaller
    } catch {
        Write-Host "[!] Goose CLI via Invoke-WebRequest failed, retrying with curl..." -ForegroundColor Yellow
        try {
            & curl.exe -fsSL "https://github.com/aaif-goose/goose/releases/download/stable/download_cli.ps1" -o $gooseInstaller
            $env:CONFIGURE = "false"
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $gooseInstaller
        } catch {
            Write-Host "[!] Goose CLI install failed: $_" -ForegroundColor Yellow
        }
    } finally {
        Remove-Item $gooseInstaller -ErrorAction SilentlyContinue
        Remove-Item Env:CONFIGURE -ErrorAction SilentlyContinue
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

if (Get-Command gh -ErrorAction SilentlyContinue) {
    gh extension install github/gh-copilot --force
}

# --- 10b. Claude Code & Codex plugins (caveman, ponytail) ---
if (Get-Command claude -ErrorAction SilentlyContinue) {
    Write-Host "🧩 Installing Claude Code plugins..." -ForegroundColor Cyan
    Protect-ScoopGit {
        claude plugin marketplace add https://github.com/JuliusBrussee/caveman 2>$null
        claude plugin marketplace add https://github.com/DietrichGebert/ponytail 2>$null
        claude plugin install caveman 2>$null
        claude plugin install ponytail 2>$null
    }
}
if (Get-Command codex -ErrorAction SilentlyContinue) {
    Write-Host "🧩 Installing Codex plugins..." -ForegroundColor Cyan
    Protect-ScoopGit {
        codex plugin marketplace add JuliusBrussee/caveman 2>$null
        codex plugin marketplace add DietrichGebert/ponytail 2>$null
        codex plugin add caveman@caveman 2>$null
        codex plugin add ponytail@ponytail 2>$null
    }
}

# --- 11. WSL host provisioning ---
Write-Host "🐧 Checking WSL..." -ForegroundColor Cyan

$wslDistro = "Ubuntu"
$wslSetupCmd = "curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/setup.sh | bash"

function Test-WslDistroInstalled {
    param([string]$Name)
    if (!(Get-Command wsl.exe -ErrorAction SilentlyContinue)) { return $false }
    $raw = & wsl.exe -l -v 2>&1 | Out-String
    $raw = $raw -replace "`0", ""
    if ($raw -match "REGDB_E_CLASSNOTREG|corrupted") {
        $script:WslBroken = $true
        Write-Host "[!] WSL looks corrupted. Repair in an elevated PowerShell: wsl --update" -ForegroundColor Yellow
        Write-Host "    Then: wsl --install -d $Name" -ForegroundColor DarkGray
        return $false
    }
    if ($LASTEXITCODE -ne 0) { return $false }
    return ($raw -match [regex]::Escape($Name))
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
} elseif ($script:WslBroken) {
    Write-Host "[-] Skipping wsl --install until WSL is repaired." -ForegroundColor Yellow
} else {
    Write-Host "[+] Installing WSL + $wslDistro (elevation may be required)..." -ForegroundColor Yellow
    Write-Host "    After reboot, re-run this script or open Ubuntu and run:" -ForegroundColor Yellow
    Write-Host "    $wslSetupCmd" -ForegroundColor Cyan

    wsl.exe --install -d $wslDistro --no-launch 2>&1 | ForEach-Object { Write-Host $_ }

    if ($LASTEXITCODE -ne 0) {
        Write-Host "[!] wsl --install failed (exit $LASTEXITCODE). Run elevated PowerShell:" -ForegroundColor Yellow
        Write-Host "    wsl --install -d $wslDistro" -ForegroundColor Cyan
    } else {
        Write-Host "[+] WSL install initiated. Reboot if prompted, then re-run setup or the curl command above." -ForegroundColor Green
    }
}

# --- 12. Browser extension store pages ---
$extScript = Join-Path $dotfiles "bootstrap\browser-extensions.ps1"
if (Test-Path $extScript) {
    Write-Host "🧩 Opening browser extension store pages..." -ForegroundColor Cyan
    & $extScript
}

# --- 13. Final Polish ---
scoop cleanup *
Write-Host "🎯 SYSTEM IS MISSION READY." -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Sign into 1Password, then:" -ForegroundColor Yellow
Write-Host "     irm https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/post-setup.ps1 | iex" -ForegroundColor Cyan
Write-Host "  2. Bitbucket repo sync (after SSH agent ready):" -ForegroundColor Yellow
Write-Host "     `$s=`$env:TEMP\post-setup.ps1; irm https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/post-setup.ps1 -OutFile `$s; & `$s -SyncBitbucket" -ForegroundColor Cyan
Write-Host ""
Write-Host "Manual follow-ups:" -ForegroundColor Yellow
Write-Host "  - TrafficMonitor: right-click → Show taskbar window (first run)"
Write-Host "  - G-Helper: uninstall or quit Armoury Crate if both are installed"
Write-Host "  - DisplayLink / Deskflow: reboot, then re-run elevated if Winget still reports 1603"
Write-Host "  - WSL: if REGDB_E_CLASSNOTREG, elevated: wsl --update ; wsl --install -d Ubuntu"
Write-Host "  - atlassian-cli: Visual Studio Build Tools (MSVC + Windows SDK), then cargo install atlassian-cli"
Write-Host "  - Wavlink: install drivers for your model from https://www.wavlink.com/en_us/Drivers.html"
Write-Host "  - Antigravity / Goose / Cursor / Claude: sign in in each desktop app"
Write-Host "  - Ollama: pull a model (e.g. ollama pull llama3.2)"
Write-Host "  - Kubernetes: kind create cluster / k3d cluster create when Podman is running"
Write-Host "  - Java: jv temurin21-jdk  (re-run bootstrap/java-windows.ps1 to fill gaps)"
