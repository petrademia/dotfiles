# Dotfiles

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/setup.sh -o setup.sh && bash setup.sh
```

Windows:

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
irm https://raw.githubusercontent.com/petrademia/dotfiles/main/setup/windows.ps1 | iex
```

The first line unlocks scripts (and your profile). Windows defaults to Restricted, which prints `running scripts is disabled` when PowerShell starts.

That script also enables WSL and installs Ubuntu (idempotent). Reboot if Windows asks, then inside Ubuntu:

```bash
curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/setup.sh | bash
```

Or from a clone: `./setup.sh` (full) / `./install.sh` (symlinks only).

## macOS defaults

```bash
curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/macos.sh | zsh
```

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
# Windows
irm https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/java-windows.ps1 | iex
```

Switch: `java-use 21-temurin` (macOS/WSL) · `jv temurin21-jdk` (Windows).

## CLIs

`gh`, `atlassian-cli`, and `wrangler` (Cloudflare Pages/Workers) come with setup.

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

macOS (opens store pages in installed browsers):

```bash
~/dotfiles/bootstrap/browser-extensions.sh       # defaults
~/dotfiles/bootstrap/browser-extensions.sh all
```

Windows:

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

Velja (App Store) · JetBrains via Toolbox · [Wavlink drivers](https://www.wavlink.com/en_us/Drivers.html) (DisplayLink is in setup on macOS and Windows; reboot after install). Windows also installs NetSpeedTray and TrafficMonitor Lite for taskbar network speed; enable TrafficMonitor's taskbar window once after first run.

## Notes

Mac + Android (iOS as a bonus): UpNote (App Store), Notesnook, Standard Notes, Joplin, Simplenote, Obsidian. Obsidian sync is separate. Windows gets the same set via Winget (UpNote, Notesnook, Standard Notes, Simplenote, Joplin, Obsidian).

## Manual

macOS Podman uses `applehv` via `config/containers/containers.conf` (avoids libkrun/`krunkit --timesync` skew with Podman Desktop). New machines inherit that provider; stop or remove any leftover libkrun default machine if Desktop keeps trying to start it.

`kubectl`, `kind`, and `k3d` are installed by setup on macOS, Windows, and WSL. Clusters are not created automatically - run `kind create cluster` or `k3d cluster create` when you need one (Podman/Docker must be running).

## Layout

```
setup.sh setup/   installers
install.sh        symlinks
bootstrap/        java-*, macos.sh, browser-extensions.{sh,ps1}, post-setup.ps1
ai/ git/ go/ cursor/ shell/ config/ (nvim, zellij, zsh, containers) scripts/
```
