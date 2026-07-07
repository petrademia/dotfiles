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
- Tools: brew, fnm, cargo, sdkman, Claude Code, graphify
- Terminals: Alacritty, Ghostty, Hyper, iTerm2, Kitty, Rio, Tabby, Warp, WezTerm
- Apps: 1Password, Brave, Cursor, Discord, Firefox Dev, Floorp, Freetube, Helm, JetBrains Toolbox, LibreOffice, LibreWolf, Obsidian, OpenVPN, Podman, Postman, Slack, Spotify, Vivaldi, VS Code, VLC
- Java bootstrap: 20 JDKs (Temurin, Zulu, Corretto, Liberica)

## macOS defaults

```bash
~/dotfiles/bootstrap/macos.sh
```

Run once or when needed. Restarts Dock/Finder. Sets: autohide, tilesize 48, Finder extensions, fast key repeat, tap-to-click, three-finger drag, screenshots folder, battery percentage.

## Manual installs

- Velja - [App Store](https://apps.apple.com/app/id1607635845)
- JetBrains IDEs - via Toolbox
- RTK - [GitHub releases](https://github.com/rtk-ai/rtk/releases)


```bash
```


## Structure

```
dotfiles/
├── setup.sh          # Full install
├── install.sh        # Symlinks only
├── bootstrap/        # Java, macOS defaults
├── shell/.zshrc      # Shell loader
├── config/zsh/       # Shell modules
└── AGENTS.md         # AI tool guidelines
```
