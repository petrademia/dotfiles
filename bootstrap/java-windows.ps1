# Windows Java matrix via Scoop - mirrors the macOS java-macos.sh vendor/version set.

if (!(Get-Command scoop -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Scoop..." -ForegroundColor Yellow
    irm get.scoop.sh | iex
}

$currentBuckets = scoop bucket list
foreach ($b in @("java", "versions")) {
    if (!($currentBuckets -like "*$b*")) { scoop bucket add $b }
}

$installedList = scoop export

$majors = @("8", "11", "17", "21", "25")
foreach ($v in $majors) {
    $pkgs = @("temurin$v-jdk", "corretto$v-jdk", "zulu$v-jdk", "liberica$v-jdk")
    foreach ($p in $pkgs) {
        if (!($installedList -like "*$p*")) {
            Write-Host "==> Installing $p" -ForegroundColor Cyan
            & scoop install $p 2>$null
        }
    }
    # Microsoft Build of OpenJDK has no Java 8
    if ($v -ne "8") {
        $msName = if ($v -eq "25") { "microsoft-jdk" } else { "microsoft$v-jdk" }
        if (!($installedList -like "*$msName*")) {
            Write-Host "==> Installing $msName" -ForegroundColor Cyan
            & scoop install $msName 2>$null
        }
    }
}

Write-Host "Switch JDKs with: jv <name>   (e.g. jv temurin21-jdk)" -ForegroundColor Green
