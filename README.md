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

- Shell: zsh config, aliases, paths, AI key helper, neovim
- Go: `GOPRIVATE` for Amartha Bitbucket modules
- Git: Bitbucket SSH `insteadOf` for private Go module fetch; global hook strips Cursor commit trailers
- Tools: brew, fnm, cargo, sdkman, Claude Code, graphify, mas
- AI: `/grammar` and `/leetcode` slash commands for Cursor, Claude, Copilot, Zai, Gemini, Codex/ChatGPT; caveman and ponytail plugins for Claude Code and ChatGPT/Codex
- Terminals: Alacritty, Ghostty, Hyper, iTerm2, Kitty, Rio, Tabby, Warp, WezTerm
- Apps: 1Password, Brave, ChatGPT (Classic), Codex (new unified ChatGPT desktop app), Cursor, Discord, Firefox Dev, Floorp, Freetube, Helm, JetBrains Toolbox, LibreOffice, LibreWolf, Obsidian, OpenVPN, Podman, Postman, Scroll Reverser, Slack, Spotify, Unsplash Wallpapers, Vivaldi, VS Code, VLC
- Java bootstrap: 20 JDKs (Temurin, Zulu, Corretto, Liberica) - see below

## macOS defaults

```bash
curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/macos.sh | zsh
```

Clears default Dock icons, sets: autohide, tilesize 48, Finder list view, clean desktop, fast key repeat, tap-to-click, three-finger drag, screenshots folder, battery percentage.

## Java bootstrap

Not run by `setup.sh`. Requires Homebrew and `~/dotfiles` (from setup or manual clone).

```bash
curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/java.sh | bash
```

Installs 20 JDK casks (Temurin, Zulu, Corretto, Liberica for 8/11/17/21/25) and writes `config/zsh/java.zsh` with a `java-use` helper. Reload shell, then switch JDKs:

```bash
java-use 21-temurin
java-use 17-corretto
```

## Manual installs

- Velja - [App Store](https://apps.apple.com/app/id1607635845)
- JetBrains IDEs - via Toolbox
- RTK - [GitHub releases](https://github.com/rtk-ai/rtk/releases)
- Wavlink - no Homebrew package. Drivers depend on chipset (DisplayLink, Silicon Motion InstantView, Realtek, etc.). Download for your model from [Wavlink Drivers](https://www.wavlink.com/en_us/Drivers.html). DisplayLink itself is installed by `setup.sh` via `brew install --cask displaylink` (reboot required).

## Bitbucket sync

```bash
curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/scripts/sync-bitbucket-repos.sh | zsh
```

Requires 1Password item "Amartha Bitbucket" with username/password.

## AI commands

Installed by `install.sh` as symlinks from `ai/`:

| Tool | Path | Invoke |
|---|---|---|
| Cursor | `~/.cursor/commands/{grammar,leetcode}.md` | `/grammar ...`, `/leetcode ...` |
| Claude Code | `~/.claude/commands/{grammar,leetcode}.md` | `/grammar ...`, `/leetcode ...` |
| Copilot CLI | `~/.claude/commands/{grammar,leetcode}.md` | `/grammar ...`, `/leetcode ...` |
| Zai | `~/.zai/commands/{grammar,leetcode}.md` | `/grammar ...`, `/leetcode ...` |
| Gemini CLI | `~/.gemini/commands/{grammar,leetcode}.toml` | `/grammar ...`, `/leetcode ...` |
| Codex CLI / ChatGPT app | `~/.agents/skills/{grammar,leetcode}/SKILL.md` | invoke the `grammar` / `leetcode` skill |

- `/grammar` - checks grammar, then executes your prompt.
- `/leetcode` - a coach that guides you to the solution with progressive hints instead of dumping the answer.

Canonical Markdown source: `ai/commands/*.md`. Gemini uses `ai/gemini/*.toml` (`{{args}}`). Codex/ChatGPT uses `ai/codex/<name>/SKILL.md` (also symlinked to legacy `~/.codex/skills/`).

## AI plugins (caveman, ponytail)

`setup.sh` installs these for both **Claude Code** and **Codex / ChatGPT app** (separate plugin systems).

After setup, restart the ChatGPT app and start a new thread. For ponytail, open `/hooks` in Codex mode and trust its lifecycle hooks.

Manual Codex install:

```bash
codex plugin marketplace add JuliusBrussee/caveman
codex plugin marketplace add DietrichGebert/ponytail
codex plugin add caveman@caveman
codex plugin add ponytail@ponytail
```

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
├── ai/
│   ├── commands/        # Shared slash commands (Markdown)
│   ├── gemini/          # Gemini TOML commands
│   └── codex/           # Codex/ChatGPT agent skills (SKILL.md)
├── scripts/          # Bitbucket sync
├── shell/.zshrc      # Shell loader
├── config/zsh/       # Shell modules
├── config/nvim/      # Neovim config
└── AGENTS.md         # AI tool guidelines
```
