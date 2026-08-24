# Dotfiles

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/setup.sh -o setup.sh && bash setup.sh
```

Windows:

```powershell
irm https://raw.githubusercontent.com/petrademia/dotfiles/main/setup/windows.ps1 | iex
```

The script sets CurrentUser `RemoteSigned` (Windows defaults to Restricted, which prints `running scripts is disabled` when the profile loads). If `irm | iex` itself is blocked, run `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force` first.

It enables Virtual Machine Platform (UAC DISM) when `vmcompute` is missing, installs Ubuntu with Winget `Canonical.Ubuntu`, then `ubuntu.exe install --root`. Do not install Ubuntu from the Store. If `wsl` reports `REGDB_E_CLASSNOTREG`, the script downloads the official `wsl.msi` from GitHub and prompts for UAC. Then inside Ubuntu:

```bash
curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/setup.sh | bash
```

Or from a clone: `./setup.sh` (full) / `./install.sh` (symlinks only; Windows copies files instead).

## macOS defaults

```bash
curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/macos.sh | zsh
```

## Windows defaults

`setup/windows.ps1` applies a small host set (same role as `bootstrap/macos.sh`): show file extensions and hidden files, `~/Screenshots`, faster key repeat, tap-to-click, disable Windows three-finger swipe/tap so ThreeFingerDrag can own the gesture, hibernate plus Hibernate in the power menu, NTFS long paths, Alt+Tab as windows only (no Edge tabs), hide taskbar Search / Task view / Widgets / Chat / Copilot / Resume, unpin default taskbar apps (Edge, Store, File Explorer, Copilot, Mail, Teams, Xbox), Windows Security SmartScreen / PUA on and Smart App Control off, and trim startup apps. Startup keeps 1Password, TrafficMonitor, window-switcher, ThreeFingerDrag, Surfshark, Google Drive, OneDrive, Everything, FDM (hidden), DisplayLink tray, and Windows Security. Startup disables browser helpers (Opera / GX / Air, Brave update), Steam, UniGetUI, Discord, Slack, WhatsApp, Warp, OpenVPN Connect, Ollama, Spotify, Virtual Pet, ASUS Smart Display, Radeon overlay, Mobile devices/Phone Link, Copilot, Teams, ChatGPT, Xbox, To Do, and similar. Hibernate, long paths, HKLM startup, Smart App Control Off, and the Widgets policy need elevation. Alt+Tab and some taskbar buttons may need a logoff (or Explorer restart) to take effect. Widgets (`TaskbarDa`) is ACL-locked on some Windows 11 builds; the Feeds policy is the fallback.

## Java

~24 JDKs (Temurin, Zulu, Corretto, Liberica 8–25; Microsoft 11–25).

Windows `setup/windows.ps1` installs this matrix via `bootstrap/java-windows.ps1` (idempotent). macOS and WSL still use the standalone scripts (not part of `setup.sh`).

macOS (download then run - needs a TTY for sudo `.pkg` passwords; `curl | bash` looks stuck):

```bash
curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/java-macos.sh -o /tmp/java-macos.sh
bash /tmp/java-macos.sh
```

```bash
# WSL
curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/java-wsl.sh | bash
# Windows (already run by windows.ps1; safe to re-run)
irm https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/java-windows.ps1 | iex
```

Switch: `java-use 21-temurin` (macOS/WSL) · `jv temurin21-jdk` (Windows).

## CLIs

`gh`, `atlassian-cli`, and `wrangler` (Cloudflare Pages/Workers) come with setup. Windows has no GitHub binary for `atlassian-cli`; setup compiles it with MSVC `link.exe` when present, otherwise Scoop `gcc` and the gnu rustc triple. Visual Studio 2022 Build Tools (C++ workload) are installed so `rustup-msvc` and UniGetUI rust packages can link.

```bash
gh auth login
atlassian-cli auth login --profile amartha --bitbucket --bearer --workspace Amartha
```

Amartha repos: `curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/scripts/sync-bitbucket-repos.sh | zsh` (1Password item `Amartha Bitbucket PR Review`).

Atlassian API tokens are per-app (scoped). Keep separate 1Password items:
- `Amartha Jira API` - Jira REST
- `Amartha Bitbucket PR Review` - Bitbucket PR / API
- `petruswiyadi-Bitbucket` - SSH for git push

## Browser extensions

macOS (opens store pages in installed browsers; not run by `setup.sh`):

```bash
~/dotfiles/bootstrap/browser-extensions.sh       # defaults
~/dotfiles/bootstrap/browser-extensions.sh all
```

Windows (not run by `windows.ps1`; browsers cannot silently install extensions):

```powershell
~\dotfiles\bootstrap\browser-extensions.ps1
~\dotfiles\bootstrap\browser-extensions.ps1 -All
```

Opens store pages for uBlock, 1Password, FDM (Lite on Chromium; full uBO on Firefox/Brave).

## Post-setup (Windows)

After `windows.ps1`, sign into 1Password, then:

```powershell
irm https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/post-setup.ps1 | iex
```

Configures `gh` and `atlassian-cli` from 1Password when tokens exist. Optional Bitbucket clone/sync (needs SSH agent):

```powershell
$s = $env:TEMP\post-setup.ps1
irm https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/post-setup.ps1 -OutFile $s
& $s -SyncBitbucket
```

## AI

`/grammar` · `/leetcode` · `/handoff` (Cursor, Claude, Copilot, Zai, Gemini/Antigravity, Codex). Caveman + ponytail via setup. [Impeccable](https://github.com/pbakaus/impeccable) design skills (`/impeccable`) install globally for Claude, Codex, Cursor, Gemini, OpenCode, and Pi. Hermes Agent, Pi Coding Agent, Oh My Pi (`omp`), [Reasonix](https://github.com/esengine/DeepSeek-Reasonix) (`reasonix`), [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (`dsh`; needs Node 22.19+ or 24+), OpenClaw, Kimi Code CLI, Antigravity CLI (`agy`), and [Goose](https://github.com/aaif-goose/goose) are installed as agent clients. Antigravity desktop (2.0) and Goose desktop are installed on macOS and Windows; WSL uses CLI agents (`agy`, `goose`) and reuses the Windows desktop apps.

Antigravity skills are linked into `~/.gemini/config/skills/` (works in Desktop + CLI + IDE). Product-specific roots (`antigravity/`, `antigravity-cli/`) are also filled. Skills with `disable-model-invocation` must be run as slash commands (e.g. `/grammar`), not auto-picked.

## Local AI

Ollama, LM Studio, and llama.cpp are installed on macOS and Windows. WSL installs the llama.cpp CLI, maps `ollama` to the Windows CLI when available, and reuses the Windows Ollama / LM Studio servers.

Models are not downloaded automatically. Start with `ollama run llama3.2`; use `llama --help` (WSL installer) or `llama-cli --help` (package-manager builds).

## Manual

Velja (App Store) · JetBrains via Toolbox · [Wavlink drivers](https://www.wavlink.com/en_us/Drivers.html) (DisplayLink is in setup on macOS and Windows; reboot after install). On Windows, DisplayLink may exit Winget 1603 until you reboot and re-run that ID elevated. Deskflow 1603 is usually an old VC++ runtime (needs 14.50+); setup upgrades `Microsoft.VCRedist.2015+.x64` before installing it. Windows also installs NetSpeedTray and TrafficMonitor Lite for taskbar network speed. Setup adds a Start Menu shortcut and autostart for TrafficMonitor, and turns on its taskbar window. Three-finger drag (macOS parity) is [ThreeFingerDragOnWindows](https://github.com/ClementGre/ThreeFingerDragOnWindows) (`9MSX91WQCM2V`); Windows three-finger Task View swipes are turned off so it can work. ROG Flow X13 gets [G-Helper](https://github.com/seerge/g-helper) (`seerge.g-helper`) as a lightweight Armoury Crate alternative; setup installs .NET 10 Desktop Runtime first. Do not run G-Helper and Armoury Crate at once.

macOS Podman uses `applehv` via `config/containers/containers.conf` (avoids libkrun/`krunkit --timesync` skew with Podman Desktop). New machines inherit that provider; stop or remove any leftover libkrun default machine if Desktop keeps trying to start it.

`kubectl`, `kind`, and `k3d` are installed by setup on macOS, Windows, and WSL. Clusters are not created automatically - run `kind create cluster` or `k3d cluster create` when you need one (Podman/Docker must be running).

## Notes

Mac + Android (iOS as a bonus): UpNote (App Store), Notesnook, Standard Notes, Joplin, Simplenote, Obsidian. Obsidian sync is separate. Windows gets the same notes set via Winget, plus LibreOffice and ONLYOFFICE.

Windows also installs the macOS GUI set where Winget has a package: extra browsers (LibreWolf, Waterfox, Mullvad, ungoogled Chromium, Chromium, Thorium, Min, Chrome Beta/Canary, Firefox ESR/Nightly, Opera / GX / Air), terminals (Alacritty, WezTerm, Tabby, Warp, Hyper, Windows Terminal), editors (Notepad++, VS Code), Everything, Files, UniGetUI, Patch My PC Home Updater, VLC, PotPlayer, K-Lite, Steam, EA App, VALORANT (AP), Spotify, Stremio, qBittorrent, Transmission, FDM, Postman, OpenVPN Connect, OpenCode desktop, and WhatsApp. Mac-only (no Windows package or no equivalent): iTerm, Ghostty, Orion, SigmaOS, Helium, Wispr Flow, CotEditor, IINA, Rectangle / DockDoor.

## Layout

```
setup.sh setup/   installers (macos.sh, windows.ps1, wsl.sh)
install.sh        symlinks (macOS/WSL; Windows copies via windows.ps1)
bootstrap/        java-*, macos.sh, browser-extensions.{sh,ps1}, post-setup.ps1
ai/ git/ go/ cursor/ shell/ config/ (nvim, zellij, zsh, containers) scripts/
```
