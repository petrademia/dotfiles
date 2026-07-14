# Dotfiles

## Install

`setup.sh` is an OS dispatcher: it detects the platform and runs the matching
script in `setup/` (`macos.sh`, `wsl.sh`). Windows uses `setup/windows.ps1`.

```bash
curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/setup.sh -o setup.sh
bash setup.sh
```

Run standalone, it clones the repo to `~/dotfiles` and dispatches from there.
Requires sudo for first-time Homebrew (macOS) / apt (WSL) installs.

Windows (PowerShell):

```powershell
irm https://raw.githubusercontent.com/petrademia/dotfiles/main/setup/windows.ps1 | iex
```

## Manual install

```bash
git clone https://github.com/petrademia/dotfiles.git ~/dotfiles
cd ~/dotfiles
./setup.sh          # full install (OS-detected)
./install.sh        # symlinks only (OS-aware paths)
```

## What's included

- Shell: zsh config, aliases, paths, AI key helper, neovim
- Go: `GOPRIVATE` for Amartha Bitbucket modules
- Git: Bitbucket SSH `insteadOf` for private Go module fetch; global hook strips Cursor commit trailers
- Tools: brew, fnm, cargo, sdkman, Claude Code, graphify, mas, `gh`, `atlassian-cli` (Bitbucket/Jira)
- AI: `/grammar` and `/leetcode` slash commands for Cursor, Claude, Copilot, Zai, Gemini, Codex/ChatGPT; caveman and ponytail plugins for Claude Code and ChatGPT/Codex
- Terminals: Alacritty, Ghostty, Hyper, iTerm2, Kitty, Rio, Tabby, Warp, WezTerm
- Apps: 1Password, Brave, ChatGPT (Classic), Codex (new unified ChatGPT desktop app), Cursor, Discord, Firefox Dev, Floorp, Freetube, Helm, JetBrains Toolbox, LibreOffice, LibreWolf, Obsidian, OpenVPN, Podman, Postman, Scroll Reverser, Slack, Spotify, Unsplash Wallpapers, Vivaldi, VS Code, VLC
- Java bootstrap: synced JDK matrix across macOS / WSL / Windows (Temurin, Zulu, Corretto, Liberica, Microsoft) - see below

## macOS defaults

```bash
curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/macos.sh | zsh
```

Clears default Dock icons, sets: autohide, tilesize 48, Finder list view (also clears `~/**/.DS_Store` so per-folder views stop overriding the default; leaves `/Applications` as icons), new windows → Home, search current folder, save-to-disk (not iCloud), expanded save/print panels, battery percentage, clean desktop, fast key repeat, tap-to-click, three-finger drag, PNG screenshots without shadow.

## Java bootstrap

Not run by `setup.sh` (heavy). Installs the same vendor/version matrix on each OS via that OS's package manager: **Temurin, Zulu, Corretto, Liberica** for 8/11/17/21/25, plus **Microsoft** for 11/17/21/25 (Microsoft ships no Java 8). That's 24 JDKs per platform.

| OS | Command | Manager | Switcher |
|---|---|---|---|
| macOS | `bootstrap/java-macos.sh` | Homebrew casks | `java-use 21-temurin` |
| WSL | `bootstrap/java-wsl.sh` | SDKMAN | `java-use 21-temurin` |
| Windows | `bootstrap/java-windows.ps1` | Scoop | `jv temurin21-jdk` |

macOS example (requires Homebrew and `~/dotfiles`):

```bash
curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/java-macos.sh | bash
```

`java-macos.sh` writes `config/zsh/java.zsh` with the `java-use` helper. WSL's `java-use` resolves installed SDKMAN identifiers; `setup/wsl.sh` installs a default JDK path via apt/SDKMAN, and Windows `setup.ps1` installs a single Temurin 21 by default. Reload the shell, then switch:

```bash
java-use 21-temurin
java-use 21-microsoft   # macOS / WSL
jv temurin21-jdk        # Windows
```

## Manual installs

- Velja - [App Store](https://apps.apple.com/app/id1607635845)
- JetBrains IDEs - via Toolbox
- RTK - [GitHub releases](https://github.com/rtk-ai/rtk/releases)
- Wavlink - no Homebrew package. Drivers depend on chipset (DisplayLink, Silicon Motion InstantView, Realtek, etc.). Download for your model from [Wavlink Drivers](https://www.wavlink.com/en_us/Drivers.html). DisplayLink itself is installed by `setup.sh` via `brew install --cask displaylink` (reboot required).

## GitHub + Bitbucket CLIs

`setup/macos.sh` installs:

- **`gh`** (Homebrew) - GitHub CLI + `gh-copilot` extension
- **`atlassian-cli`** (tap `omar16100/atlassian-cli`) - Bitbucket/Jira/Confluence; use `atlassian-cli bitbucket …` (alias: `atlassian-cli bb …`)

```bash
gh auth login
atlassian-cli auth login --profile amartha --bitbucket --bearer --workspace Amartha
atlassian-cli auth test --bitbucket --profile amartha
```

Use an [Atlassian API token](https://id.atlassian.com/manage-profile/security/api-tokens) (or Bitbucket workspace/repo access token). Prefer storing it in 1Password rather than a plaintext env var.

## Bitbucket sync

```bash
curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/scripts/sync-bitbucket-repos.sh | zsh
```

Requires 1Password item "Amartha Bitbucket" with username/password. Kept separate from `atlassian-cli` - this script is for bulk clone/sync of the Amartha workspace.

## Browser extensions

Browsers block silent extension installs by design, so this is a helper - not part of `setup.sh`. It opens the correct store page for each extension in the browsers you pick (click "Add" on each), auto-selecting the right uBlock variant per engine.

```bash
bootstrap/browser-extensions.sh                 # default: Chrome, Brave, Firefox, Edge
bootstrap/browser-extensions.sh all             # every installed supported browser
bootstrap/browser-extensions.sh "Google Chrome" "Firefox"
```

Extensions: uBlock Origin (Lite on Chromium, full on Firefox/Brave), 1Password, Free Download Manager.

- Full uBlock Origin no longer works on Chrome (Manifest V2 removed) - Chromium browsers get uBlock Origin **Lite**.
- Firefox/Brave get full uBlock Origin; LibreWolf and Mullvad usually ship it preinstalled.
- 1Password and FDM extensions require their desktop apps to function.
- For the least effort long-term, just use each browser's account sync.

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
├── setup.sh          # OS dispatcher (detects macOS / WSL)
├── setup/
│   ├── macos.sh          # Homebrew stack, AI tools, plugins, RTK
│   ├── wsl.sh            # apt stack mirroring macOS + Windows bridges
│   └── windows.ps1       # Windows setup (PowerShell)
├── install.sh        # Symlinks only (OS-aware paths)
├── bootstrap/        # java-macos.sh, java-wsl.sh, java-windows.ps1, macos.sh, browser-extensions.sh
├── git/
│   ├── gitconfig         # Bitbucket insteadOf, name, Amartha includeIf
│   ├── amartha.gitconfig # Amartha email for ~/Amartha/ repos
│   └── hooks/            # Global prepare-commit-msg + commit-msg (strip Cursor/Claude trailers)
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
