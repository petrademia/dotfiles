# Dotfiles

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/setup.sh -o setup.sh
zsh setup.sh
```

Requires sudo for first-time Homebrew install.

## Manual install

```bash
git clone https://github.com/petrademia/dotfiles.git ~/dotfiles
~/dotfiles/install.sh
```

## What's included

- Shell: zsh config, aliases, paths, AI key helper
- Go: `GOPRIVATE` for Amartha Bitbucket modules
- Git: Bitbucket SSH `insteadOf` for private Go module fetch; global hook strips Cursor commit trailers
- Tools: brew, fnm, cargo, sdkman, Claude Code, graphify, mas
- Terminals: Alacritty, Ghostty, Hyper, iTerm2, Kitty, Rio, Tabby, Warp, WezTerm
- Apps: 1Password, Brave, Codex app, Cursor, Discord, Firefox Dev, Floorp, Freetube, Helm, JetBrains Toolbox, LibreOffice, LibreWolf, Obsidian, OpenVPN, Podman, Postman, Scroll Reverser, Slack, Spotify, Unsplash Wallpapers, Vivaldi, VS Code, VLC
- Java bootstrap: 20 JDKs (Temurin, Zulu, Corretto, Liberica)

## macOS defaults

```bash
curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/macos.sh | zsh
```

Clears default Dock icons, sets: autohide, tilesize 48, Finder list view, clean desktop, fast key repeat, tap-to-click, three-finger drag, screenshots folder, battery percentage.

## Manual installs

- Velja - [App Store](https://apps.apple.com/app/id1607635845)
- JetBrains IDEs - via Toolbox
- RTK - [GitHub releases](https://github.com/rtk-ai/rtk/releases)

## Bitbucket sync

```bash
curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/scripts/sync-bitbucket-repos.sh | zsh
```

Requires 1Password item "Amartha Bitbucket" with username/password.

## Structure

```
dotfiles/
├── setup.sh          # Full install
├── install.sh        # Symlinks only
├── bootstrap/        # Java, macOS defaults
├── git/
│   ├── gitconfig         # Bitbucket insteadOf, name, Amartha includeIf
│   ├── amartha.gitconfig # Amartha email for ~/Amartha/ repos
│   └── hooks/            # Global prepare-commit-msg (strips Cursor trailers)
├── go/
│   └── env           # GOPRIVATE for Amartha Bitbucket modules
├── cursor/
│   └── cli-config.json  # Disable Cursor commit/PR attribution
├── scripts/          # Bitbucket sync
├── shell/.zshrc      # Shell loader
├── config/zsh/       # Shell modules
└── AGENTS.md         # AI tool guidelines
```
