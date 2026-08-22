# AGENTS.md - dotfiles repo

Global personal standards (in `~/AGENTS.md`) also apply here. This file adds rules specific to this dotfiles repo.

## What this repo is

Reproducible macOS/Windows/WSL setup via Homebrew, Scoop/Winget, copies or symlinks, and bootstrap scripts.

- `setup.sh`, `setup/` - package install (`macos.sh`, `windows.ps1`, `wsl.sh`).
- `install.sh` - symlinks dotfiles into `$HOME` on macOS/WSL. Windows copies the same files from `setup/windows.ps1`.
- `bootstrap/` - one-off provisioners (java, macOS defaults, browser extensions, Windows post-setup).
- `ai/` - AI slash commands and skills shared across tools.
- `global/AGENTS.md` - source for the global `~/AGENTS.md` and `~/.claude/CLAUDE.md`.

## Conventions

- Add a new app/tool in the matching `setup/` script, then keep `README.md` notes (Install, Java, CLIs, Manual) in sync when the change needs a user-facing step.
- Add a new dotfile by adding a `link` line in `install.sh` (macOS/WSL) and a `Sync-Dotfile` call in `setup/windows.ps1` when Windows should get it too. Never hand-create symlinks.
- Keep AI commands in sync across all variants: `ai/commands/*.md` (Cursor/Claude/Zai), `ai/gemini/*.toml`, `ai/codex/*/SKILL.md`.
- Bootstrap scripts must be safe and idempotent. Skip already-installed items and continue on individual failures.
- Scripts fetched via `curl | bash` cannot prompt for `sudo`; anything needing `sudo` (e.g. `.pkg` installs) must be download-then-run.
