# Windows Java matrix via Scoop - mirrors java-macos.sh / java-wsl.sh
# Usage: irm https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/java-windows.ps1 | iex

$ErrorActionPreference = 'Continue'

if (!(Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Scoop..." -ForegroundColor Yellow
    irm get.scoop.sh | iex
}

foreach ($b in @('java', 'versions')) {
    scoop bucket add $b 6>$null | Out-Null
}

function Test-ScoopApp([string]$Name) {
    $null -ne (scoop list $Name 6>$null | Select-String -SimpleMatch $Name -Quiet)
}

# Temurin/Zulu/Corretto/Liberica: 8/11/17/21/25. Microsoft: 11/17/21 + unversioned microsoft-jdk (Scoop's 25+ slot).
$packages = @(
    'temurin8-jdk', 'corretto8-jdk', 'zulu8-jdk', 'liberica8-jdk',
    'temurin11-jdk', 'corretto11-jdk', 'zulu11-jdk', 'liberica11-jdk', 'microsoft11-jdk',
    'temurin17-jdk', 'corretto17-jdk', 'zulu17-jdk', 'liberica17-jdk', 'microsoft17-jdk',
    'temurin21-jdk', 'corretto21-jdk', 'zulu21-jdk', 'liberica21-jdk', 'microsoft21-jdk',
    'temurin25-jdk', 'corretto25-jdk', 'zulu25-jdk', 'liberica25-jdk', 'microsoft-jdk'
)

$ok = 0; $skip = 0; $fail = 0
foreach ($p in $packages) {
    if (Test-ScoopApp $p) {
        Write-Host "==> skip $p (already installed)" -ForegroundColor DarkGray
        $skip++
        continue
    }
    Write-Host "==> Installing $p" -ForegroundColor Cyan
    scoop install $p
    if ($LASTEXITCODE -eq 0 -or (Test-ScoopApp $p)) {
        $ok++
    } else {
        Write-Host "==> FAILED $p" -ForegroundColor Red
        $fail++
    }
}

Write-Host ""
Write-Host "Done. installed=$ok skipped=$skip failed=$fail" -ForegroundColor Green
Write-Host "Switch JDKs:  jv <name>   (e.g. jv temurin21-jdk)"
Write-Host "Optional:    scoop config aria2-warning-enabled false   # quiet aria2 WARN lines"
