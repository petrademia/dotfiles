# AGENTS.md

## General Guidelines

- Be concise.
- Be direct.
- State assumptions explicitly.
- Distinguish facts from opinions.
- Distinguish observations from conclusions.
- If uncertain, say so.
- Prefer practical recommendations over theoretical ones.
- Understand before changing.
- Investigate root causes before proposing fixes.

## Standards

- Never use the em dash "-". Use plain dash "-" instead.
- When writing commit messages, NEVER auto-add your agent name as co-author.
- Never manually modify CHANGELOG.md files or any files that are marked as auto-generated.
- When making technical decisions, do not give much weight to development cost. Instead, prefer quality, simplicity, robustness, scalability, and long term maintainability.
- When doing bug fixes, always start with reproducing the bug in an E2E setting as closely aligned with how an end user would experience it as possible. This makes sure you find the real problem so your fix will actually solve it.
- When end-to-end testing a product, be picky about the UI you see and be obsessed with pixel perfection. If something clearly looks off, even if it is not directly related to what you are doing, try to get it fixed along the way.
- Apply that same high standard to engineering excellence: lint, test failures, and test flakiness. If you see one, even if it is not caused by what you are working on right now, still get it fixed.

## Environment

### 1Password

Desktop app unlocked; **Settings > Developer**: turn on **Integrate with 1Password CLI** and **SSH Agent**. Keep 1Password in the system tray.

**Verify (any platform):** `op vault list` then `ssh -T git@github.com` (expect `Hi petrademia!`).

**Windows**

- AI keys: `Get-Keys` in PowerShell `$PROFILE` (from `setup/windows.ps1`).
- Git over SSH: `git config --global core.sshCommand` is System OpenSSH (`C:/Windows/System32/OpenSSH/ssh.exe`). Do not set `IdentityAgent` in `~/.ssh/config` (1Password uses the Windows pipe automatically).
- Disable the Windows **OpenSSH Authentication Agent** service (1Password replaces it).
- SSH keys in agent (from `config/1password/ssh-agent.toml`, synced to `%LOCALAPPDATA%\1Password\config\ssh\agent.toml`):
  - `SSH Key` - GitHub (`git@github.com`; `git/gitconfig` rewrites `https://github.com/` to SSH)
  - `petruswiyadi-Bitbucket` - Bitbucket git push
- `gh` (optional, for `gh api` / PRs): `bootstrap/post-setup.ps1` reads `GitHub CLI Token` (`credential`, `password`, or `token` field). **Git push uses SSH**, not `gh`.

**macOS / WSL**

- AI keys: `get-keys` in `~/.zshrc` (`config/zsh/ai.zsh`).
- Git SSH: 1Password SSH agent (`IdentityAgent` on macOS; WSL uses Windows `op.exe` when bridged).

**API tokens (not SSH)** - Amartha scopes are per app:

- Jira: `op://Personal/Amartha Jira API` (`username` + `password`)
- Bitbucket API / PR review: `op://Personal/Amartha Bitbucket PR Review` (`username` + `credential`)
