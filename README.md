# Dotfiles

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/setup.sh -o setup.sh && bash setup.sh
```

Windows: `irm https://raw.githubusercontent.com/petrademia/dotfiles/main/setup/windows.ps1 | iex`

Or from a clone: `./setup.sh` (full) / `./install.sh` (symlinks only).

## macOS defaults

```bash
curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/macos.sh | zsh
```

## Java (optional)

~24 JDKs (Temurin, Zulu, Corretto, Liberica 8–25; Microsoft 11–25). Not part of `setup.sh`.

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

`gh` and `atlassian-cli` come with setup.

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

```bash
~/dotfiles/bootstrap/browser-extensions.sh       # defaults
~/dotfiles/bootstrap/browser-extensions.sh all
```

Opens store pages for uBlock, 1Password, FDM (Lite on Chromium; full uBO on Firefox/Brave).

## AI

`/grammar` · `/leetcode` · `/handoff` (Cursor, Claude, Copilot, Zai, Gemini/Antigravity, Codex). Caveman + ponytail via setup. [Impeccable](https://github.com/pbakaus/impeccable) design skills (`/impeccable`) install globally for Claude, Codex, Cursor, Gemini, OpenCode, and Pi. Hermes Agent, Pi Coding Agent, Oh My Pi (`omp`), [Reasonix](https://github.com/esengine/DeepSeek-Reasonix) (`reasonix`), OpenClaw, Kimi Code CLI, Antigravity CLI (`agy`), and [Goose](https://github.com/aaif-goose/goose) are installed as agent clients. Antigravity desktop (2.0) and Goose desktop are installed on macOS and Windows; WSL uses CLI agents (`agy`, `goose`) and reuses the Windows desktop apps.

Antigravity skills are linked into `~/.gemini/config/skills/` (works in Desktop + CLI + IDE). Product-specific roots (`antigravity/`, `antigravity-cli/`) are also filled. Skills with `disable-model-invocation` must be run as slash commands (e.g. `/grammar`), not auto-picked.

## Local AI

Ollama, LM Studio, and llama.cpp are installed on macOS and Windows. WSL installs the llama.cpp CLI, maps `ollama` to the Windows CLI when available, and reuses the Windows Ollama / LM Studio servers.

Models are not downloaded automatically. Start with `ollama run llama3.2`; use `llama --help` (WSL installer) or `llama-cli --help` (package-manager builds).

## Manual

Velja (App Store) · JetBrains via Toolbox · [RTK](https://github.com/rtk-ai/rtk/releases) · [Wavlink drivers](https://www.wavlink.com/en_us/Drivers.html) (DisplayLink is a brew cask in setup).

macOS Podman uses `applehv` via `config/containers/containers.conf` (avoids libkrun/`krunkit --timesync` skew with Podman Desktop). New machines inherit that provider; stop or remove any leftover libkrun default machine if Desktop keeps trying to start it.

`kubectl`, `kind`, and `k3d` are installed by setup on macOS, Windows, and WSL. Clusters are not created automatically - run `kind create cluster` or `k3d cluster create` when you need one (Podman/Docker must be running).

## Layout

```
setup.sh setup/   installers
install.sh        symlinks
bootstrap/        java-*, macos.sh, browser-extensions.sh
ai/ git/ go/ cursor/ shell/ config/ (nvim, zellij, zsh, containers) scripts/
```
