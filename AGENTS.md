# AGENTS.md - dotfiles repo

Global personal standards (in `~/AGENTS.md`) also apply here. This file adds rules specific to this dotfiles repo.

## What this repo is

Reproducible macOS/Windows/WSL setup via Homebrew, symlinks, and bootstrap scripts.

- `setup.sh`, `setup/` - package install (Homebrew formulas/casks, npm, CLIs).
- `install.sh` - symlinks dotfiles into `$HOME`.
- `bootstrap/` - one-off provisioners (java, macOS defaults, browser extensions).
- `ai/` - AI slash commands and skills shared across tools.
- `global/AGENTS.md` - source for the global `~/AGENTS.md` and `~/.claude/CLAUDE.md`.

## Conventions

- Add a new app/tool in `setup.sh` (or `setup/macos.sh`), then keep `README.md` "What's included" / apps list in sync.
- Add a new dotfile by adding a `link` line in `install.sh`; never hand-create symlinks.
- Keep AI commands in sync across all variants: `ai/commands/*.md` (Cursor/Claude/Zai), `ai/gemini/*.toml`, `ai/codex/*/SKILL.md`.
- Bootstrap scripts must be safe and idempotent. Skip already-installed items and continue on individual failures.
- Scripts fetched via `curl | bash` cannot prompt for `sudo`; anything needing `sudo` (e.g. `.pkg` installs) must be download-then-run.
