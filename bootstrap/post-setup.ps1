# Post-install auth and work setup. Requires 1Password CLI (op) to be signed in.
#
# Usage:
#   irm https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/post-setup.ps1 | iex
#   .\bootstrap\post-setup.ps1 -SkipAuth

param(
    [switch]$SkipAuth
)

$ErrorActionPreference = 'Continue'

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

function Invoke-OpReadFirst {
    param([string[]]$Refs)
    foreach ($ref in $Refs) {
        $val = Invoke-OpRead $ref
        if ($val) { return $val }
    }
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

    $token = Invoke-OpReadFirst @(
        "op://Personal/GitHub CLI Token/credential",
        "op://Personal/GitHub CLI Token/password",
        "op://Personal/GitHub CLI Token/token",
        "op://Personal/GitHub/credential",
        "op://Personal/GitHub/password",
        "op://Personal/GitHub PAT/credential"
    )
    if (-not $token) {
        Write-Host "[!] No GitHub token in 1Password (GitHub CLI Token item). Git push still works via SSH Key." -ForegroundColor Yellow
        return
    }

    $token | gh auth login --with-token 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[+] gh authenticated from 1Password." -ForegroundColor Green
    } else {
        Write-Host "[!] gh auth login --with-token failed." -ForegroundColor Yellow
    }
}

function Show-ManualChecklist {
    Write-Host ""
    Write-Host "Manual follow-ups:" -ForegroundColor Yellow
    Write-Host "  - Desktop apps: sign into Cursor, Claude, ChatGPT, Antigravity, Goose"
    Write-Host "  - DisplayLink: reboot after driver install if you use a dock"
    Write-Host "  - Wavlink: install model-specific drivers from https://www.wavlink.com/en_us/Drivers.html"
    Write-Host "  - Obsidian / notes: configure sync separately"
    Write-Host "  - Ollama: pull a model (e.g. ollama pull llama3.2)"
    Write-Host "  - Kubernetes: kind create cluster / k3d cluster create when Podman is running"
    Write-Host "  - Java: jv temurin21-jdk  (windows.ps1 installs the full matrix)"
}

Write-Host "==> Post-setup" -ForegroundColor Cyan

if (-not $SkipAuth) {
    if (Test-OpReady) {
        Ensure-GhAuth
    }
} else {
    Write-Host "[-] Skipping auth (-SkipAuth)." -ForegroundColor Gray
}

Show-ManualChecklist
