# Opens extension store pages in installed browsers. Browsers block silent installs;
# click Add on each tab. Mirrors bootstrap/browser-extensions.sh on macOS.
#
# Usage:
#   .\bootstrap\browser-extensions.ps1
#   .\bootstrap\browser-extensions.ps1 -All
#   .\bootstrap\browser-extensions.ps1 -Browsers "Google Chrome", "Firefox"

param(
    [switch]$All,
    [string[]]$Browsers = @()
)

$ErrorActionPreference = 'Continue'

$CwsUbol = "https://chromewebstore.google.com/detail/ddkjiahejlhfcafbddmgiahcphecmpfh"
$CwsUbo  = "https://chromewebstore.google.com/detail/cjpalhdlnbpafiamejdnhcphjbkeiagm"
$Cws1Pw  = "https://chromewebstore.google.com/detail/aeblfdkhhhdcdjpifhhbdiojplfjncoa"
$CwsFdm  = "https://chromewebstore.google.com/detail/ahmpjcflkgiildlgicmcieglgoilbfdp"
$AmoUbo  = "https://addons.mozilla.org/firefox/addon/ublock-origin/"
$Amo1Pw  = "https://addons.mozilla.org/firefox/addon/1password-x-password-manager/"
$AmoFdm  = "https://addons.mozilla.org/firefox/search/?q=Free%20Download%20Manager"

$Catalog = [ordered]@{
    "Google Chrome"              = @{ Engine = "chromium"; Paths = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe", "$env:LocalAppData\Google\Chrome\Application\chrome.exe") }
    "Microsoft Edge"             = @{ Engine = "chromium"; Paths = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") }
    "Brave Browser"              = @{ Engine = "brave";     Paths = @("$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe", "${env:ProgramFiles(x86)}\BraveSoftware\Brave-Browser\Application\brave.exe", "$env:LocalAppData\BraveSoftware\Brave-Browser\Application\brave.exe") }
    "Firefox"                    = @{ Engine = "firefox";   Paths = @("$env:ProgramFiles\Mozilla Firefox\firefox.exe", "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe", "$env:LocalAppData\Mozilla Firefox\firefox.exe") }
    "Firefox Developer Edition"  = @{ Engine = "firefox";   Paths = @("$env:ProgramFiles\Firefox Developer Edition\firefox.exe", "$env:LocalAppData\Firefox Developer Edition\firefox.exe") }
    "Vivaldi"                    = @{ Engine = "chromium"; Paths = @("$env:LocalAppData\Vivaldi\Application\vivaldi.exe") }
    "Opera GX"                   = @{ Engine = "chromium"; Paths = @("$env:LocalAppData\Programs\Opera GX\opera.exe", "$env:AppData\Opera Software\Opera GX\opera.exe") }
    "Floorp"                     = @{ Engine = "firefox";   Paths = @("$env:ProgramFiles\Ablaze Floorp\floorp.exe", "$env:ProgramFiles\Floorp\floorp.exe", "$env:LocalAppData\Ablaze Floorp\floorp.exe", "$env:LocalAppData\Floorp\floorp.exe") }
}

function Get-BrowserExe {
    param([string[]]$Paths)
    foreach ($p in $Paths) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    return $null
}

function Get-ExtensionUrls {
    param([string]$Engine)
    switch ($Engine) {
        "chromium" { return @($CwsUbol, $Cws1Pw, $CwsFdm) }
        "brave"    { return @($CwsUbo, $Cws1Pw, $CwsFdm) }
        "firefox"  { return @($AmoUbo, $Amo1Pw, $AmoFdm) }
        default    { return @() }
    }
}

function Open-InBrowser {
    param([string]$Exe, [string[]]$Urls)
    Start-Process -FilePath $Exe -ArgumentList $Urls
}

$DefaultNames = @("Google Chrome", "Brave Browser", "Firefox", "Microsoft Edge")
if ($All) {
    $targetNames = @($Catalog.Keys)
} elseif ($Browsers.Count -gt 0) {
    $targetNames = $Browsers
} else {
    $targetNames = $DefaultNames
}

$opened = 0
foreach ($name in $targetNames) {
    if (-not $Catalog.Contains($name)) {
        Write-Host "-- skip '$name' (not a supported browser name)" -ForegroundColor DarkGray
        continue
    }
    $meta = $Catalog[$name]
    $exe = Get-BrowserExe $meta.Paths
    if (-not $exe) {
        Write-Host "-- skip '$name' (not installed)" -ForegroundColor DarkGray
        continue
    }
    $urls = Get-ExtensionUrls $meta.Engine
    Write-Host "==> $name`: opening $($urls.Count) extension pages (click Add on each)" -ForegroundColor Cyan
    try {
        Open-InBrowser -Exe $exe -Urls $urls
        $opened++
    } catch {
        Write-Host "    could not open $name`: $_" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Done. Opened pages in $opened browser(s)." -ForegroundColor Green
Write-Host "Notes:"
Write-Host "  - Chrome/Edge/Vivaldi/Opera use uBlock Origin Lite (full uBO no longer works on Chrome)."
Write-Host "  - 1Password and FDM extensions need their desktop apps installed to function."
