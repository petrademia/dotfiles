# Post-install auth and work setup. Requires 1Password CLI (op) to be signed in.
#
# Usage:
#   irm https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/post-setup.ps1 | iex
#   .\bootstrap\post-setup.ps1 -SyncBitbucket

param(
    [switch]$SyncBitbucket,
    [switch]$SkipAuth
)

$ErrorActionPreference = 'Continue'

$Dotfiles = Join-Path $HOME "dotfiles"
if (!(Test-Path (Join-Path $Dotfiles ".git"))) {
    $Dotfiles = $null
}

function Test-OpReady {
    if (!(Get-Command op -ErrorAction SilentlyContinue)) {
        Write-Host "[!] 1Password CLI (op) not found. Install/sign in first." -ForegroundColor Yellow
        return $false
    }
    op account get 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[!] 1Password not signed in. Open 1Password and run: op signin" -ForegroundColor Yellow
        return $false
    }
    return $true
}

function Invoke-OpRead {
    param([string]$Ref)
    try {
        $val = op read $Ref 2>$null
        if ($LASTEXITCODE -eq 0 -and $val) { return $val.Trim() }
    } catch {}
    return $null
}

function Ensure-GhAuth {
    if (!(Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Host "[-] gh not installed; skipping GitHub auth." -ForegroundColor DarkGray
        return
    }
    gh auth status 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[-] gh already authenticated." -ForegroundColor Gray
        return
    }

    $token = Invoke-OpRead "op://Personal/GitHub/credential"
    if (-not $token) {
        $token = Invoke-OpRead "op://Personal/GitHub PAT/credential"
    }
    if (-not $token) {
        Write-Host "[!] No GitHub token in 1Password (op://Personal/GitHub/credential). Run: gh auth login" -ForegroundColor Yellow
        return
    }

    $token | gh auth login --with-token 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[+] gh authenticated from 1Password." -ForegroundColor Green
    } else {
        Write-Host "[!] gh auth login --with-token failed." -ForegroundColor Yellow
    }
}

function Ensure-AtlassianAuth {
    if (!(Get-Command atlassian-cli -ErrorAction SilentlyContinue)) {
        Write-Host "[-] atlassian-cli not installed; skipping Atlassian auth." -ForegroundColor DarkGray
        return
    }

    atlassian-cli auth test --profile amartha --bitbucket 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[-] atlassian-cli profile 'amartha' already works." -ForegroundColor Gray
        return
    }

    $token = Invoke-OpRead "op://Personal/Amartha Bitbucket PR Review/credential"
    if (-not $token) {
        Write-Host "[!] Could not read op://Personal/Amartha Bitbucket PR Review/credential" -ForegroundColor Yellow
        return
    }

    atlassian-cli auth login --profile amartha --bitbucket --bearer --token $token --workspace Amartha 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[+] atlassian-cli Bitbucket profile 'amartha' configured." -ForegroundColor Green
    } else {
        Write-Host "[!] atlassian-cli auth login failed." -ForegroundColor Yellow
    }
}

function Invoke-BitbucketSync {
    $scriptUrl = "https://raw.githubusercontent.com/petrademia/dotfiles/main/scripts/sync-bitbucket-repos.sh"
    $localScript = if ($Dotfiles) { Join-Path $Dotfiles "scripts\sync-bitbucket-repos.sh" } else { $null }

    if ((Get-Command wsl.exe -ErrorAction SilentlyContinue) -and (wsl.exe -l -v 2>$null) -match "Ubuntu") {
        Write-Host "[+] Syncing Bitbucket repos via WSL..." -ForegroundColor Cyan
        if ($localScript -and (Test-Path $localScript)) {
            $wslPath = wsl.exe wslpath -a $localScript 2>$null
            if ($wslPath) {
                wsl.exe -d Ubuntu -- bash $wslPath
                return
            }
        }
        wsl.exe -d Ubuntu -- bash -lc "curl -fsSL $scriptUrl | bash"
        return
    }

    $bash = Get-Command bash -ErrorAction SilentlyContinue
    if ($bash -and $localScript -and (Test-Path $localScript)) {
        Write-Host "[+] Syncing Bitbucket repos via Git Bash..." -ForegroundColor Cyan
        & $bash.Source $localScript
        return
    }

    Write-Host "[!] Bitbucket sync needs WSL Ubuntu or Git Bash + local dotfiles clone." -ForegroundColor Yellow
    Write-Host "    curl -fsSL $scriptUrl | bash" -ForegroundColor Cyan
}

function Show-ManualChecklist {
    Write-Host ""
    Write-Host "Manual follow-ups:" -ForegroundColor Yellow
    Write-Host "  - 1Password: unlock vault; enable SSH agent for Bitbucket git push (petruswiyadi-Bitbucket)"
    Write-Host "  - Desktop apps: sign into Cursor, Claude, ChatGPT, Antigravity, Goose"
    Write-Host "  - DisplayLink: reboot after driver install if you use a dock"
    Write-Host "  - Wavlink: install model-specific drivers from https://www.wavlink.com/en_us/Drivers.html"
    Write-Host "  - Obsidian / notes: configure sync separately"
    Write-Host "  - Ollama: pull a model (e.g. ollama pull llama3.2)"
    Write-Host "  - Kubernetes: kind create cluster / k3d cluster create when Podman is running"
    Write-Host "  - Java: jv temurin21-jdk  (windows.ps1 installs the full matrix)"
    if ($Dotfiles) {
        Write-Host "  - Browser extensions: $($Dotfiles)\bootstrap\browser-extensions.ps1"
    }
}

Write-Host "==> Post-setup" -ForegroundColor Cyan

if (-not $SkipAuth) {
    if (Test-OpReady) {
        Ensure-GhAuth
        Ensure-AtlassianAuth
    }
} else {
    Write-Host "[-] Skipping auth (-SkipAuth)." -ForegroundColor Gray
}

if ($SyncBitbucket) {
    if (Test-OpReady) {
        Invoke-BitbucketSync
    } else {
        Write-Host "[!] Bitbucket sync requires signed-in op." -ForegroundColor Yellow
    }
}

Show-ManualChecklist
Write-Host ""
Write-Host "Re-run with -SyncBitbucket after SSH agent is ready for git clone." -ForegroundColor DarkGray
