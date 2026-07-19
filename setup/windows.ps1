# Windows setup - mirrors the macOS/WSL tool stack via Scoop + Winget.

# --- 0. Pre-Flight & Self-Update ---
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
if (!(Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-Host "📦 Installing Scoop..." -ForegroundColor Yellow
    irm get.scoop.sh | iex
}

Write-Host "🔄 Updating Scoop Manifests..." -ForegroundColor Cyan
scoop update

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
$buckets = @("extras", "versions", "nerd-fonts", "java")
$currentBuckets = scoop bucket list
foreach ($b in $buckets) {
    if (!($currentBuckets -like "*$b*")) { scoop bucket add $b }
}

$core = @("git", "7zip", "gh", "go", "rustup-msvc", "fastfetch", "aria2")
foreach ($app in $core) { Smart-Scoop $app }

# --- 3. Main App Block (CLI & Portable) ---
$apps = @(
    "1password-cli", "localsend", "wiztree", "dust", "fzf", "jq",
    "fnm", "gcc", "jetbrains-toolbox", "JetBrainsMono-NF", "llvm",
    "ninja", "podman", "podman-desktop", "sudo", "uv", "gdb", "cheat-engine",
    "syncthing",
    "xmake", "cmake", "ripgrep", "neovim", "graphviz", "zstd", "ngrok",
    "gradle", "maven", "plantuml", "z3", "sqlite"
)
foreach ($app in $apps) { Smart-Scoop $app }

if (Get-Command rustup -ErrorAction SilentlyContinue) {
    rustup default stable | Out-Null
    $env:PATH = "$HOME\.cargo\bin;$env:PATH"
    $atlassianCli = Join-Path $HOME ".cargo\bin\atlassian-cli.exe"
    if (!(Get-Command atlassian-cli -ErrorAction SilentlyContinue) -and !(Test-Path $atlassianCli)) {
        cargo install atlassian-cli
    }
}

if (Get-Command uv -ErrorAction SilentlyContinue) {
    uv python install 3 --default
}

# --- 4. Default JDK (full matrix lives in bootstrap/java-windows.ps1) ---
Write-Host "☕ Installing default JDK (Temurin 21)..." -ForegroundColor Cyan
if (!(scoop bucket list | Select-String "java")) { scoop bucket add java }
Smart-Scoop "temurin21-jdk"

# --- 5. Winget Apps (2026 Verified IDs) ---
Write-Host "📦 Checking Winget Apps..." -ForegroundColor Cyan

$wingetApps = @(
    "AgileBits.1Password", "Surfshark.Surfshark", "Anysphere.Cursor",
    "Anthropic.Claude", "MoonshotAI.Kimi", "Microsoft.PowerToys",
    "Ollama.Ollama", "ElementLabs.LMStudio", "ggml.llamacpp",
    "Google.Chrome", "Google.GoogleDrive", "Microsoft.OneDrive",
    "Microsoft.VisualStudioCode", "Zen-Team.Zen-Browser",
    "Mozilla.Firefox.DeveloperEdition", "Vivaldi.Vivaldi", "Brave.Brave",
    "Opera.OperaGX", "Ablaze.Floorp",
    "Deskflow.Deskflow", "SlackTechnologies.Slack", "Discord.Discord",
    "UpNote.UpNote",
    "Streetwriters.Notesnook",
    "StandardNotes.StandardNotes", "Automattic.Simplenote"
)

foreach ($app in $wingetApps) {
    $check = winget list --id $app --source winget 2>$null
    if ($null -eq $check -or $check -match "No installed package found") {
        Write-Host "[+] Installing $app..." -ForegroundColor Cyan
        winget install -e --id $app --accept-package-agreements --accept-source-agreements --silent --source winget

        if ($LASTEXITCODE -ne 0) {
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
Sync-Dotfile (Join-Path $dotfiles "claude\RTK.md") (Join-Path $HOME ".claude\RTK.md")
Sync-Dotfile (Join-Path $dotfiles "config\nvim") (Join-Path $env:LOCALAPPDATA "nvim")
Sync-Dotfile (Join-Path $dotfiles "cursor\cli-config.json") (Join-Path $HOME ".cursor\cli-config.json")

foreach ($command in @("grammar", "leetcode")) {
    Sync-Dotfile (Join-Path $dotfiles "ai\commands\$command.md") (Join-Path $HOME ".cursor\commands\$command.md")
    Sync-Dotfile (Join-Path $dotfiles "ai\commands\$command.md") (Join-Path $HOME ".claude\commands\$command.md")
    Sync-Dotfile (Join-Path $dotfiles "ai\commands\$command.md") (Join-Path $HOME ".zai\commands\$command.md")
    Sync-Dotfile (Join-Path $dotfiles "ai\gemini\$command.toml") (Join-Path $HOME ".gemini\commands\$command.toml")
    Sync-Dotfile (Join-Path $dotfiles "ai\codex\$command") (Join-Path $HOME ".agents\skills\$command")
    Sync-Dotfile (Join-Path $dotfiles "ai\codex\$command") (Join-Path $HOME ".codex\skills\$command")
}

$goEnv = go env GOENV
if ($goEnv) { Sync-Dotfile (Join-Path $dotfiles "go\env") $goEnv }

git config --global include.path (Join-Path $dotfiles "git\gitconfig")
git config --global core.hooksPath (Join-Path $dotfiles "git\hooks")

# --- 7. Deskflow Firewall Rule ---
Write-Host "🌐 Opening Port 24800 for Deskflow..." -ForegroundColor Cyan
$dfRule = "Deskflow Inbound (TCP 24800)"
if (!(Get-NetFirewallRule -DisplayName $dfRule -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $dfRule -Direction Inbound -LocalPort 24800 -Protocol TCP -Action Allow -Description "Deskflow KVM"
}

# --- 8. Window Switcher (sigoden/window-switcher) ---
Write-Host "🪟 Checking Alt-Backtick Switcher (sigoden)..." -ForegroundColor Cyan

if (!(Get-Command window-switcher -ErrorAction SilentlyContinue)) {
    Write-Host "[+] Installing window-switcher via Scoop..." -ForegroundColor Yellow
    if (!(scoop bucket list | Select-String "extras")) { scoop bucket add extras }
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

# --- 10. AI Agent Initializations ---
Write-Host "🤖 Checking AI Agents..." -ForegroundColor Yellow

if (!(Get-Command claude -ErrorAction SilentlyContinue)) { irm https://claude.ai/install.ps1 | iex }

if (Get-Command fnm -ErrorAction SilentlyContinue) {
    fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression
    fnm use --install-if-missing lts-latest
    fnm default lts-latest
}

if (Get-Command npm -ErrorAction SilentlyContinue) {
    Write-Host "📦 Installing Node-based AI Agents..." -ForegroundColor Cyan
    npm install -g @openai/codex @z_ai/coding-helper opencode-ai @github/copilot playwright --silent
    npx playwright install chromium
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
    claude plugin marketplace add https://github.com/JuliusBrussee/caveman 2>$null
    claude plugin marketplace add https://github.com/DietrichGebert/ponytail 2>$null
    claude plugin install caveman 2>$null
    claude plugin install ponytail 2>$null
}
if (Get-Command codex -ErrorAction SilentlyContinue) {
    Write-Host "🧩 Installing Codex plugins..." -ForegroundColor Cyan
    codex plugin marketplace add JuliusBrussee/caveman 2>$null
    codex plugin marketplace add DietrichGebert/ponytail 2>$null
    codex plugin add caveman@caveman 2>$null
    codex plugin add ponytail@ponytail 2>$null
}

# --- 10c. RTK (Rust Token Killer) ---
if (!(Get-Command rtk -ErrorAction SilentlyContinue)) {
    Write-Host "⚡ Installing RTK..." -ForegroundColor Cyan
    try {
        $rel = Invoke-RestMethod "https://api.github.com/repos/rtk-ai/rtk/releases/latest"
        $tag = $rel.tag_name
        $rtkUrl = "https://github.com/rtk-ai/rtk/releases/download/$tag/rtk-x86_64-pc-windows-msvc.zip"
        $binDir = "$HOME\.local\bin"
        New-Item -Type Directory -Path $binDir -Force | Out-Null
        $tmp = "$env:TEMP\rtk.zip"
        Invoke-WebRequest $rtkUrl -OutFile $tmp
        Expand-Archive $tmp -DestinationPath $binDir -Force
        Remove-Item $tmp -ErrorAction SilentlyContinue
        Write-Host "RTK installed to $binDir" -ForegroundColor Green
    } catch {
        Write-Host "[!] RTK auto-install failed - grab it from https://github.com/rtk-ai/rtk/releases" -ForegroundColor Yellow
    }
}

# --- 11. Final Polish ---
scoop cleanup *
Write-Host "🎯 SYSTEM IS MISSION READY." -ForegroundColor Green
