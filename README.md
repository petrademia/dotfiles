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

```bash
# macOS
curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/java-macos.sh | bash
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

Amartha repos: `curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/scripts/sync-bitbucket-repos.sh | zsh` (1Password item `Amartha Bitbucket`).

## Browser extensions

```bash
~/dotfiles/bootstrap/browser-extensions.sh       # defaults
~/dotfiles/bootstrap/browser-extensions.sh all
```

Opens store pages for uBlock, 1Password, FDM (Lite on Chromium; full uBO on Firefox/Brave).

## AI

`/grammar` · `/leetcode` (Cursor, Claude, Copilot, Zai, Gemini, Codex). Caveman + ponytail via setup.

## Manual

Velja (App Store) · JetBrains via Toolbox · [RTK](https://github.com/rtk-ai/rtk/releases) · [Wavlink drivers](https://www.wavlink.com/en_us/Drivers.html) (DisplayLink is a brew cask in setup).

## Layout

```
setup.sh setup/   installers
install.sh        symlinks
bootstrap/        java-*, macos.sh, browser-extensions.sh
ai/ git/ go/ cursor/ shell/ config/ scripts/
```
