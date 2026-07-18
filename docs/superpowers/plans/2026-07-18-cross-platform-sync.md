# Cross-Platform Setup Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give macOS and Windows the selected desktop baseline while making Windows and WSL share the same development, AI, editor, and Git configuration.

**Architecture:** Keep desktop applications on each host and WSL CLI-only. Make `install.sh` safe on Linux by gating macOS shell links, call it from WSL, and add equivalent PowerShell synchronization for Windows.

**Tech Stack:** Zsh/Bash, PowerShell, Homebrew, Scoop, Winget, Git.

## Global Constraints

- Do not invent packages or force platform-specific applications onto another OS.
- Windows owns browsers, cloud drives, GUI editors, chat apps, and Podman Desktop.
- WSL owns command-line development tools and reuses Windows GUI applications.
- Setup remains repeatable and skips existing installations.

---

### Task 1: Add a static parity check

**Files:**
- Create: `scripts/check-setup-parity.sh`

**Interfaces:**
- Consumes: repository root inferred from the script location.
- Produces: exit status 0 only when required cross-platform setup markers exist.

- [ ] Write a shell check that asserts the Windows Node bootstrap, selected Winget IDs, WSL shared installer call, Atlassian CLI installation, and macOS pending casks.
- [ ] Run `bash scripts/check-setup-parity.sh`.
- [ ] Confirm it fails because Windows and WSL are not synchronized yet.

### Task 2: Make shared configuration portable

**Files:**
- Modify: `install.sh`
- Modify: `setup/wsl.sh`
- Modify: `setup/windows.ps1`

**Interfaces:**
- `install.sh` installs OS-neutral assets everywhere and macOS zsh assets only on Darwin.
- WSL calls `"$DOTFILES/install.sh"` after cloning.
- Windows clones `~/dotfiles`, copies shared assets to native locations, and points Git directly at repository config/hooks.

- [ ] Gate `.zshrc` and `config/zsh` links in `install.sh` behind `uname -s = Darwin`.
- [ ] Call `install.sh` from WSL before injecting the WSL shell block.
- [ ] Add a minimal PowerShell `Sync-Dotfile` helper and synchronize AGENTS, Claude, Neovim, Cursor, AI commands/skills, Go env, Git include, and hooks.
- [ ] Run `bash -n install.sh setup/wsl.sh`.

### Task 3: Synchronize runtimes and host applications

**Files:**
- Modify: `setup/macos.sh`
- Modify: `setup/windows.ps1`
- Modify: `setup/wsl.sh`

**Interfaces:**
- Windows initializes Node LTS before npm tools.
- Windows Winget list includes verified host application IDs.
- Windows and WSL install `atlassian-cli` through Cargo after Rust is initialized.

- [ ] Retain `zen`, `google-drive`, and `onedrive` in macOS setup and make optional cask failures non-fatal.
- [ ] Add verified Windows IDs: `Google.Chrome`, `Zen-Team.Zen-Browser`, `Google.GoogleDrive`, `Microsoft.OneDrive`, `Microsoft.VisualStudioCode`, `SlackTechnologies.Slack`, and `Discord.Discord`.
- [ ] Initialize `fnm` and Node LTS before the Windows npm block.
- [ ] Initialize Rust before installing `atlassian-cli` with Cargo on Windows.
- [ ] Install `atlassian-cli` with Cargo on WSL.
- [ ] Run the parity check and shell syntax checks.

### Task 4: Verify the complete change

**Files:**
- Verify: `scripts/check-setup-parity.sh`
- Verify: `install.sh`
- Verify: `setup/macos.sh`
- Verify: `setup/windows.ps1`
- Verify: `setup/wsl.sh`

- [ ] Run `bash scripts/check-setup-parity.sh`.
- [ ] Run `bash -n install.sh setup/wsl.sh scripts/check-setup-parity.sh`.
- [ ] Run `zsh -n setup/macos.sh`.
- [ ] Parse `setup/windows.ps1` with PowerShell if `pwsh` is available.
- [ ] Review `git diff --check` and the final diff.
